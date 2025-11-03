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
    
    echo "$users" | jq -r '.[]' 2>/dev/null | while read -r u; do
        [[ -z "$u" ]] && continue
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
    
    echo "$arns" | jq -r '.[]' 2>/dev/null | while read -r arn; do
        [[ -z "$arn" ]] && continue
        
        ver="$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || true)"
        if [[ -z "$ver" ]]; then
            emit "IAM:PolicyWildcard" "$arn" "$r" "INFO" "LOW" "No permission to read version"
            continue
        fi
        
        doc="$(aws iam get-policy-version --policy-arn "$arn" --version-id "$ver" --query 'PolicyVersion.Document' --output json 2>/dev/null || echo '{}')"
        
        # 簡化的萬用字元檢查 - 使用 grep 而非複雜 jq
        if echo "$doc" | grep -qE '"Action"[[:space:]]*:[[:space:]]*"\*"' || \
           echo "$doc" | grep -qE '"Resource"[[:space:]]*:[[:space:]]*"\*"'; then
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
    
    echo "$buckets" | jq -r '.[]' 2>/dev/null | while read -r b; do
        [[ -z "$b" ]] && continue
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
    
    local out
    out="$(aws cloudtrail describe-trails --region "$region" --include-shadow-trails --output json 2>/dev/null || echo '{}')"
    
    if [[ "$out" == "{}" ]]; then
        emit "CloudTrail:Enabled" "-" "$region" "INFO" "HIGH" "AccessDenied or not permitted"
        return
    fi
    
    local count
    count="$(echo "$out" | jq '.trailList | length' 2>/dev/null || echo 0)"
    
    if [[ "$count" -eq 0 ]]; then
        emit "CloudTrail:Enabled" "-" "$region" "FAIL" "HIGH" "No trails"
        return
    fi
    
    # 簡化檢查，避免卡住
    echo "$out" | jq -r '.trailList[]?.Name' 2>/dev/null | while read -r name; do
        [[ -z "$name" ]] && continue
        
        local st
        st="$(aws cloudtrail get-trail-status --region "$region" --name "$name" --output json 2>/dev/null || echo '{}')"
        
        if [[ "$st" == "{}" ]]; then
            emit "CloudTrail:Status" "$name" "$region" "INFO" "HIGH" "No permission to get status"
        else
            local logging
            logging="$(echo "$st" | jq -r '.IsLogging // false' 2>/dev/null || echo "false")"
            emit "CloudTrail:Status" "$name" "$region" "$([[ "$logging" == "true" ]] && echo OK || echo FAIL)" "HIGH" "IsLogging=$logging"
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
    
    local sgs
    sgs="$(aws ec2 describe-security-groups --region "$region" --output json 2>/dev/null || echo '{}')"
    
    if [[ "$sgs" == "{}" ]]; then
        emit "EC2:SGOpenAdminPorts" "-" "$region" "INFO" "HIGH" "AccessDenied"
        return
    fi
    
    # 簡化檢查，使用 grep 而非複雜的 jq
    echo "$sgs" | jq -r '.SecurityGroups[]? | .GroupId' 2>/dev/null | while read -r id; do
        [[ -z "$id" ]] && continue
        
        local sg_data
        sg_data="$(echo "$sgs" | jq -r --arg id "$id" '.SecurityGroups[] | select(.GroupId==$id)' 2>/dev/null || echo "")"
        
        # 檢查是否有 0.0.0.0/0 開放 22 或 3389 埠
        if echo "$sg_data" | grep -q '"CidrIp": "0.0.0.0/0"'; then
            if echo "$sg_data" | grep -E '"FromPort": (22|3389)|"ToPort": (22|3389)' &>/dev/null; then
                local name
                name="$(echo "$sg_data" | jq -r '.GroupName' 2>/dev/null || echo "unknown")"
                emit "EC2:SGOpenAdminPorts" "$id($name)" "$region" "FAIL" "HIGH" "Open 22/3389 to world"
            fi
        fi
    done
}

check_rds_security() {
    local region="$1"
    log_info "檢查 RDS 安全配置 (區域: $region)..."
    dbs="$(aws_try "$region" aws rds describe-db-instances --output json 2>/dev/null || echo '{}')"
    if [[ "$dbs" == __ERROR__* ]] || [[ "$dbs" == "{}" ]]; then
        emit "RDS:PubliclyAccessible" "-" "$region" "INFO" "MEDIUM" "AccessDenied or no RDS instances"
        return
    fi
    
    local db_count
    db_count="$(echo "$dbs" | jq '.DBInstances | length' 2>/dev/null || echo 0)"
    if [[ "$db_count" -eq 0 ]]; then
        emit "RDS:PubliclyAccessible" "-" "$region" "INFO" "LOW" "No RDS instances found"
        return
    fi
    
    echo "$dbs" | jq -c '.DBInstances[]?' 2>/dev/null | while read -r db; do
        [[ -z "$db" ]] && continue
        
        id="$(echo "$db" | jq -r '.DBInstanceIdentifier' 2>/dev/null || echo "unknown")"
        pub="$(echo "$db" | jq -r '.PubliclyAccessible' 2>/dev/null || echo "false")"
        enc="$(echo "$db" | jq -r '.StorageEncrypted' 2>/dev/null || echo "false")"
        
        [[ "$pub" == "true" ]] && emit "RDS:PubliclyAccessible" "$id" "$region" "WARN" "MEDIUM" "PubliclyAccessible=true"
        [[ "$enc" != "true" ]] && emit "RDS:StorageEncrypted" "$id" "$region" "FAIL" "HIGH" "StorageEncrypted=false"
    done
}

check_kms_rotation() {
    local region="$1"
    log_info "檢查 KMS 金鑰輪換 (區域: $region)..."
    keys="$(aws_try "$region" aws kms list-keys --query 'Keys[].KeyId' --output json 2>/dev/null || echo '[]')"
    if [[ "$keys" == __ERROR__* ]] || [[ "$keys" == "[]" ]]; then
        emit "KMS:RotationEnabled" "-" "$region" "INFO" "LOW" "AccessDenied or no KMS keys"
        return
    fi
    
    local key_count
    key_count="$(echo "$keys" | jq 'length' 2>/dev/null || echo 0)"
    if [[ "$key_count" -eq 0 ]]; then
        emit "KMS:RotationEnabled" "-" "$region" "INFO" "LOW" "No KMS keys found"
        return
    fi
    
    echo "$keys" | jq -r '.[]' 2>/dev/null | while read -r k; do
        [[ -z "$k" ]] && continue
        m="$(aws_try "$region" aws kms get-key-rotation-status --key-id "$k" --query 'KeyRotationEnabled' --output text 2>/dev/null || echo "__ERROR__")"
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
        --query 'CertificateSummaryList[].CertificateArn' --output json 2>/dev/null || echo '[]')"
    if [[ "$cert_arns" == __ERROR__* ]] || [[ "$cert_arns" == "[]" ]]; then
        emit "ACM:Expiry" "-" "$region" "INFO" "MEDIUM" "AccessDenied or ACM unsupported in region"
        return
    fi
    
    local cert_count
    cert_count="$(echo "$cert_arns" | jq 'length' 2>/dev/null || echo 0)"
    if [[ "$cert_count" -eq 0 ]]; then
        emit "ACM:Expiry" "-" "$region" "INFO" "LOW" "No ACM certificates found"
        return
    fi
    
    echo "$cert_arns" | jq -r '.[]' 2>/dev/null | while read -r arn; do
        [[ -z "$arn" ]] && continue
        desc="$(aws_try "$region" aws acm describe-certificate --certificate-arn "$arn" --output json 2>/dev/null || echo '{}')"
        if [[ "$desc" == __ERROR__* ]] || [[ "$desc" == "{}" ]]; then
            emit "ACM:Expiry" "$arn" "$region" "INFO" "LOW" "No permission to describe-certificate"
            continue
        fi
        
        not_after="$(echo "$desc" | jq -r '.Certificate.NotAfter' 2>/dev/null || echo "")"
        status="$(echo "$desc" | jq -r '.Certificate.Status' 2>/dev/null || echo "UNKNOWN")"
        domain="$(echo "$desc" | jq -r '.Certificate.DomainName' 2>/dev/null || echo "unknown")"
        
        if [[ -z "$not_after" ]]; then
            emit "ACM:Expiry" "$domain ($arn)" "$region" "INFO" "LOW" "Cannot determine expiry date"
            continue
        fi
        
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

# 新增檢查函數

check_iam_password_policy() {
    local r="global"
    log_info "檢查 IAM 密碼政策..."
    policy="$(aws iam get-account-password-policy --output json 2>/dev/null || echo '{}')"
    
    if [[ "$policy" == "{}" ]]; then
        emit "IAM:PasswordPolicy" "-" "$r" "FAIL" "HIGH" "No password policy configured"
        return
    fi
    
    local min_len require_symbols require_numbers require_upper require_lower max_age
    min_len="$(echo "$policy" | jq -r '.PasswordPolicy.MinimumPasswordLength // 0')"
    require_symbols="$(echo "$policy" | jq -r '.PasswordPolicy.RequireSymbols // false')"
    require_numbers="$(echo "$policy" | jq -r '.PasswordPolicy.RequireNumbers // false')"
    require_upper="$(echo "$policy" | jq -r '.PasswordPolicy.RequireUppercaseCharacters // false')"
    require_lower="$(echo "$policy" | jq -r '.PasswordPolicy.RequireLowercaseCharacters // false')"
    max_age="$(echo "$policy" | jq -r '.PasswordPolicy.MaxPasswordAge // 0')"
    
    local issues=()
    [[ "$min_len" -lt 14 ]] && issues+=("MinLength<14")
    [[ "$require_symbols" != "true" ]] && issues+=("NoSymbols")
    [[ "$require_numbers" != "true" ]] && issues+=("NoNumbers")
    [[ "$require_upper" != "true" ]] && issues+=("NoUppercase")
    [[ "$require_lower" != "true" ]] && issues+=("NoLowercase")
    [[ "$max_age" -eq 0 || "$max_age" -gt 90 ]] && issues+=("MaxAge>90days")
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        emit "IAM:PasswordPolicy" "-" "$r" "WARN" "MEDIUM" "Weak policy: ${issues[*]}"
    else
        emit "IAM:PasswordPolicy" "-" "$r" "OK" "MEDIUM" "Strong password policy"
    fi
}

check_config_recorder() {
    local region="$1"
    log_info "檢查 AWS Config Recorder (區域: $region)..."
    
    recorders="$(aws configservice describe-configuration-recorders --region "$region" --output json 2>/dev/null || echo '{"ConfigurationRecorders":[]}')"
    cnt="$(echo "$recorders" | jq '.ConfigurationRecorders|length')"
    
    if [[ "$cnt" -eq 0 ]]; then
        emit "Config:Recorder" "-" "$region" "WARN" "MEDIUM" "No Config Recorder (compliance tracking disabled)"
        return
    fi
    
    status="$(aws configservice describe-configuration-recorder-status --region "$region" --output json 2>/dev/null || echo '{"ConfigurationRecordersStatus":[]}')"
    echo "$status" | jq -c '.ConfigurationRecordersStatus[]?' | while read -r s; do
        name="$(echo "$s" | jq -r '.name')"
        recording="$(echo "$s" | jq -r '.recording')"
        
        if [[ "$recording" == "true" ]]; then
            emit "Config:Recorder" "$name" "$region" "OK" "MEDIUM" "Recording enabled"
        else
            emit "Config:Recorder" "$name" "$region" "FAIL" "MEDIUM" "Recording disabled"
        fi
    done
}

check_guardduty() {
    local region="$1"
    log_info "檢查 GuardDuty (區域: $region)..."
    
    detectors="$(aws guardduty list-detectors --region "$region" --output json 2>/dev/null || echo '{"DetectorIds":[]}')"
    cnt="$(echo "$detectors" | jq '.DetectorIds|length')"
    
    if [[ "$cnt" -eq 0 ]]; then
        emit "GuardDuty:Enabled" "-" "$region" "WARN" "HIGH" "GuardDuty not enabled (threat detection disabled)"
        return
    fi
    
    echo "$detectors" | jq -r '.DetectorIds[]' 2>/dev/null | while read -r detector_id; do
        [[ -z "$detector_id" ]] && continue
        
        details="$(aws guardduty get-detector --region "$region" --detector-id "$detector_id" --output json 2>/dev/null || echo '{}')"
        status="$(echo "$details" | jq -r '.Status // "DISABLED"')"
        
        if [[ "$status" == "ENABLED" ]]; then
            emit "GuardDuty:Enabled" "$detector_id" "$region" "OK" "HIGH" "GuardDuty enabled"
        else
            emit "GuardDuty:Enabled" "$detector_id" "$region" "FAIL" "HIGH" "GuardDuty disabled"
        fi
    done
}

check_securityhub() {
    local region="$1"
    log_info "檢查 Security Hub (區域: $region)..."
    
    hub="$(aws securityhub describe-hub --region "$region" --output json 2>/dev/null || echo '{}')"
    
    if [[ "$hub" == "{}" ]]; then
        emit "SecurityHub:Enabled" "-" "$region" "WARN" "MEDIUM" "Security Hub not enabled"
        return
    fi
    
    status="$(echo "$hub" | jq -r '.HubArn // empty')"
    if [[ -n "$status" ]]; then
        emit "SecurityHub:Enabled" "-" "$region" "OK" "MEDIUM" "Security Hub enabled"
    else
        emit "SecurityHub:Enabled" "-" "$region" "WARN" "MEDIUM" "Security Hub not configured"
    fi
}

check_vpc_flow_logs() {
    local region="$1"
    log_info "檢查 VPC Flow Logs (區域: $region)..."
    
    vpcs="$(aws ec2 describe-vpcs --region "$region" --query 'Vpcs[].VpcId' --output json 2>/dev/null || echo '[]')"
    
    echo "$vpcs" | jq -r '.[]' 2>/dev/null | while read -r vpc_id; do
        [[ -z "$vpc_id" ]] && continue
        
        flow_logs="$(aws ec2 describe-flow-logs --region "$region" --filter "Name=resource-id,Values=$vpc_id" --output json 2>/dev/null || echo '{"FlowLogs":[]}')"
        cnt="$(echo "$flow_logs" | jq '.FlowLogs|length')"
        
        if [[ "$cnt" -eq 0 ]]; then
            emit "VPC:FlowLogs" "$vpc_id" "$region" "WARN" "MEDIUM" "No Flow Logs (network monitoring disabled)"
        else
            emit "VPC:FlowLogs" "$vpc_id" "$region" "OK" "MEDIUM" "Flow Logs enabled"
        fi
    done
}

check_secrets_manager_rotation() {
    local region="$1"
    log_info "檢查 Secrets Manager 輪換 (區域: $region)..."
    
    secrets="$(aws secretsmanager list-secrets --region "$region" --output json 2>/dev/null || echo '{"SecretList":[]}')"
    
    echo "$secrets" | jq -c '.SecretList[]?' | while read -r secret; do
        name="$(echo "$secret" | jq -r '.Name')"
        rotation_enabled="$(echo "$secret" | jq -r '.RotationEnabled // false')"
        
        if [[ "$rotation_enabled" == "true" ]]; then
            emit "SecretsManager:Rotation" "$name" "$region" "OK" "MEDIUM" "Rotation enabled"
        else
            emit "SecretsManager:Rotation" "$name" "$region" "WARN" "MEDIUM" "Rotation not enabled"
        fi
    done
}

check_lambda_vpc_config() {
    local region="$1"
    log_info "檢查 Lambda VPC 配置 (區域: $region)..."
    
    functions="$(aws lambda list-functions --region "$region" --query 'Functions[].FunctionName' --output json 2>/dev/null || echo '[]')"
    
    echo "$functions" | jq -r '.[]' 2>/dev/null | while read -r func; do
        [[ -z "$func" ]] && continue
        
        config="$(aws lambda get-function-configuration --region "$region" --function-name "$func" --output json 2>/dev/null || echo '{}')"
        vpc_config="$(echo "$config" | jq -r '.VpcConfig.VpcId // empty')"
        
        # 如果 Lambda 需要訪問 VPC 資源但沒有配置 VPC，這可能是安全問題
        # 這裡只記錄資訊，不判斷好壞
        if [[ -n "$vpc_config" ]]; then
            emit "Lambda:VPCConfig" "$func" "$region" "INFO" "LOW" "In VPC: $vpc_config"
        else
            emit "Lambda:VPCConfig" "$func" "$region" "INFO" "LOW" "Not in VPC (public internet access)"
        fi
    done
}

check_ec2_imdsv2() {
    local region="$1"
    log_info "檢查 EC2 IMDSv2 (區域: $region)..."
    
    instances="$(aws ec2 describe-instances --region "$region" --query 'Reservations[].Instances[]' --output json 2>/dev/null || echo '[]')"
    
    echo "$instances" | jq -c '.[]?' | while read -r instance; do
        id="$(echo "$instance" | jq -r '.InstanceId')"
        imds="$(echo "$instance" | jq -r '.MetadataOptions.HttpTokens // "optional"')"
        
        if [[ "$imds" == "required" ]]; then
            emit "EC2:IMDSv2" "$id" "$region" "OK" "MEDIUM" "IMDSv2 required (secure)"
        else
            emit "EC2:IMDSv2" "$id" "$region" "WARN" "MEDIUM" "IMDSv2 not required (consider enforcing)"
        fi
    done
}

check_waf() {
    local region="$1"
    log_info "檢查 WAF (區域: $region)..."
    
    # WAFv2 (regional)
    web_acls="$(aws wafv2 list-web-acls --region "$region" --scope REGIONAL --output json 2>/dev/null || echo '{"WebACLs":[]}')"
    cnt="$(echo "$web_acls" | jq '.WebACLs|length')"
    
    if [[ "$cnt" -eq 0 ]]; then
        emit "WAF:WebACL" "-" "$region" "INFO" "LOW" "No regional WAF WebACLs (consider for ALB/API Gateway protection)"
    else
        emit "WAF:WebACL" "-" "$region" "OK" "LOW" "Regional WAF enabled, count=$cnt"
    fi
}

# ========== 執行檢查 ==========

log_info "執行全域安全檢查..."
check_root_mfa
check_iam_users_mfa_and_keys
check_iam_password_policy
check_iam_policy_wildcards
check_s3_security
check_cloudfront_security

log_info "執行區域性安全檢查 (區域: $REGION)..."
check_cloudtrail "$REGION"
check_config_recorder "$REGION"
check_guardduty "$REGION"
check_securityhub "$REGION"
check_ebs_encryption "$REGION"
check_security_groups "$REGION"
check_vpc_flow_logs "$REGION"
check_rds_security "$REGION"
check_kms_rotation "$REGION"
check_secrets_manager_rotation "$REGION"
check_lambda_vpc_config "$REGION"
check_ec2_imdsv2 "$REGION"
check_waf "$REGION"
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
    "設定強密碼政策（最少 14 字元，包含大小寫、數字、符號）",
    "定期輪換 IAM 存取金鑰（建議 90 天內）",
    "檢查並移除 IAM 政策中的萬用字元權限",
    "實施最小權限原則（Least Privilege）",
    "啟用 S3 儲存桶公開存取封鎖",
    "為 S3 儲存桶啟用預設加密（SSE-S3 或 SSE-KMS）",
    "使用 S3 Object Ownership 設定為 BucketOwnerEnforced",
    "檢查並修正過於寬鬆的 Security Group 規則",
    "避免對 0.0.0.0/0 開放管理埠（22, 3389）",
    "啟用 EBS 預設加密",
    "啟用 CloudTrail 並確保記錄檔驗證",
    "啟用 AWS Config 進行合規性追蹤",
    "啟用 GuardDuty 進行威脅偵測",
    "啟用 Security Hub 進行集中安全管理",
    "為所有 VPC 啟用 Flow Logs",
    "為 RDS 執行個體啟用儲存加密",
    "避免 RDS 執行個體公開存取",
    "啟用 KMS 金鑰自動輪換",
    "為 Secrets Manager 密鑰啟用自動輪換",
    "監控 ACM 憑證到期時間",
    "CloudFront 分發使用 HTTPS-only 和現代 TLS 版本（>= TLSv1.2_2019）",
    "為 EC2 實例強制使用 IMDSv2",
    "考慮為面向公眾的應用程式啟用 WAF",
    "定期審查和更新安全群組規則",
    "使用 VPC Endpoints 減少公開網路暴露",
    "啟用 CloudWatch Logs 加密",
    "實施資料分類和標籤策略",
    "定期進行安全審計和滲透測試"
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