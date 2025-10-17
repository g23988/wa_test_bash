#!/usr/bin/env bash

# Security Pillar 檢查 - AWS Well-Architected Framework
# 安全性支柱 - 詳細檢查版本

set -euo pipefail

ACCOUNT_ID=$1
REGION=$2
TIMESTAMP=$3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
REPORTS_DIR="$PROJECT_ROOT/reports"

# 顏色定義
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[SECURITY]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SECURITY]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[SECURITY]${NC} $1"
}

log_error() {
    echo -e "${RED}[SECURITY]${NC} $1"
}

# 輸出文件
OUTPUT_FILE="$REPORTS_DIR/security_${TIMESTAMP}.json"
DETAILED_OUTPUT_FILE="$REPORTS_DIR/security_detailed_${TIMESTAMP}.jsonl"

log_info "開始 Security 支柱詳細檢查..."

# 工具函數
emit() {
    local check="$1" resource="$2" region="$3" status="$4" severity="$5" details="$6"
    jq -c -n --arg ts "$TIMESTAMP" --arg acct "$ACCOUNT_ID" \
        --arg check "$check" --arg res "$resource" --arg reg "$region" \
        --arg status "$status" --arg sev "$severity" --arg details "$details" \
        '{timestamp:$ts,account_id:$acct,check:$check,resource:$res,region:$reg,status:$status,severity:$sev,details:$details}' >> "$DETAILED_OUTPUT_FILE"
}

aws_try() {
    local region="$1"; shift
    if [[ "$region" == "global" ]]; then
        if ! out="$("$@" 2> >(stderr=$(cat); typeset -p stderr > /dev/null))"; then
            local err="$(typeset -p stderr 2>/dev/null | sed -E 's/^declare -x stderr="(.*)"$/\1/' | sed 's/\r//g')"
            echo "__ERROR__:$err"; return 1
        fi
    else
        if ! out="$("$@" --region "$region" 2> >(stderr=$(cat); typeset -p stderr > /dev/null))"; then
            local err="$(typeset -p stderr 2>/dev/null | sed -E 's/^declare -x stderr="(.*)"$/\1/' | sed 's/\r//g')"
            echo "__ERROR__:$err"; return 1
        fi
    fi
    echo "$out"; return 0
}

days_since() {
    python3 - <<'PY' "$1"
import sys, datetime
s=sys.argv[1]
dt=datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
now=datetime.datetime.now(datetime.timezone.utc)
print(int((now-dt).total_seconds()//86400))
PY
}

days_until() {
    python3 - <<'PY' "$1"
import sys, datetime
s=sys.argv[1]
dt=datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
now=datetime.datetime.now(datetime.timezone.utc)
print(int((dt-now).total_seconds()//86400))
PY
}

# 初始化詳細輸出文件
echo "" > "$DETAILED_OUTPUT_FILE"

# ========== 全域檢查 (IAM, S3, CloudFront) ==========

check_root_mfa() {
    local r="global"
    log_info "檢查 Root 帳戶 MFA..."
    if out="$(aws iam get-account-summary 2>/dev/null)"; then
        local enabled="$(echo "$out" | jq -r '.SummaryMap.AccountMFAEnabled')"
        [[ "$enabled" == "1" ]] \
            && emit "IAM:RootMFAEnabled" "root" "$r" "OK" "HIGH" "Root MFA enabled" \
            || emit "IAM:RootMFAEnabled" "root" "$r" "FAIL" "CRITICAL" "Root MFA NOT enabled"
    else
        emit "IAM:RootMFAEnabled" "root" "$r" "INFO" "HIGH" "AccessDenied or no permission"
    fi
}

check_iam_users_mfa_and_keys() {
    local r="global"
    log_info "檢查 IAM 使用者 MFA 和存取金鑰..."
    users="$(aws iam list-users --query 'Users[].UserName' --output json 2>/dev/null || echo '[]')"
    
    for u in $(echo "$users" | jq -r '.[]'); do
        # MFA 檢查
        mfa_cnt="$(aws iam list-mfa-devices --user-name "$u" --query 'length(MFADevices)' --output text 2>/dev/null || echo 0)"
        [[ "$mfa_cnt" -gt 0 ]] \
            && emit "IAM:UserMFA" "$u" "$r" "OK" "MEDIUM" "User has MFA" \
            || emit "IAM:UserMFA" "$u" "$r" "FAIL" "HIGH" "User has NO MFA"
        
        # 存取金鑰檢查
        keys="$(aws iam list-access-keys --user-name "$u" --output json 2>/dev/null || echo '{"AccessKeyMetadata":[]}')"
        echo "$keys" | jq -c '.AccessKeyMetadata[]?' | while read -r k; do
            kid="$(echo "$k" | jq -r '.AccessKeyId')"
            created="$(echo "$k" | jq -r '.CreateDate')"
            status="$(echo "$k" | jq -r '.Status')"
            age="$(days_since "$created" 2>/dev/null || echo 0)"
            
            st="OK"; sev="LOW"
            [[ "$status" != "Active" ]] && { st="INFO"; sev="INFO"; }
            [[ "$status" == "Active" && "$age" -ge 90 ]] && { st="WARN"; sev="MEDIUM"; }
            
            emit "IAM:AccessKeyAge" "$u/$kid" "$r" "$st" "$sev" "age_days=$age,status=$status,created=$created"
        done
    done
}

check_iam_policy_wildcards() {
    local r="global"
    log_info "檢查 IAM 政策萬用字元..."
    arns="$(aws iam list-policies --scope Local --only-attached --query 'Policies[].Arn' --output json 2>/dev/null || echo '[]')"
    
    for arn in $(echo "$arns" | jq -r '.[]'); do
        ver="$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || true)"
        [[ -z "$ver" ]] && { emit "IAM:PolicyWildcard" "$arn" "$r" "INFO" "LOW" "No permission to read version"; continue; }
        
        doc="$(aws iam get-policy-version --policy-arn "$arn" --version-id "$ver" --query 'PolicyVersion.Document' --output json 2>/dev/null || echo '{}')"
        if echo "$doc" | jq -e '
            .Statement as $s |
            ( ($s|type=="array")? $s : [$s]) |
            map(
                ( .Action|tostring|test("\\*") ) or
                ( (.Action|arrays|map(tostring)|join(","))? // "" | test("\\*") ) or
                ( .Resource|tostring|test("\\*") ) or
                ( (.Resource|arrays|map(tostring)|join(","))? // "" | test("\\*") )
            ) | any
        ' >/dev/null; then
            emit "IAM:PolicyWildcard" "$arn" "$r" "WARN" "MEDIUM" "Wildcard in Action/Resource"
        else
            emit "IAM:PolicyWildcard" "$arn" "$r" "OK" "LOW" "No obvious wildcards"
        fi
    done
}

check_s3_security() {
    local r="global"
    log_info "檢查 S3 安全配置..."
    buckets="$(aws s3api list-buckets --query 'Buckets[].Name' --output json 2>/dev/null || echo '[]')"
    
    for b in $(echo "$buckets" | jq -r '.[]'); do
        # Public Access Block 檢查
        pab="$(aws s3api get-public-access-block --bucket "$b" --output json 2>/dev/null || echo '{}')"
        pubblocked="$(echo "$pab" | jq -r '.PublicAccessBlockConfiguration | [ .BlockPublicAcls, .IgnorePublicAcls, .BlockPublicPolicy, .RestrictPublicBuckets ] | all' 2>/dev/null || echo false)"
        [[ "$pubblocked" == "true" ]] \
            && emit "S3:PublicAccessBlock" "$b" "$r" "OK" "HIGH" "Full PublicAccessBlock" \
            || emit "S3:PublicAccessBlock" "$b" "$r" "WARN" "HIGH" "Not fully enabled"
        
        # 公開政策檢查
        pols="$(aws s3api get-bucket-policy-status --bucket "$b" --output json 2>/dev/null || echo '{}')"
        ispublic="$(echo "$pols" | jq -r '.PolicyStatus.IsPublic' 2>/dev/null || echo 'false')"
        [[ "$ispublic" == "true" ]] \
            && emit "S3:BucketPublic" "$b" "$r" "FAIL" "HIGH" "Bucket policy is PUBLIC" \
            || emit "S3:BucketPublic" "$b" "$r" "OK" "HIGH" "Not public by policy"
        
        # 預設加密檢查
        if enc="$(aws s3api get-bucket-encryption --bucket "$b" --output json 2>/dev/null)"; then
            algo="$(echo "$enc" | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm')"
            emit "S3:DefaultEncryption" "$b" "$r" "OK" "MEDIUM" "SSE=$algo"
        else
            emit "S3:DefaultEncryption" "$b" "$r" "FAIL" "MEDIUM" "No default encryption"
        fi
        
        # Object Ownership 檢查
        oc="$(aws s3api get-bucket-ownership-controls --bucket "$b" --output json 2>/dev/null || echo '{}')"
        setting="$(echo "$oc" | jq -r '.OwnershipControls.Rules[0].ObjectOwnership // empty')"
        if [[ "$setting" == "BucketOwnerEnforced" ]]; then
            emit "S3:ObjectOwnership" "$b" "$r" "OK" "MEDIUM" "BucketOwnerEnforced (ACLs disabled)"
        elif [[ -n "$setting" ]]; then
            emit "S3:ObjectOwnership" "$b" "$r" "WARN" "MEDIUM" "ObjectOwnership=$setting (consider BucketOwnerEnforced)"
        else
            emit "S3:ObjectOwnership" "$b" "$r" "INFO" "LOW" "OwnershipControls not set or AccessDenied"
        fi
        
        # ACL 公開檢查
        acl="$(aws s3api get-bucket-acl --bucket "$b" --output json 2>/dev/null || echo '{}')"
        pub_grant="$(echo "$acl" | jq -r '
            [.Grants[]? | select(.Grantee.URI? and (.Grantee.URI|test("AllUsers|AuthenticatedUsers"))) ] | length')"
        if [[ "$pub_grant" -gt 0 ]]; then
            emit "S3:BucketACLPublic" "$b" "$r" "FAIL" "HIGH" "ACL grants to AllUsers/AuthenticatedUsers"
        else
            emit "S3:BucketACLPublic" "$b" "$r" "OK" "LOW" "No public ACL grants detected"
        fi
    done
}

check_cloudfront_security() {
    local r="global"
    log_info "檢查 CloudFront 安全配置..."
    dists="$(aws_try "$r" aws cloudfront list-distributions --output json)"
    if [[ "$dists" == __ERROR__* ]]; then
        emit "CloudFront:Distributions" "-" "$r" "INFO" "HIGH" "AccessDenied or no CloudFront"
        return
    fi
    
    echo "$dists" | jq -c '.DistributionList.Items[]?' | while read -r d; do
        id="$(echo "$d" | jq -r '.Id')"
        domain="$(echo "$d" | jq -r '.DomainName')"
        vpp="$(echo "$d" | jq -r '.DefaultCacheBehavior.ViewerProtocolPolicy')"
        mpv="$(echo "$d" | jq -r '.ViewerCertificate.MinimumProtocolVersion // empty')"
        
        # HTTPS 檢查
        if [[ "$vpp" == "https-only" ]]; then
            vpp_status="OK"
        elif [[ "$vpp" == "redirect-to-https" ]]; then
            vpp_status="WARN"
        else
            vpp_status="FAIL"
        fi
        
        # TLS 版本檢查
        case "$mpv" in
            TLSv1*|SSLv3*) tls_status="FAIL"; tls_note="MinimumProtocolVersion=$mpv (too old; require >= TLSv1.2_2019)";;
            TLSv1.1_2016) tls_status="FAIL"; tls_note="TLSv1.1 (deprecated)";;
            TLSv1.2_2018|TLSv1.2_2019) tls_status="OK"; tls_note=">= TLSv1.2_2019";;
            TLSv1.2_2021|TLSv1.3_2021|TLSv1.3_2024) tls_status="OK"; tls_note="$mpv";;
            *) tls_status="INFO"; tls_note="MinimumProtocolVersion=$mpv";;
        esac
        
        emit "CloudFront:ViewerProtocolPolicy" "$id($domain)" "$r" "$vpp_status" "MEDIUM" "ViewerProtocolPolicy=$vpp"
        emit "CloudFront:MinimumTLS" "$id($domain)" "$r" "$tls_status" "HIGH" "$tls_note"
    done
}

# ========== 區域性檢查 ==========

check_cloudtrail() {
    local region="$1"
    log_info "檢查 CloudTrail (區域: $region)..."
    out="$(aws_try "$region" aws cloudtrail describe-trails --include-shadow-trails --output json)"
    if [[ "$out" == __ERROR__* ]]; then
        emit "CloudTrail:Enabled" "-" "$region" "INFO" "HIGH" "AccessDenied or not permitted"
        return
    fi
    
    count="$(echo "$out" | jq '.trailList | length')"
    [[ "$count" -eq 0 ]] && emit "CloudTrail:Enabled" "-" "$region" "FAIL" "HIGH" "No trails" && return
    
    echo "$out" | jq -c '.trailList[]' | while read -r t; do
        name="$(echo "$t" | jq -r '.Name')"
        st="$(aws_try "$region" aws cloudtrail get-trail-status --name "$name" --output json)"
        if [[ "$st" == __ERROR__* ]]; then
            emit "CloudTrail:Status" "$name" "$region" "INFO" "HIGH" "No permission to get status"
        else
            logging="$(echo "$st" | jq -r '.IsLogging // false')"
            lfv="$(aws cloudtrail get-trail --name "$name" --region "$region" --output json 2>/dev/null | jq -r '.Trail.LogFileValidationEnabled // false')"
            status="OK"
            [[ "$logging" != "true" ]] && status="FAIL"
            [[ "$lfv" != "true" && "$status" == "OK" ]] && status="WARN"
            emit "CloudTrail:Status" "$name" "$region" "$status" "HIGH" "IsLogging=$logging,LogFileValidation=$lfv"
        fi
    done
}

check_ebs_encryption() {
    local region="$1"
    log_info "檢查 EBS 預設加密 (區域: $region)..."
    en="$(aws_try "$region" aws ec2 get-ebs-encryption-by-default --query 'EbsEncryptionByDefault' --output text)"
    if [[ "$en" == __ERROR__* ]]; then
        emit "EBS:DefaultEncryption" "-" "$region" "INFO" "MEDIUM" "AccessDenied"
    else
        [[ "$en" == "true" ]] && emit "EBS:DefaultEncryption" "-" "$region" "OK" "MEDIUM" "Enabled" \
            || emit "EBS:DefaultEncryption" "-" "$region" "FAIL" "MEDIUM" "Not enabled"
    fi
}

check_security_groups() {
    local region="$1"
    log_info "檢查 Security Groups 開放管理埠 (區域: $region)..."
    sgs="$(aws_try "$region" aws ec2 describe-security-groups --output json)"
    if [[ "$sgs" == __ERROR__* ]]; then
        emit "EC2:SGOpenAdminPorts" "-" "$region" "INFO" "HIGH" "AccessDenied"
        return
    fi
    
    echo "$sgs" | jq -c '.SecurityGroups[]?' | while read -r sg; do
        id="$(echo "$sg" | jq -r '.GroupId')"
        name="$(echo "$sg" | jq -r '.GroupName')"
        hit="$(echo "$sg" | jq '
            .IpPermissions[]? as $p |
            ($p.FromPort // -1) as $fp |
            ($p.ToPort // -1) as $tp |
            ($p.IpRanges[]?.CidrIp // empty) as $cidr |
            select(($cidr=="0.0.0.0/0") and (
                ($fp<=22 and $tp>=22) or ($fp<=3389 and $tp>=3389)
            ))
        ' -c)"
        [[ -n "$hit" ]] && emit "EC2:SGOpenAdminPorts" "$id($name)" "$region" "FAIL" "HIGH" "Open 22/3389 to world"
    done
}

check_rds_security() {
    local region="$1"
    log_info "檢查 RDS 安全配置 (區域: $region)..."
    dbs="$(aws_try "$region" aws rds describe-db-instances --output json)"
    if [[ "$dbs" == __ERROR__* ]]; then
        emit "RDS:PubliclyAccessible" "-" "$region" "INFO" "MEDIUM" "AccessDenied"
        return
    fi
    
    echo "$dbs" | jq -c '.DBInstances[]?' | while read -r db; do
        id="$(echo "$db" | jq -r '.DBInstanceIdentifier')"
        pub="$(echo "$db" | jq -r '.PubliclyAccessible')"
        enc="$(echo "$db" | jq -r '.StorageEncrypted')"
        
        [[ "$pub" == "true" ]] && emit "RDS:PubliclyAccessible" "$id" "$region" "WARN" "MEDIUM" "PubliclyAccessible=true"
        [[ "$enc" != "true" ]] && emit "RDS:StorageEncrypted" "$id" "$region" "FAIL" "HIGH" "StorageEncrypted=false"
    done
}

check_kms_rotation() {
    local region="$1"
    log_info "檢查 KMS 金鑰輪換 (區域: $region)..."
    keys="$(aws_try "$region" aws kms list-keys --query 'Keys[].KeyId' --output json)"
    if [[ "$keys" == __ERROR__* ]]; then
        emit "KMS:RotationEnabled" "-" "$region" "INFO" "LOW" "AccessDenied"
        return
    fi
    
    for k in $(echo "$keys" | jq -r '.[]'); do
        m="$(aws_try "$region" aws kms get-key-rotation-status --key-id "$k" --query 'KeyRotationEnabled' --output text)"
        if [[ "$m" == __ERROR__* ]]; then
            emit "KMS:RotationEnabled" "$k" "$region" "INFO" "LOW" "No permission"
        else
            [[ "$m" == "true" ]] && emit "KMS:RotationEnabled" "$k" "$region" "OK" "LOW" "Enabled" \
                || emit "KMS:RotationEnabled" "$k" "$region" "WARN" "LOW" "Not enabled"
        fi
    done
}

check_acm_certificates() {
    local region="$1"
    log_info "檢查 ACM 憑證到期 (區域: $region)..."
    cert_arns="$(aws_try "$region" aws acm list-certificates --certificate-statuses ISSUED PENDING_VALIDATION INACTIVE EXPIRED \
        --query 'CertificateSummaryList[].CertificateArn' --output json)"
    if [[ "$cert_arns" == __ERROR__* ]]; then
        emit "ACM:Expiry" "-" "$region" "INFO" "MEDIUM" "AccessDenied or ACM unsupported in region"
        return
    fi
    
    for arn in $(echo "$cert_arns" | jq -r '.[]'); do
        desc="$(aws_try "$region" aws acm describe-certificate --certificate-arn "$arn" --output json)"
        if [[ "$desc" == __ERROR__* ]]; then
            emit "ACM:Expiry" "$arn" "$region" "INFO" "LOW" "No permission to describe-certificate"
            continue
        fi
        
        not_after="$(echo "$desc" | jq -r '.Certificate.NotAfter')"
        status="$(echo "$desc" | jq -r '.Certificate.Status')"
        domain="$(echo "$desc" | jq -r '.Certificate.DomainName')"
        days="$(days_until "$not_after" 2>/dev/null || echo -99999)"
        
        st="OK"; sev="LOW"
        if (( days < 0 )); then
            st="FAIL"; sev="CRITICAL"
        elif (( days <= 7 )); then
            st="FAIL"; sev="HIGH"
        elif (( days <= 30 )); then
            st="WARN"; sev="MEDIUM"
        elif (( days <= 60 )); then
            st="WARN"; sev="LOW"
        fi
        
        emit "ACM:Expiry" "$domain ($arn)" "$region" "$st" "$sev" "days_until=$days,status=$status,not_after=$not_after"
    done
}

# ========== 執行檢查 ==========

log_info "執行全域安全檢查..."
check_root_mfa
check_iam_users_mfa_and_keys
check_iam_policy_wildcards
check_s3_security
check_cloudfront_security

log_info "執行區域性安全檢查 (區域: $REGION)..."
check_cloudtrail "$REGION"
check_ebs_encryption "$REGION"
check_security_groups "$REGION"
check_rds_security "$REGION"
check_kms_rotation "$REGION"
check_acm_certificates "$REGION"

# ========== 生成報告 ==========

log_info "生成安全檢查報告..."

# 統計結果
TOTAL_CHECKS=$(wc -l < "$DETAILED_OUTPUT_FILE" | tr -d ' ')
CRITICAL_ISSUES=$(grep '"severity":"CRITICAL"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')
HIGH_ISSUES=$(grep '"severity":"HIGH"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')
MEDIUM_ISSUES=$(grep '"severity":"MEDIUM"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')
FAILED_CHECKS=$(grep '"status":"FAIL"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')
WARNING_CHECKS=$(grep '"status":"WARN"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')

# 生成 JSON 報告
cat > "$OUTPUT_FILE" << EOF
{
  "pillar": "Security",
  "account_id": "$ACCOUNT_ID",
  "region": "$REGION",
  "timestamp": "$TIMESTAMP",
  "summary": {
    "total_checks": $TOTAL_CHECKS,
    "critical_issues": $CRITICAL_ISSUES,
    "high_issues": $HIGH_ISSUES,
    "medium_issues": $MEDIUM_ISSUES,
    "failed_checks": $FAILED_CHECKS,
    "warning_checks": $WARNING_CHECKS
  },
  "detailed_results_file": "security_detailed_${TIMESTAMP}.jsonl",
  "key_findings": [
EOF

# 添加關鍵發現
if [[ $CRITICAL_ISSUES -gt 0 ]]; then
    echo '    "發現 '$CRITICAL_ISSUES' 個嚴重安全問題，需要立即處理",' >> "$OUTPUT_FILE"
fi
if [[ $HIGH_ISSUES -gt 0 ]]; then
    echo '    "發現 '$HIGH_ISSUES' 個高風險安全問題",' >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF
    "詳細檢查結果請參考 security_detailed_${TIMESTAMP}.jsonl 文件"
  ],
  "recommendations": [
    "啟用 Root 帳戶 MFA 多重身份驗證",
    "為所有 IAM 使用者啟用 MFA",
    "定期輪換 IAM 存取金鑰 (建議 90 天內)",
    "檢查並移除 IAM 政策中的萬用字元權限",
    "啟用 S3 儲存桶公開存取封鎖",
    "為 S3 儲存桶啟用預設加密",
    "檢查並修正過於寬鬆的 Security Group 規則",
    "啟用 EBS 預設加密",
    "啟用 CloudTrail 並確保記錄檔驗證",
    "為 RDS 執行個體啟用儲存加密",
    "啟用 KMS 金鑰自動輪換",
    "監控 ACM 憑證到期時間",
    "CloudFront 分發使用 HTTPS-only 和現代 TLS 版本"
  ]
}
EOF

log_success "Security 檢查完成！"
log_info "總檢查項目: $TOTAL_CHECKS"
log_info "嚴重問題: $CRITICAL_ISSUES"
log_info "高風險問題: $HIGH_ISSUES"
log_info "中風險問題: $MEDIUM_ISSUES"
log_info "失敗檢查: $FAILED_CHECKS"
log_info "警告檢查: $WARNING_CHECKS"
log_info "詳細報告: $OUTPUT_FILE"
log_info "詳細結果: $DETAILED_OUTPUT_FILE"