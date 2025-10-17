#!/usr/bin/env bash

# Cost Optimization Pillar 檢查 - AWS Well-Architected Framework
# 成本優化支柱 - 詳細檢查版本

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
    echo -e "${BLUE}[COST-OPT]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[COST-OPT]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[COST-OPT]${NC} $1"
}

log_error() {
    echo -e "${RED}[COST-OPT]${NC} $1"
}

# 輸出文件
OUTPUT_FILE="$REPORTS_DIR/cost-optimization_${TIMESTAMP}.json"
DETAILED_OUTPUT_FILE="$REPORTS_DIR/cost-optimization_detailed_${TIMESTAMP}.jsonl"

log_info "開始 Cost Optimization 支柱詳細檢查..."

# 配置選項
ENABLE_IDLE_METRICS="${ENABLE_IDLE_METRICS:-0}"  # 0=關閉, 1=開啟 CloudWatch 指標檢查
IDLE_CPU_PCT="${IDLE_CPU_PCT:-1}"               # 閒置 CPU% 門檻
IDLE_LOOKBACK_DAYS="${IDLE_LOOKBACK_DAYS:-3}"   # 回看天數

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
        if ! out="$("$@" 2> >(stderr=$(cat); typeset -p stderr >/dev/null))"; then
            local err="$(typeset -p stderr 2>/dev/null | sed -E 's/^declare -x stderr="(.*)"$/\1/' | tr -d '\r')"
            echo "__ERROR__:$err"; return 1
        fi
    else
        if ! out="$("$@" --region "$region" 2> >(stderr=$(cat); typeset -p stderr >/dev/null))"; then
            local err="$(typeset -p stderr 2>/dev/null | sed -E 's/^declare -x stderr="(.*)"$/\1/' | tr -d '\r')"
            echo "__ERROR__:$err"; return 1
        fi
    fi
    echo "$out"; return 0
}

days_since_iso() {
    python3 - <<'PY' "$1"
import sys,datetime
s=sys.argv[1]
dt=datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
print(int((datetime.datetime.now(datetime.timezone.utc)-dt).total_seconds()//86400))
PY
}

# 初始化詳細輸出文件
echo "" > "$DETAILED_OUTPUT_FILE"

# ========== 全域檢查 ==========

check_cloudfront_priceclass() {
    local r="global"
    log_info "檢查 CloudFront 價格等級..."
    dist="$(aws_try "$r" aws cloudfront list-distributions --output json)"
    [[ "$dist" == __ERROR__* ]] && { emit "CF:PriceClass" "-" "$r" "INFO" "LOW" "AccessDenied/None"; return; }
    
    echo "$dist" | jq -c '.DistributionList.Items[]?' | while read -r d; do
        id="$(echo "$d" | jq -r '.Id')"
        domain="$(echo "$d" | jq -r '.DomainName')"
        pc="$(echo "$d" | jq -r '.PriceClass // "All"')"
        
        case "$pc" in
            PriceClass_All|All) emit "CF:PriceClass" "$id($domain)" "$r" "WARN" "MEDIUM" "PriceClass=All (consider 100/200)";;
            PriceClass_200|PriceClass_100) emit "CF:PriceClass" "$id($domain)" "$r" "OK" "LOW" "$pc";;
            *) emit "CF:PriceClass" "$id($domain)" "$r" "INFO" "LOW" "PriceClass=$pc";;
        esac
    done
}

check_s3_lifecycle_global() {
    local r="global"
    log_info "檢查 S3 生命週期政策..."
    buckets="$(aws s3api list-buckets --query 'Buckets[].Name' --output json 2>/dev/null || echo '[]')"
    
    for b in $(echo "$buckets" | jq -r '.[]'); do
        lc="$(aws s3api get-bucket-lifecycle-configuration --bucket "$b" --output json 2>/dev/null || echo '{}')"
        rules="$(echo "$lc" | jq -r '.Rules | length' 2>/dev/null || echo 0)"
        [[ "$rules" -eq 0 ]] && emit "S3:Lifecycle" "$b" "$r" "WARN" "MEDIUM" "No lifecycle rules (consider IA/Glacier/version cleanup)"
    done
}

# ========== 區域性檢查 ==========

check_ebs_orphans_and_gp2() {
    local region="$1"
    log_info "檢查 EBS 孤立磁碟區和 gp2 類型 (區域: $region)..."
    vols="$(aws_try "$region" aws ec2 describe-volumes --output json)"
    [[ "$vols" == __ERROR__* ]] && { 
        emit "EBS:Unused" "-" "$region" "INFO" "MEDIUM" "AccessDenied"
        emit "EBS:gp2" "-" "$region" "INFO" "LOW" "AccessDenied"
        return
    }
    
    echo "$vols" | jq -c '.Volumes[]?' | while read -r v; do
        id="$(echo "$v" | jq -r '.VolumeId')"
        state="$(echo "$v" | jq -r '.State')"
        type="$(echo "$v" | jq -r '.VolumeType')"
        atts="$(echo "$v" | jq -r '.Attachments|length')"
        
        # 檢查未附加的磁碟區
        if [[ "$state" == "available" && "$atts" -eq 0 ]]; then
            size="$(echo "$v" | jq -r '.Size')"
            emit "EBS:Unused" "$id" "$region" "FAIL" "HIGH" "Unattached size=${size}GiB"
        fi
        
        # 檢查 gp2 類型
        [[ "$type" == "gp2" ]] && emit "EBS:gp2" "$id" "$region" "WARN" "LOW" "Consider migrate to gp3"
    done
}

check_eip_unattached() {
    local region="$1"
    log_info "檢查未關聯的 Elastic IP (區域: $region)..."
    eip="$(aws_try "$region" aws ec2 describe-addresses --output json)"
    [[ "$eip" == __ERROR__* ]] && { emit "EIP:Unattached" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    echo "$eip" | jq -c '.Addresses[]?' | while read -r a; do
        [[ "$(echo "$a" | jq -r '.AssociationId // empty')" == "" ]] && \
            emit "EIP:Unattached" "$(echo "$a" | jq -r '.PublicIp')" "$region" "FAIL" "MEDIUM" "Elastic IP not associated"
    done
}

check_elbv2_idle() {
    local region="$1"
    log_info "檢查 Load Balancer 目標群組 (區域: $region)..."
    lbs="$(aws_try "$region" aws elbv2 describe-load-balancers --output json)"
    [[ "$lbs" == __ERROR__* ]] && { emit "ALB/NLB:NoTargets" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    echo "$lbs" | jq -c '.LoadBalancers[]?' | while read -r lb; do
        arn="$(echo "$lb" | jq -r '.LoadBalancerArn')"
        name="$(echo "$lb" | jq -r '.LoadBalancerName')"
        
        tgs="$(aws elbv2 describe-target-groups --region "$region" --load-balancer-arn "$arn" --output json 2>/dev/null || echo '{"TargetGroups":[]}')"
        cnt="$(echo "$tgs" | jq '[.TargetGroups[]? | .TargetGroupArn] | length')"
        
        if [[ "$cnt" -eq 0 ]]; then
            emit "ALB/NLB:NoTargets" "$name" "$region" "WARN" "LOW" "No target groups"
        else
            # 檢查目標健康狀態
            none="$(echo "$tgs" | jq -r '.TargetGroups[]?.TargetGroupArn' | while read -r tg; do
                aws elbv2 describe-target-health --region "$region" --target-group-arn "$tg" --query 'TargetHealthDescriptions' --output json 2>/dev/null || echo '[]'
            done | jq -s '[.[]]|flatten|length')"
            [[ "${none:-0}" -eq 0 ]] && emit "ALB/NLB:NoTargets" "$name" "$region" "WARN" "LOW" "Target groups with 0 registered targets"
        fi
    done
}

check_ecr_lifecycle() {
    local region="$1"
    log_info "檢查 ECR 生命週期政策 (區域: $region)..."
    repos="$(aws_try "$region" aws ecr describe-repositories --query 'repositories[].repositoryName' --output json)"
    [[ "$repos" == __ERROR__* ]] && { emit "ECR:LifecyclePolicy" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    for r in $(echo "$repos" | jq -r '.[]'); do
        pol="$(aws ecr get-lifecycle-policy --region "$region" --repository-name "$r" --query 'lifecyclePolicyText' --output text 2>/dev/null || true)"
        [[ -z "${pol:-}" || "$pol" == "None" ]] && emit "ECR:LifecyclePolicy" "$r" "$region" "WARN" "LOW" "No lifecycle policy"
    done
}

check_rds_storage_autoscaling() {
    local region="$1"
    log_info "檢查 RDS 儲存自動擴展 (區域: $region)..."
    dbs="$(aws_try "$region" aws rds describe-db-instances --output json)"
    [[ "$dbs" == __ERROR__* ]] && { 
        emit "RDS:gp2" "-" "$region" "INFO" "LOW" "AccessDenied/None"
        emit "RDS:StorageAutoscaling" "-" "$region" "INFO" "LOW" "AccessDenied/None"
        return
    }
    
    echo "$dbs" | jq -c '.DBInstances[]?' | while read -r db; do
        id="$(echo "$db" | jq -r '.DBInstanceIdentifier')"
        st="$(echo "$db" | jq -r '.StorageType // "gp2"')"
        
        # 檢查 gp2 儲存類型
        [[ "$st" == "gp2" ]] && emit "RDS:gp2" "$id" "$region" "WARN" "LOW" "Consider gp3 (if supported)"
        
        # 檢查儲存自動擴展
        alloc="$(echo "$db" | jq -r '.AllocatedStorage // 0')"
        maxalloc="$(echo "$db" | jq -r '.MaxAllocatedStorage // 0')"
        if [[ "$maxalloc" -eq 0 || "$maxalloc" -le "$alloc" ]]; then
            emit "RDS:StorageAutoscaling" "$id" "$region" "WARN" "LOW" "Storage autoscaling not configured (MaxAllocatedStorage<=Allocated)"
        fi
    done
}

check_lambda_provisioned() {
    local region="$1"
    log_info "檢查 Lambda 預配置並發 (區域: $region)..."
    funcs="$(aws_try "$region" aws lambda list-functions --query 'Functions[].FunctionName' --output json)"
    [[ "$funcs" == __ERROR__* ]] && { emit "Lambda:ProvisionedConcurrency" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    for f in $(echo "$funcs" | jq -r '.[]'); do
        pc="$(aws lambda list-provisioned-concurrency-configs --region "$region" --function-name "$f" --query 'ProvisionedConcurrencyConfigs' --output json 2>/dev/null || echo '[]')"
        [[ "$(echo "$pc" | jq 'length')" -gt 0 ]] && emit "Lambda:ProvisionedConcurrency" "$f" "$region" "WARN" "LOW" "Has provisioned concurrency"
    done
}

check_dynamodb_mode_autoscaling() {
    local region="$1"
    log_info "檢查 DynamoDB 計費模式 (區域: $region)..."
    tabs="$(aws_try "$region" aws dynamodb list-tables --query 'TableNames' --output json)"
    [[ "$tabs" == __ERROR__* ]] && { emit "DDB:AutoScaling" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    for t in $(echo "$tabs" | jq -r '.[]'); do
        d="$(aws dynamodb describe-table --region "$region" --table-name "$t" --output json 2>/dev/null || echo '{}')"
        mode="$(echo "$d" | jq -r '.Table.BillingModeSummary.BillingMode // "PROVISIONED"')"
        if [[ "$mode" == "PROVISIONED" ]]; then
            emit "DDB:AutoScaling" "$t" "$region" "WARN" "LOW" "Provisioned mode (ensure Auto Scaling or switch to On-Demand)"
        fi
    done
}

check_ec2_graviton_candidates() {
    local region="$1"
    log_info "檢查 EC2 Graviton 候選和 Savings Plan 機會 (區域: $region)..."
    res="$(aws_try "$region" aws ec2 describe-instances --query 'Reservations[].Instances[]' --output json)"
    [[ "$res" == __ERROR__* ]] && { 
        emit "EC2:GravitonCandidate" "-" "$region" "INFO" "LOW" "AccessDenied"
        emit "EC2:SavingsPlanCandidate" "-" "$region" "INFO" "LOW" "AccessDenied"
        return
    }
    
    echo "$res" | jq -c '.[]?' | while read -r i; do
        id="$(echo "$i" | jq -r '.InstanceId')"
        it="$(echo "$i" | jq -r '.InstanceType')"
        arch="$(echo "$i" | jq -r '.Architecture // .PlatformDetails // "x86_64"')"
        lt="$(echo "$i" | jq -r '.LaunchTime')"
        sp="$(echo "$i" | jq -r '.InstanceLifecycle // ""')"
        
        # Graviton 候選檢查
        if [[ "$arch" == "x86_64" && "$it" =~ ^(t3|t3a|t2|m5|m5a|m5n|c5|c5a|c5n|r5|r5a|r5n|m6i|c6i|r6i) ]]; then
            emit "EC2:GravitonCandidate" "$id/$it" "$region" "INFO" "LOW" "Evaluate migration to Graviton (e.g., t4g/m7g/c7g)"
        fi
        
        # Savings Plan 候選檢查
        if [[ "$sp" != "spot" && -n "$lt" ]]; then
            d="$(days_since_iso "$lt" 2>/dev/null || echo 0)"
            [[ "${d:-0}" -ge 30 ]] && emit "EC2:SavingsPlanCandidate" "$id/$it" "$region" "WARN" "LOW" "On-Demand >= ${d}d (consider Savings Plans/RI)"
        fi
    done
}

check_nat_gateways() {
    local region="$1"
    log_info "檢查 NAT Gateway 使用 (區域: $region)..."
    nats="$(aws_try "$region" aws ec2 describe-nat-gateways --query 'NatGateways[].NatGatewayId' --output json)"
    [[ "$nats" == __ERROR__* ]] && { emit "NAT:Usage" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    for n in $(echo "$nats" | jq -r '.[]'); do
        emit "NAT:Usage" "$n" "$region" "INFO" "LOW" "High-cost data processing; evaluate PrivateLink/egress patterns"
    done
}

check_cw_logs_retention() {
    local region="$1"
    log_info "檢查 CloudWatch Logs 保留政策 (區域: $region)..."
    groups="$(aws_try "$region" aws logs describe-log-groups --query 'logGroups[].{n:logGroupName,r:retentionInDays}' --output json)"
    [[ "$groups" == __ERROR__* ]] && { emit "CWLogs:Retention" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    echo "$groups" | jq -c '.[]?' | while read -r g; do
        name="$(echo "$g" | jq -r '.n')"
        r="$(echo "$g" | jq -r '.r // "None"')"
        [[ "$r" == "None" ]] && emit "CWLogs:Retention" "$name" "$region" "WARN" "LOW" "No retention policy (infinite storage)"
    done
}

# EC2 閒置偵測 (可選，需要 CloudWatch 指標)
check_ec2_idle_metrics() {
    local region="$1"
    [[ "$ENABLE_IDLE_METRICS" != "1" ]] && return
    
    log_info "檢查 EC2 閒置指標 (區域: $region)..."
    inst="$(aws_try "$region" aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --output json)"
    [[ "$inst" == __ERROR__* ]] && { emit "EC2:Idle" "-" "$region" "INFO" "LOW" "AccessDenied"; return; }
    
    end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    start="$(date -u -d "$IDLE_LOOKBACK_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)"
    
    for id in $(echo "$inst" | jq -r '.[]'); do
        m="$(aws cloudwatch get-metric-statistics --region "$region" \
            --namespace AWS/EC2 --metric-name CPUUtilization \
            --dimensions Name=InstanceId,Value="$id" \
            --start-time "$start" --end-time "$end" --period 3600 --statistics Average \
            --query 'Datapoints[].Average' --output json 2>/dev/null || echo '[]')"
        
        if [[ "$(echo "$m" | jq 'length')" -gt 0 ]]; then
            maxv="$(echo "$m" | jq -r 'max // 0')"
            cmp="$(python3 - <<PY "$maxv" "$IDLE_CPU_PCT"
a=float(__import__("sys").argv[1]); b=float(__import__("sys").argv[2]); print(1 if a<b else 0)
PY
)"
            [[ "$cmp" == "1" ]] && emit "EC2:Idle" "$id" "$region" "WARN" "MEDIUM" "Max CPU < ${IDLE_CPU_PCT}% in last ${IDLE_LOOKBACK_DAYS}d"
        fi
    done
}

# ========== 執行檢查 ==========

log_info "執行全域成本優化檢查..."
check_cloudfront_priceclass
check_s3_lifecycle_global

log_info "執行區域性成本優化檢查 (區域: $REGION)..."
check_ebs_orphans_and_gp2 "$REGION"
check_eip_unattached "$REGION"
check_elbv2_idle "$REGION"
check_ecr_lifecycle "$REGION"
check_rds_storage_autoscaling "$REGION"
check_lambda_provisioned "$REGION"
check_dynamodb_mode_autoscaling "$REGION"
check_ec2_graviton_candidates "$REGION"
check_nat_gateways "$REGION"
check_cw_logs_retention "$REGION"
check_ec2_idle_metrics "$REGION"

# ========== 計算資源成本檢查 ==========

check_ec2_sp_candidates() {
    local region="$1"
    log_info "檢查 EC2 Savings Plan 候選 (區域: $region)..."
    res="$(aws_try "$region" aws ec2 describe-instances --query 'Reservations[].Instances[]' --output json)"
    [[ "$res" == __ERROR__* ]] && { emit "EC2:SavingsPlanCandidate" "-" "$region" "INFO" "LOW" "AccessDenied"; return; }
    
    echo "$res" | jq -c '.[]?' | while read -r i; do
        id="$(echo "$i" | jq -r '.InstanceId')"
        state="$(echo "$i" | jq -r '.State.Name')"
        lifecycle="$(echo "$i" | jq -r '.InstanceLifecycle // ""')"
        itype="$(echo "$i" | jq -r '.InstanceType')"
        lt="$(echo "$i" | jq -r '.LaunchTime // empty')"
        
        [[ "$state" != "running" || -z "$lt" || "$lifecycle" == "spot" ]] && continue
        
        days="$(days_since_iso "$lt" 2>/dev/null || echo 0)"
        if (( days >= 30 )); then
            emit "EC2:SavingsPlanCandidate" "$id/$itype" "$region" "WARN" "LOW" "On-Demand running >= ${days}d (consider 1/3-yr Savings Plans)"
        fi
    done
}

check_ec2_type_tally() {
    local region="$1"
    log_info "統計 EC2 實例類型分佈 (區域: $region)..."
    res="$(aws_try "$region" aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceType' --output json)"
    [[ "$res" == __ERROR__* ]] && { emit "EC2:TypeTally" "-" "$region" "INFO" "LOW" "AccessDenied"; return; }
    
    # 統計各實例類型數量
    echo "$res" | jq -r '.[]' | sort | uniq -c | while read -r count type; do
        emit "EC2:TypeTally" "$type" "$region" "INFO" "LOW" "count=$count"
    done
}

check_asg_overprovision() {
    local region="$1"
    log_info "檢查 Auto Scaling Group 過度佈署 (區域: $region)..."
    asg="$(aws_try "$region" aws autoscaling describe-auto-scaling-groups --output json)"
    [[ "$asg" == __ERROR__* ]] && { emit "ASG:OverProvision" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    echo "$asg" | jq -c '.AutoScalingGroups[]?' | while read -r g; do
        name="$(echo "$g" | jq -r '.AutoScalingGroupName')"
        desired="$(echo "$g" | jq -r '.DesiredCapacity // 0')"
        inservice="$(echo "$g" | jq -r '[.Instances[]? | select(.LifecycleState=="InService")] | length')"
        min="$(echo "$g" | jq -r '.MinSize // 0')"
        
        # 檢查過度佈署：Desired - InService >= 1 或 Desired >= 2*Min
        if (( desired - inservice >= 1 )) || (( min > 0 && desired >= 2 * min )); then
            emit "ASG:OverProvision" "$name" "$region" "WARN" "LOW" "desired=$desired,inService=$inservice,min=$min"
        fi
    done
}

check_eks_nodegroups() {
    local region="$1"
    log_info "檢查 EKS NodeGroup 右調大小 (區域: $region)..."
    cls="$(aws_try "$region" aws eks list-clusters --query 'clusters' --output json)"
    [[ "$cls" == __ERROR__* ]] && { emit "EKS:NodeGroupRightsize" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    for c in $(echo "$cls" | jq -r '.[]'); do
        ngs="$(aws eks list-nodegroups --region "$region" --cluster-name "$c" --query 'nodegroups' --output json 2>/dev/null || echo '[]')"
        for ng in $(echo "$ngs" | jq -r '.[]'); do
            d="$(aws eks describe-nodegroup --region "$region" --cluster-name "$c" --nodegroup-name "$ng" --output json 2>/dev/null || echo '{}')"
            min="$(echo "$d" | jq -r '.nodegroup.scalingConfig.minSize // 0')"
            des="$(echo "$d" | jq -r '.nodegroup.scalingConfig.desiredSize // 0')"
            max="$(echo "$d" | jq -r '.nodegroup.scalingConfig.maxSize // 0')"
            
            if (( min > 0 && des >= 2 * min )); then
                emit "EKS:NodeGroupRightsize" "$c/$ng" "$region" "WARN" "LOW" "desired=$des,min=$min,max=$max"
            fi
        done
    done
}

check_lambda_mem_heuristic() {
    local region="$1"
    log_info "檢查 Lambda 記憶體配置啟發式 (區域: $region)..."
    funcs="$(aws_try "$region" aws lambda list-functions --query 'Functions[].{n:FunctionName,m:MemorySize,t:Timeout}' --output json)"
    [[ "$funcs" == __ERROR__* ]] && { emit "Lambda:OversizedMemory" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    echo "$funcs" | jq -c '.[]?' | while read -r f; do
        name="$(echo "$f" | jq -r '.n')"
        mem="$(echo "$f" | jq -r '.m')"
        to="$(echo "$f" | jq -r '.t')"
        
        # 啟發式：Timeout <= 2s 且 Memory >= 1024MB
        if (( to <= 2 && mem >= 1024 )); then
            emit "Lambda:OversizedMemory" "$name" "$region" "WARN" "LOW" "Memory=${mem}MB,Timeout=${to}s (consider downsize)"
        fi
    done
}

log_info "執行計算資源成本檢查 (區域: $REGION)..."
check_ec2_sp_candidates "$REGION"
check_ec2_type_tally "$REGION"
check_asg_overprovision "$REGION"
check_eks_nodegroups "$REGION"
check_lambda_mem_heuristic "$REGION"

# ========== 資料庫成本檢查 ==========

# 配置參數
ENABLE_METRICS="${ENABLE_METRICS:-0}"           # 0=關閉, 1=開啟 CloudWatch 指標檢查
LOOKBACK_DAYS="${LOOKBACK_DAYS:-7}"            # 指標回看天數
RDS_LOW_CPU_PCT="${RDS_LOW_CPU_PCT:-5}"        # RDS 低利用的 CPU% 門檻
DDB_IDLE_RCU_PER_HR="${DDB_IDLE_RCU_PER_HR:-1}" # DDB Idle 判斷
DDB_IDLE_WCU_PER_HR="${DDB_IDLE_WCU_PER_HR:-1}" # DDB Idle 判斷
RDS_SNAPSHOT_OLD_DAYS="${RDS_SNAPSHOT_OLD_DAYS:-90}" # 舊快照門檻
RDS_LONG_BACKUP_DAYS="${RDS_LONG_BACKUP_DAYS:-35}"  # 備份保存期過長門檻

check_rds_cost_basics() {
    local region="$1"
    log_info "檢查 RDS 基本成本配置 (區域: $region)..."
    dbs="$(aws_try "$region" aws rds describe-db-instances --output json)"
    [[ "$dbs" == __ERROR__* ]] && { emit "RDS:Describe" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    echo "$dbs" | jq -c '.DBInstances[]?' | while read -r db; do
        id="$(echo "$db" | jq -r '.DBInstanceIdentifier')"
        stype="$(echo "$db" | jq -r '.StorageType // "gp2"')"
        alloc="$(echo "$db" | jq -r '.AllocatedStorage // 0')"
        maxalloc="$(echo "$db" | jq -r '.MaxAllocatedStorage // 0')"
        brdays="$(echo "$db" | jq -r '.BackupRetentionPeriod // 0')"
        multi="$(echo "$db" | jq -r '.MultiAZ // false')"
        
        # gp2 儲存類型檢查
        [[ "$stype" == "gp2" ]] && emit "RDS:gp2" "$id" "$region" "WARN" "LOW" "StorageType=gp2 (consider gp3)"
        
        # 儲存自動擴展檢查
        if [[ "$maxalloc" -eq 0 || "$maxalloc" -le "$alloc" ]]; then
            emit "RDS:StorageAutoscaling" "$id" "$region" "WARN" "LOW" "MaxAllocatedStorage<=Allocated (autoscaling not configured)"
        fi
        
        # 備份保留期檢查
        if (( brdays > RDS_LONG_BACKUP_DAYS )); then
            emit "RDS:LongBackupRetention" "$id" "$region" "WARN" "LOW" "BackupRetentionPeriod=${brdays}d (> ${RDS_LONG_BACKUP_DAYS}d)"
        fi
        
        # Multi-AZ 成本提示
        [[ "$multi" == "true" ]] && emit "RDS:MultiAZCost" "$id" "$region" "INFO" "LOW" "Multi-AZ incurs ~2x instance+storage cost (validate HA need)"
    done
}

check_rds_old_snapshots() {
    local region="$1"
    log_info "檢查 RDS 舊快照 (區域: $region)..."
    snaps="$(aws_try "$region" aws rds describe-db-snapshots --output json)"
    [[ "$snaps" == __ERROR__* ]] && { emit "RDS:Snapshots" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    echo "$snaps" | jq -c '.DBSnapshots[]?' | while read -r s; do
        sid="$(echo "$s" | jq -r '.DBSnapshotIdentifier')"
        t="$(echo "$s" | jq -r '.SnapshotCreateTime')"
        days="$(days_since_iso "$t" 2>/dev/null || echo 0)"
        
        if (( days > RDS_SNAPSHOT_OLD_DAYS )); then
            emit "RDS:OldSnapshot" "$sid" "$region" "WARN" "LOW" "age_days=${days} (> ${RDS_SNAPSHOT_OLD_DAYS})"
        fi
    done
}

check_rds_low_cpu() {
    local region="$1"
    [[ "$ENABLE_METRICS" != "1" ]] && return
    
    log_info "檢查 RDS 低 CPU 使用率 (區域: $region)..."
    dbs="$(aws_try "$region" aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output json)"
    [[ "$dbs" == __ERROR__* ]] && { emit "RDS:LowCPU" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    start="$(date -u -d "$LOOKBACK_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)"
    
    for id in $(echo "$dbs" | jq -r '.[]'); do
        pts="$(aws cloudwatch get-metric-statistics --region "$region" \
            --namespace AWS/RDS --metric-name CPUUtilization \
            --dimensions Name=DBInstanceIdentifier,Value="$id" \
            --start-time "$start" --end-time "$end" --period 3600 --statistics Average \
            --query 'Datapoints[].Average' --output json 2>/dev/null || echo '[]')"
        
        if [[ "$(echo "$pts" | jq 'length')" -gt 0 ]]; then
            maxv="$(echo "$pts" | jq -r 'max // 0')"
            if [[ "$(python3 - <<PY "$maxv" "$RDS_LOW_CPU_PCT"
mx=float(__import__("sys").argv[1]); thr=float(__import__("sys").argv[2]); print("LOW" if mx<thr else "OK")
PY
)" == "LOW" ]]; then
                emit "RDS:LowCPU" "$id" "$region" "WARN" "MEDIUM" "Max CPU < ${RDS_LOW_CPU_PCT}% in last ${LOOKBACK_DAYS}d"
            fi
        fi
    done
}

check_ddb_mode_autoscaling_ttl() {
    local region="$1"
    log_info "檢查 DynamoDB 模式和配置 (區域: $region)..."
    tabs="$(aws_try "$region" aws dynamodb list-tables --query 'TableNames' --output json)"
    [[ "$tabs" == __ERROR__* ]] && { emit "DDB:Tables" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    # 取得 Application Auto Scaling 綁定
    targets="$(aws application-autoscaling describe-scalable-targets --region "$region" --service-namespace dynamodb --output json 2>/dev/null || echo '{"ScalableTargets":[]}')"
    asg_list="$(echo "$targets" | jq -r '.ScalableTargets[].ResourceId' | sort -u)"
    
    for t in $(echo "$tabs" | jq -r '.[]'); do
        desc="$(aws dynamodb describe-table --region "$region" --table-name "$t" --output json 2>/dev/null || echo '{}')"
        mode="$(echo "$desc" | jq -r '.Table.BillingModeSummary.BillingMode // "PROVISIONED"')"
        
        ttl_cfg="$(aws dynamodb describe-time-to-live --region "$region" --table-name "$t" --output json 2>/dev/null || echo '{}')"
        ttl_status="$(echo "$ttl_cfg" | jq -r '.TimeToLiveDescription.TimeToLiveStatus // "DISABLED"')"
        
        # 檢查 Provisioned 模式是否有 Auto Scaling
        if [[ "$mode" == "PROVISIONED" ]]; then
            res_tbl="table/$t"
            has_as="$(echo "$asg_list" | grep -q "^${res_tbl}$" && echo yes || echo no)"
            [[ "$has_as" == "no" ]] && emit "DDB:NoAutoScaling" "$t" "$region" "WARN" "LOW" "Provisioned but no Application Auto Scaling target"
        fi
        
        # TTL 檢查
        [[ "$ttl_status" != "ENABLED" ]] && emit "DDB:TTLDisabled" "$t" "$region" "WARN" "LOW" "TTL not enabled (storage may grow)"
    done
}

check_ddb_idle_metrics() {
    local region="$1"
    [[ "$ENABLE_METRICS" != "1" ]] && return
    
    log_info "檢查 DynamoDB 閒置指標 (區域: $region)..."
    tabs="$(aws_try "$region" aws dynamodb list-tables --query 'TableNames' --output json)"
    [[ "$tabs" == __ERROR__* ]] && { emit "DDB:Idle" "-" "$region" "INFO" "LOW" "AccessDenied/None"; return; }
    
    end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    start="$(date -u -d "$LOOKBACK_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)"
    hours=$(( LOOKBACK_DAYS * 24 ))
    
    for t in $(echo "$tabs" | jq -r '.[]'); do
        rcu="$(aws cloudwatch get-metric-statistics --region "$region" \
            --namespace AWS/DynamoDB --metric-name ConsumedReadCapacityUnits \
            --dimensions Name=TableName,Value="$t" \
            --start-time "$start" --end-time "$end" --period 3600 --statistics Sum \
            --query 'Datapoints[].Sum' --output json 2>/dev/null || echo '[]')"
        
        wcu="$(aws cloudwatch get-metric-statistics --region "$region" \
            --namespace AWS/DynamoDB --metric-name ConsumedWriteCapacityUnits \
            --dimensions Name=TableName,Value="$t" \
            --start-time "$start" --end-time "$end" --period 3600 --statistics Sum \
            --query 'Datapoints[].Sum' --output json 2>/dev/null || echo '[]')"
        
        avg_rcu=$(python3 - <<PY "$rcu" "$hours"
import sys,json;arr=json.loads(sys.argv[1]); hrs=int(sys.argv[2]); print(0 if hrs==0 else (sum(arr)/hrs if len(arr)>0 else 0))
PY
)
        avg_wcu=$(python3 - <<PY "$wcu" "$hours"
import sys,json;arr=json.loads(sys.argv[1]); hrs=int(sys.argv[2]); print(0 if hrs==0 else (sum(arr)/hrs if len(arr)>0 else 0))
PY
)
        
        # 檢查是否閒置
        awk_rcu=$(python3 - <<PY "$avg_rcu" "$DDB_IDLE_RCU_PER_HR"
import sys;print(1 if float(sys.argv[1])<float(sys.argv[2]) else 0)
PY
)
        awk_wcu=$(python3 - <<PY "$avg_wcu" "$DDB_IDLE_WCU_PER_HR"
import sys;print(1 if float(sys.argv[1])<float(sys.argv[2]) else 0)
PY
)
        
        if [[ "$awk_rcu" == "1" && "$awk_wcu" == "1" ]]; then
            emit "DDB:Idle" "$t" "$region" "WARN" "MEDIUM" "Avg/hour RCU=${avg_rcu}, WCU=${avg_wcu} over ${LOOKBACK_DAYS}d"
        fi
    done
}

log_info "執行資料庫成本檢查 (區域: $REGION)..."
check_rds_cost_basics "$REGION"
check_rds_old_snapshots "$REGION"
check_rds_low_cpu "$REGION"
check_ddb_mode_autoscaling_ttl "$REGION"
check_ddb_idle_metrics "$REGION"

# ========== 網路成本檢查 ==========

check_network_cost_basics() {
    local region="$1"
    log_info "檢查網路基本成本配置 (區域: $region)..."
    
    # NAT Gateway 檢查
    local natgw nat_count
    natgw="$(aws ec2 describe-nat-gateways --region "$region" --output json 2>/dev/null || echo '{}')"
    nat_count="$(echo "$natgw" | jq '[.NatGateways[]? | select(.State!="deleted")] | length')"
    
    if (( nat_count > 0 )); then
        emit "NET:NATGatewayCount" "-" "$region" "INFO" "LOW" "count=${nat_count} (hourly + data processing/transfer cost)"
        echo "$natgw" | jq -r '.NatGateways[]? | select(.State!="deleted") | [.NatGatewayId, .SubnetId, .ConnectivityType, .State] | @tsv' \
        | while read -r id subnet ctype state; do
            emit "NET:NATGatewayDetail" "$id" "$region" "INFO" "LOW" "Subnet=$subnet ConnectivityType=$ctype State=$state"
        done
    else
        emit "NET:NATGatewayCount" "-" "$region" "INFO" "LOW" "No active NAT Gateways"
    fi
    
    # CloudFront 檢查 (只在第一個區域執行，因為是全域服務)
    if [[ "$region" == "$REGION" ]]; then
        local cf cf_count
        cf="$(aws cloudfront list-distributions --output json 2>/dev/null || echo '{}')"
        cf_count="$(echo "$cf" | jq '[.DistributionList.Items[]?] | length')"
        emit "NET:CloudFrontCount" "global" "global" "INFO" "LOW" "count=${cf_count}"
        
        echo "$cf" | jq -r '.DistributionList.Items[]? | [.Id, .DomainName, .PriceClass, .DefaultCacheBehavior.ViewerProtocolPolicy] | @tsv' \
        | while read -r id domain price vpp; do
            # 價格等級檢查
            if [[ "$price" == "PriceClass_All" ]]; then
                emit "NET:CloudFrontPriceClass" "$id($domain)" "global" "WARN" "MEDIUM" "PriceClass_All (consider 200/100)"
            elif [[ "$price" == "PriceClass_200" ]]; then
                emit "NET:CloudFrontPriceClass" "$id($domain)" "global" "INFO" "LOW" "PriceClass_200 (consider 100 if traffic localized)"
            fi
            
            # HTTPS 重定向檢查
            [[ "$vpp" == "redirect-to-https" ]] && emit "NET:CloudFrontHTTPSRedirect" "$id($domain)" "global" "INFO" "LOW" "ViewerProtocolPolicy=redirect-to-https"
        done
    fi
    
    # Transit Gateway 檢查
    local tgw tgw_count
    tgw="$(aws ec2 describe-transit-gateways --region "$region" --output json 2>/dev/null || echo '{}')"
    tgw_count="$(echo "$tgw" | jq '[.TransitGateways[]?] | length')"
    
    if (( tgw_count > 0 )); then
        emit "NET:TransitGatewayCount" "-" "$region" "INFO" "LOW" "count=${tgw_count} (per-hour + per-GB data processing)"
        echo "$tgw" | jq -r '.TransitGateways[]? | [.TransitGatewayId, .State, .OwnerId, .Options.DnsSupport, .Options.VpnEcmpSupport, .Options.MulticastSupport] | @tsv' \
        | while read -r id state owner dns ecmp mcast; do
            emit "NET:TransitGatewayDetail" "$id" "$region" "INFO" "LOW" "State=$state Owner=$owner DNS=$dns ECMP=$ecmp Multicast=$mcast"
        done
    else
        emit "NET:TransitGatewayCount" "-" "$region" "INFO" "LOW" "No active Transit Gateways"
    fi
}

check_vpc_endpoints() {
    local region="$1"
    log_info "檢查 VPC Endpoints (區域: $region)..."
    
    local vpes vpe_total
    vpes="$(aws_try "$region" aws ec2 describe-vpc-endpoints --output json || true)"
    if [[ "$vpes" == __ERROR__* || -z "$vpes" ]]; then
        emit "NET:VPCEListError" "-" "$region" "INFO" "LOW" "${vpes:0:200}"
        return
    fi
    
    vpe_total="$(echo "$vpes" | jq '.VpcEndpoints | length')"
    emit "NET:VPCECount" "-" "$region" "INFO" "LOW" "count=${vpe_total}"
    
    # 各類型數量統計
    for t in Interface Gateway GatewayLoadBalancer; do
        local cnt
        cnt="$(echo "$vpes" | jq --arg T "$t" '[.VpcEndpoints[]? | select(.VpcEndpointType==$T and .State=="available")] | length')"
        emit "NET:VPCETypeCount" "$t" "$region" "INFO" "LOW" "available=${cnt}"
    done
    
    # Interface 端點詳細檢查
    echo "$vpes" \
    | jq -r '.VpcEndpoints[]?| select(.VpcEndpointType=="Interface")| [.VpcEndpointId,.ServiceName,(.SubnetIds|length),(.NetworkInterfaceIds|length),(.PrivateDnsEnabled // false),.State] | @tsv' \
    | while read -r id svc subnets enis pdns state; do
        local note="Service=$svc Subnets=$subnets ENIs=$enis PrivateDNS=$pdns State=$state"
        
        # 私有 DNS 檢查
        if [[ "$pdns" == "false" ]]; then
            emit "NET:VPCEInterfacePrivateDNS" "$id" "$region" "WARN" "LOW" "$note (consider enabling PrivateDns if supported)"
        else
            emit "NET:VPCEInterfaceDetail" "$id" "$region" "INFO" "LOW" "$note"
        fi
    done
    
    # Gateway 端點檢查
    echo "$vpes" \
    | jq -r '.VpcEndpoints[]?| select(.VpcEndpointType=="Gateway")| [.VpcEndpointId,.ServiceName,(.RouteTableIds|length),.State] | @tsv' \
    | while read -r id svc rts state; do
        emit "NET:VPCEGatewayDetail" "$id" "$region" "INFO" "LOW" "Service=$svc RouteTables=$rts State=$state"
    done
}

check_nlb_idle() {
    local region="$1"
    log_info "檢查 NLB 閒置狀況 (區域: $region)..."
    
    local lbs
    lbs="$(aws_try "$region" aws elbv2 describe-load-balancers --output json || true)"
    if [[ "$lbs" == __ERROR__* || -z "$lbs" ]]; then
        emit "NET:NLBListError" "-" "$region" "INFO" "LOW" "${lbs:0:200}"
        return
    fi
    
    # 只檢查 Network Load Balancer
    echo "$lbs" \
    | jq -r '.LoadBalancers[]? | select(.Type=="network") | [.LoadBalancerArn, .LoadBalancerName, .Scheme, .State.Code] | @tsv' \
    | while read -r lbarn lbname scheme state; do
        # 檢查 Listeners
        local listeners lcount
        listeners="$(aws elbv2 describe-listeners --region "$region" --load-balancer-arn "$lbarn" --output json 2>/dev/null || echo '{"Listeners":[]}')"
        lcount="$(echo "$listeners" | jq '.Listeners | length')"
        
        # 檢查 Target Groups
        local tgs tg_arns
        tgs="$(aws elbv2 describe-target-groups --region "$region" --load-balancer-arn "$lbarn" --output json 2>/dev/null || echo '{"TargetGroups":[]}')"
        tg_arns=($(echo "$tgs" | jq -r '.TargetGroups[]?.TargetGroupArn'))
        
        # 沒有 Listener
        if (( lcount == 0 )); then
            emit "NET:NLBIdle" "$lbname" "$region" "WARN" "MEDIUM" "No listeners (Scheme=$scheme State=$state)"
            continue
        fi
        
        # 沒有 Target Group
        if (( ${#tg_arns[@]} == 0 )); then
            emit "NET:NLBIdle" "$lbname" "$region" "WARN" "MEDIUM" "No target groups attached (Scheme=$scheme State=$state)"
            continue
        fi
        
        # 檢查 Target Group 是否有註冊的目標
        local all_zero=1
        for tg in "${tg_arns[@]}"; do
            local th tcnt
            th="$(aws elbv2 describe-target-health --region "$region" --target-group-arn "$tg" --output json 2>/dev/null || echo '{"TargetHealthDescriptions":[]}')"
            tcnt="$(echo "$th" | jq '.TargetHealthDescriptions | length')"
            if (( tcnt > 0 )); then 
                all_zero=0
                break
            fi
        done
        
        if (( all_zero == 1 )); then
            emit "NET:NLBIdle" "$lbname" "$region" "WARN" "MEDIUM" "All target groups have 0 registered targets (Scheme=$scheme State=$state)"
        else
            emit "NET:NLBDetail" "$lbname" "$region" "INFO" "LOW" "Listeners=$lcount TGs=${#tg_arns[@]} Scheme=$scheme State=$state"
        fi
    done
}

log_info "執行網路成本檢查 (區域: $REGION)..."
check_network_cost_basics "$REGION"
check_vpc_endpoints "$REGION"
check_nlb_idle "$REGION"

# ========== 監控和資料流成本檢查 ==========

# 配置參數
CW_RETENTION_OK_DAYS="${CW_RETENTION_OK_DAYS:-30}"     # 預設 log group 應該設保留期 <=30 天
CW_RETENTION_WARN_DAYS="${CW_RETENTION_WARN_DAYS:-90}" # >90 天為高成本風險
CW_METRIC_FILTER_LIMIT="${CW_METRIC_FILTER_LIMIT:-50}" # 太多自訂 Metric Filter 提醒
KIN_STREAM_IDLE_DAYS="${KIN_STREAM_IDLE_DAYS:-14}"     # 若無消費活動 14 天以上提醒

check_cw_logs_enhanced() {
    local region="$1"
    log_info "檢查 CloudWatch Logs 詳細配置 (區域: $region)..."
    
    local logs
    logs="$(aws_try "$region" aws logs describe-log-groups --output json || true)"
    if [[ "$logs" == __ERROR__* || -z "$logs" ]]; then
        emit "CW:DescribeLogsError" "-" "$region" "INFO" "LOW" "${logs:0:200}"
        return
    fi
    
    local count
    count="$(echo "$logs" | jq '.logGroups|length')"
    emit "CW:LogGroupCount" "-" "$region" "INFO" "LOW" "count=$count"
    
    echo "$logs" | jq -r '.logGroups[]? | [.logGroupName, (.retentionInDays // 0)] | @tsv' \
    | while read -r name days; do
        if [[ "$days" == "0" ]]; then
            emit "CW:NoRetention" "$name" "$region" "WARN" "HIGH" "No retention policy (infinite storage cost)"
        elif (( days > CW_RETENTION_WARN_DAYS )); then
            emit "CW:LongRetention" "$name" "$region" "WARN" "MEDIUM" "Retention=$days days (>${CW_RETENTION_WARN_DAYS})"
        elif (( days > CW_RETENTION_OK_DAYS )); then
            emit "CW:ModerateRetention" "$name" "$region" "INFO" "LOW" "Retention=$days days"
        fi
    done
}

check_cw_metrics_alarms() {
    local region="$1"
    log_info "檢查 CloudWatch Metrics 和 Alarms (區域: $region)..."
    
    # 檢查 Metrics
    local metrics
    metrics="$(aws_try "$region" aws cloudwatch list-metrics --namespace AWS/EC2 --output json || true)"
    if [[ "$metrics" == __ERROR__* || -z "$metrics" ]]; then
        emit "CW:MetricsError" "-" "$region" "INFO" "LOW" "${metrics:0:200}"
    else
        local count
        count="$(echo "$metrics" | jq '.Metrics|length')"
        emit "CW:MetricCount" "-" "$region" "INFO" "LOW" "AWS/EC2 metrics count=$count"
    fi
    
    # 檢查 Alarms
    local alarms
    alarms="$(aws_try "$region" aws cloudwatch describe-alarms --output json || true)"
    if [[ "$alarms" == __ERROR__* || -z "$alarms" ]]; then
        emit "CW:AlarmsError" "-" "$region" "INFO" "LOW" "${alarms:0:200}"
    else
        local acount
        acount="$(echo "$alarms" | jq '.MetricAlarms|length')"
        emit "CW:AlarmsCount" "-" "$region" "INFO" "LOW" "count=$acount"
        
        # 檢查過多的 Alarms
        if (( acount > 100 )); then
            emit "CW:TooManyAlarms" "-" "$region" "WARN" "LOW" "count=$acount (consider consolidation)"
        fi
        
        # 檢查未使用的 Alarms (狀態為 INSUFFICIENT_DATA 超過一定時間)
        echo "$alarms" | jq -c '.MetricAlarms[]? | select(.StateValue=="INSUFFICIENT_DATA")' | while read -r alarm; do
            alarm_name="$(echo "$alarm" | jq -r '.AlarmName')"
            emit "CW:InsufficientDataAlarm" "$alarm_name" "$region" "WARN" "LOW" "Alarm in INSUFFICIENT_DATA state"
        done
    fi
}

check_kinesis_streams_cost() {
    local region="$1"
    log_info "檢查 Kinesis Data Streams 成本 (區域: $region)..."
    
    local streams
    streams="$(aws_try "$region" aws kinesis list-streams --output json || true)"
    if [[ "$streams" == __ERROR__* || -z "$streams" ]]; then
        emit "Kinesis:ListError" "-" "$region" "INFO" "LOW" "${streams:0:200}"
        return
    fi
    
    local scount
    scount="$(echo "$streams" | jq '.StreamNames|length')"
    emit "Kinesis:StreamCount" "-" "$region" "INFO" "LOW" "count=$scount"
    
    echo "$streams" | jq -r '.StreamNames[]?' | while read -r s; do
        local desc
        desc="$(aws_try "$region" aws kinesis describe-stream-summary --stream-name "$s" --output json || true)"
        if [[ "$desc" == __ERROR__* || -z "$desc" ]]; then
            emit "Kinesis:DescribeError" "$s" "$region" "INFO" "LOW" "${desc:0:200}"
            continue
        fi
        
        local shards status ret mode
        shards="$(echo "$desc" | jq -r '.StreamDescriptionSummary.OpenShardCount // 0')"
        status="$(echo "$desc" | jq -r '.StreamDescriptionSummary.StreamStatus // "UNKNOWN"')"
        ret="$(echo "$desc" | jq -r '.StreamDescriptionSummary.RetentionPeriodHours // 0')"
        mode="$(echo "$desc" | jq -r '.StreamDescriptionSummary.StreamModeDetails.StreamMode // "PROVISIONED"')"
        
        emit "Kinesis:StreamInfo" "$s" "$region" "INFO" "LOW" "Shards=$shards RetentionHrs=$ret Mode=$mode Status=$status"
        
        # 檢查 Provisioned 模式的高 Shard 數量
        if [[ "$mode" == "PROVISIONED" && "$shards" -gt 2 ]]; then
            emit "Kinesis:ProvisionedHigh" "$s" "$region" "WARN" "MEDIUM" "Provisioned mode with $shards shards (consider On-Demand)"
        fi
        
        # 檢查長保留期
        if (( ret > 168 )); then  # 超過 7 天
            emit "Kinesis:LongRetention" "$s" "$region" "WARN" "LOW" "Retention=$ret hours (consider shorter period)"
        fi
        
        # 檢查閒置 Stream (如果狀態不是 ACTIVE)
        if [[ "$status" != "ACTIVE" ]]; then
            emit "Kinesis:InactiveStream" "$s" "$region" "WARN" "MEDIUM" "Stream status=$status (consider cleanup)"
        fi
    done
}

log_info "執行監控和資料流成本檢查 (區域: $REGION)..."
check_cw_logs_enhanced "$REGION"
check_cw_metrics_alarms "$REGION"
check_kinesis_streams_cost "$REGION"

# ========== 資料傳輸成本檢查 ==========

# 配置參數
CHECK_S3_REPLICATION="${CHECK_S3_REPLICATION:-1}"       # 檢查 S3 跨區複寫
CHECK_CF_ORIGIN="${CHECK_CF_ORIGIN:-1}"                 # CloudFront Origin 類型/PriceClass 提示
CHECK_ELB2_CROSSZONE="${CHECK_ELB2_CROSSZONE:-1}"       # ELBv2 Cross-Zone 成本風險
CHECK_VPC_PEERING="${CHECK_VPC_PEERING:-1}"             # VPC Peering 清單
CHECK_TGW="${CHECK_TGW:-1}"                             # Transit Gateway 摘要
CHECK_NAT="${CHECK_NAT:-1}"                             # NAT Gateway 數量與狀態
CHECK_VPCE="${CHECK_VPCE:-1}"                           # VPC Endpoint 狀態

check_cloudfront_dt() {
    local r="global"
    [[ "$CHECK_CF_ORIGIN" != "1" ]] && return
    
    # 只在主要區域執行 CloudFront 檢查（全域服務）
    [[ "$REGION" != "us-east-1" ]] && return
    
    log_info "檢查 CloudFront 資料傳輸配置..."
    local dists
    dists="$(aws_try "$r" aws cloudfront list-distributions --output json || true)"
    if [[ "$dists" == __ERROR__* || -z "$dists" ]]; then
        emit "DT:CloudFrontListError" "-" "$r" "INFO" "LOW" "${dists:0:200}"
        return
    fi
    
    local count
    count="$(echo "$dists" | jq '.DistributionList.Items|length // 0')"
    emit "DT:CloudFrontCount" "global" "$r" "INFO" "LOW" "count=${count}"
    
    echo "$dists" | jq -c '.DistributionList.Items[]?' | while read -r d; do
        local id domain pc
        id="$(echo "$d" | jq -r '.Id')"
        domain="$(echo "$d" | jq -r '.DomainName')"
        pc="$(echo "$d" | jq -r '.PriceClass // "PriceClass_All"')"
        
        emit "DT:CloudFrontPriceClass" "$id($domain)" "$r" \
            "$([[ "$pc" == "PriceClass_All" ]] && echo WARN || echo INFO)" \
            "$([[ "$pc" == "PriceClass_All" ]] && echo MEDIUM || echo LOW)" \
            "PriceClass=${pc} (consider 200/100 if audience limited)"
        
        # Origin 類型提示
        local origins
        origins="$(echo "$d" | jq -c '.Origins.Items[]? | {Id,DomainName,OriginType:(if .S3OriginConfig then "S3" elif .CustomOriginConfig then "Custom" else "Other" end)}')"
        while read -r o; do
            [[ -z "$o" ]] && continue
            local oid odom otype
            oid="$(echo "$o" | jq -r '.Id')"
            odom="$(echo "$o" | jq -r '.DomainName')"
            otype="$(echo "$o" | jq -r '.OriginType')"
            emit "DT:CloudFrontOrigin" "$id/$oid" "$r" "INFO" "LOW" "OriginType=${otype} Domain=${odom}"
        done <<< "$(printf '%s\n' "$origins")"
    done
}

check_s3_replication_dt() {
    local r="global"
    [[ "$CHECK_S3_REPLICATION" != "1" ]] && return
    
    # 只在主要區域執行 S3 檢查（全域服務）
    [[ "$REGION" != "us-east-1" ]] && return
    
    log_info "檢查 S3 跨區複寫資料傳輸..."
    local buckets
    buckets="$(aws s3api list-buckets --output json 2>/dev/null || echo '{"Buckets":[]}')"
    
    echo "$buckets" | jq -r '.Buckets[]?.Name' | while read -r b; do
        local rep
        rep="$(aws s3api get-bucket-replication --bucket "$b" --output json 2>&1 || true)"
        if [[ "$rep" == {* || "$rep" == [* ]]; then
            local rules
            rules="$(printf '%s' "$rep" | jq -c '.ReplicationConfiguration.Rules[]?')"
            while read -r rule; do
                [[ -z "$rule" ]] && continue
                local dest destbucket
                dest="$(echo "$rule" | jq -r '.Destination')"
                destbucket="$(echo "$dest" | jq -r '.Bucket')"
                emit "DT:S3CRR" "$b" "$r" "INFO" "LOW" "ReplicateTo=${destbucket} (cross-region transfer billed at source region)"
            done <<< "$rules"
        fi
    done
}

check_elb2_crosszone_dt() {
    local region="$1"
    [[ "$CHECK_ELB2_CROSSZONE" != "1" ]] && return
    
    log_info "檢查 ELB Cross-Zone 資料傳輸 (區域: $region)..."
    local lbs
    lbs="$(aws_try "$region" aws elbv2 describe-load-balancers --output json || true)"
    if [[ "$lbs" == __ERROR__* || -z "$lbs" ]]; then
        emit "DT:ELBv2ListError" "-" "$region" "INFO" "LOW" "${lbs:0:200}"
        return
    fi
    
    echo "$lbs" | jq -c '.LoadBalancers[]?' | while read -r lb; do
        local arn name type
        arn="$(echo "$lb" | jq -r '.LoadBalancerArn')"
        name="$(echo "$lb" | jq -r '.LoadBalancerName')"
        type="$(echo "$lb" | jq -r '.Type')"
        
        # Cross-zone attribute
        local attrs cz
        attrs="$(aws elbv2 describe-load-balancer-attributes --region "$region" --load-balancer-arn "$arn" --output json 2>/dev/null || echo '{"Attributes": []}')"
        cz="$(echo "$attrs" | jq -r '.Attributes[]?|select(.Key=="load_balancing.cross_zone.enabled")|.Value // "false"')"
        
        emit "DT:ELBv2CrossZone" "$name($type)" "$region" "INFO" "LOW" "cross_zone=${cz}"
        
        # NLB 跨 AZ 成本風險提示
        if [[ "$type" == "network" && "$cz" == "true" ]]; then
            local tgs
            tgs="$(aws elbv2 describe-target-groups --region "$region" --load-balancer-arn "$arn" --output json 2>/dev/null || echo '{"TargetGroups": []}')"
            echo "$tgs" | jq -r '.TargetGroups[]?.TargetGroupArn' | while read -r tg; do
                local th azs
                th="$(aws elbv2 describe-target-health --region "$region" --target-group-arn "$tg" --output json 2>/dev/null || echo '{"TargetHealthDescriptions": []}')"
                azs="$(echo "$th" | jq -r '[.TargetHealthDescriptions[]?.AvailabilityZone]|unique|join(",")')"
                
                if [[ -n "$azs" && "$azs" == *","* ]]; then
                    emit "DT:NLBInterAZRisk" "$name/$tg" "$region" "WARN" "MEDIUM" "cross_zone=true targets_multi_AZ=${azs} (inter-AZ DT billed per GB for NLB)"
                fi
            done
        fi
    done
}

check_vpc_peering_dt() {
    local region="$1"
    [[ "$CHECK_VPC_PEERING" != "1" ]] && return
    
    log_info "檢查 VPC Peering 資料傳輸 (區域: $region)..."
    local ps
    ps="$(aws_try "$region" aws ec2 describe-vpc-peering-connections --output json || true)"
    if [[ "$ps" == __ERROR__* || -z "$ps" ]]; then
        emit "DT:PeeringListError" "-" "$region" "INFO" "LOW" "${ps:0:200}"
        return
    fi
    
    local cnt
    cnt="$(echo "$ps" | jq '.VpcPeeringConnections|length')"
    emit "DT:PeeringCount" "-" "$region" "INFO" "LOW" "count=${cnt}"
    
    echo "$ps" | jq -c '.VpcPeeringConnections[]? | {Id:.VpcPeeringConnectionId,Status:.Status.Code,Accepter:.AccepterVpcInfo.VpcId,Requester:.RequesterVpcInfo.VpcId}' \
    | while read -r row; do
        local id st a r
        id="$(echo "$row" | jq -r '.Id')"
        st="$(echo "$row" | jq -r '.Status')"
        a="$(echo "$row" | jq -r '.Accepter')"
        r="$(echo "$row" | jq -r '.Requester')"
        emit "DT:Peering" "$id" "$region" "INFO" "LOW" "Status=${st} Requester=${r} Accepter=${a}"
    done
}

check_tgw_dt() {
    local region="$1"
    [[ "$CHECK_TGW" != "1" ]] && return
    
    log_info "檢查 Transit Gateway 資料傳輸 (區域: $region)..."
    local tgws
    tgws="$(aws_try "$region" aws ec2 describe-transit-gateways --output json || true)"
    if [[ "$tgws" == __ERROR__* || -z "$tgws" ]]; then
        emit "DT:TGWListError" "-" "$region" "INFO" "LOW" "${tgws:0:200}"
        return
    fi
    
    local cnt
    cnt="$(echo "$tgws" | jq '.TransitGateways|length')"
    emit "DT:TGWCount" "-" "$region" "INFO" "LOW" "count=${cnt}"
    
    echo "$tgws" | jq -c '.TransitGateways[]? | {Id:.TransitGatewayId,State:.State,OwnerId:.OwnerId,Options:.Options}' \
    | while read -r t; do
        emit "DT:TGW" "$(echo "$t" | jq -r '.Id')" "$region" "INFO" "LOW" "$(echo "$t" | jq -r '@json')"
    done
}

check_nat_dt() {
    local region="$1"
    [[ "$CHECK_NAT" != "1" ]] && return
    
    log_info "檢查 NAT Gateway 資料傳輸 (區域: $region)..."
    local ngws
    ngws="$(aws_try "$region" aws ec2 describe-nat-gateways --filter Name=state,Values=available --output json || true)"
    if [[ "$ngws" == __ERROR__* || -z "$ngws" ]]; then
        emit "DT:NATListError" "-" "$region" "INFO" "LOW" "${ngws:0:200}"
        return
    fi
    
    local cnt
    cnt="$(echo "$ngws" | jq '.NatGateways|length')"
    emit "DT:NATCount" "-" "$region" "INFO" "LOW" "active=${cnt}"
}

check_vpce_dt() {
    local region="$1"
    [[ "$CHECK_VPCE" != "1" ]] && return
    
    log_info "檢查 VPC Endpoints 資料傳輸 (區域: $region)..."
    local e
    e="$(aws_try "$region" aws ec2 describe-vpc-endpoints --output json || true)"
    if [[ "$e" == __ERROR__* || -z "$e" ]]; then
        emit "DT:VPCEListError" "-" "$region" "INFO" "LOW" "${e:0:200}"
        return
    fi
    
    local total
    total="$(echo "$e" | jq '.VpcEndpoints|length')"
    emit "DT:VPCECount" "-" "$region" "INFO" "LOW" "count=${total}"
    
    # 類型細分：Interface（每小時+每GB）, Gateway（S3/DynamoDB 免費）
    local iface gw gwlb
    iface="$(echo "$e" | jq '[.VpcEndpoints[]?|select(.VpcEndpointType=="Interface")]|length')"
    gw="$(echo "$e" | jq '[.VpcEndpoints[]?|select(.VpcEndpointType=="Gateway")]|length')"
    gwlb="$(echo "$e" | jq '[.VpcEndpoints[]?|select(.VpcEndpointType=="GatewayLoadBalancer")]|length')"
    
    emit "DT:VPCETypeCount" "Interface" "$region" "INFO" "LOW" "count=${iface}"
    emit "DT:VPCETypeCount" "Gateway" "$region" "INFO" "LOW" "count=${gw}"
    emit "DT:VPCETypeCount" "GatewayLoadBalancer" "$region" "INFO" "LOW" "count=${gwlb}"
}

log_info "執行資料傳輸成本檢查 (區域: $REGION)..."
check_cloudfront_dt
check_s3_replication_dt
check_elb2_crosszone_dt "$REGION"
check_vpc_peering_dt "$REGION"
check_tgw_dt "$REGION"
check_nat_dt "$REGION"
check_vpce_dt "$REGION"

# ========== 儲存成本檢查 ==========

# 配置參數
EBS_SNAPSHOT_OLD_DAYS="${EBS_SNAPSHOT_OLD_DAYS:-90}"     # 舊 EBS 快照門檻
EBS_WARN_GP2="${EBS_WARN_GP2:-1}"                       # 偵測 gp2 並建議改 gp3
EFS_REQUIRE_LIFECYCLE="${EFS_REQUIRE_LIFECYCLE:-1}"      # EFS 未啟用 IA/Archive 轉檔則警告
S3_WARN_NO_LC="${S3_WARN_NO_LC:-1}"                     # S3 無生命週期規則則警告
S3_WARN_VER_BUT_NO_LC="${S3_WARN_VER_BUT_NO_LC:-1}"     # S3 開版本控但沒規則清理舊版

check_s3_storage_cost() {
    local r="global"
    log_info "檢查 S3 儲存成本配置..."
    
    # 只在第一次執行時檢查 S3 (全域服務)
    if [[ "$REGION" != "${REGIONS_ARR[0]:-$REGION}" ]]; then
        return
    fi
    
    local buckets
    buckets="$(aws s3api list-buckets --output json 2>/dev/null || echo '{"Buckets":[]}')"
    local cnt
    cnt="$(echo "$buckets" | jq '.Buckets|length')"
    emit "S3:BucketCount" "-" "$r" "INFO" "LOW" "count=${cnt}"
    
    echo "$buckets" | jq -r '.Buckets[]?.Name' | while read -r b; do
        # 版本控制檢查
        local ver
        ver="$(aws s3api get-bucket-versioning --bucket "$b" --output json 2>/dev/null || echo '{}')"
        local vs
        vs="$(echo "$ver" | jq -r '.Status // "Disabled"')"
        
        # 生命週期規則檢查
        local lc
        lc="$(aws s3api get-bucket-lifecycle-configuration --bucket "$b" --output json 2>&1 || true)"
        local has_lc="no"
        if [[ "$lc" == {* || "$lc" == [* ]]; then
            local lcount
            lcount="$(printf '%s' "$lc" | jq '.Rules | length' 2>/dev/null || echo 0)"
            [[ "$lcount" -gt 0 ]] && has_lc="yes"
        fi
        
        # 傳輸加速檢查
        local acc
        acc="$(aws s3api get-bucket-accelerate-configuration --bucket "$b" --output text 2>/dev/null || echo 'Suspended')"
        
        # 輸出基本資訊
        emit "S3:BucketInfo" "$b" "$r" "INFO" "LOW" "Versioning=$vs LifecycleRules=$has_lc Acceleration=$acc"
        
        # 成本建議
        if [[ "$S3_WARN_NO_LC" == "1" && "$has_lc" == "no" ]]; then
            emit "S3:Lifecycle" "$b" "$r" "WARN" "MEDIUM" "No lifecycle rules (consider IA/Glacier & noncurrent cleanup)"
        fi
        
        if [[ "$S3_WARN_VER_BUT_NO_LC" == "1" && "$vs" == "Enabled" && "$has_lc" == "no" ]]; then
            emit "S3:VersioningNoLC" "$b" "$r" "WARN" "HIGH" "Versioning=Enabled but no lifecycle (noncurrent objects grow cost)"
        fi
    done
}

check_ebs_storage_cost() {
    local region="$1"
    log_info "檢查 EBS 儲存成本 (區域: $region)..."
    
    # EBS 磁碟區檢查
    local vols
    vols="$(aws_try "$region" aws ec2 describe-volumes --output json || true)"
    if [[ "$vols" == __ERROR__* || -z "$vols" ]]; then
        emit "EBS:DescribeVolumesError" "-" "$region" "INFO" "LOW" "${vols:0:200}"
    else
        # 未掛載磁碟區和 gp2 類型檢查
        echo "$vols" | jq -r '.Volumes[]? | [.VolumeId, .State, .VolumeType, (.Attachments|length)] | @tsv' \
        | while read -r vid vstate vtype att; do
            if [[ "$vstate" == "available" ]]; then
                emit "EBS:UnattachedVolume" "$vid" "$region" "WARN" "HIGH" "State=available Type=$vtype Attachments=$att"
            fi
            
            if [[ "$EBS_WARN_GP2" == "1" && "$vtype" == "gp2" ]]; then
                emit "EBS:gp2Storage" "$vid" "$region" "WARN" "LOW" "VolumeType=gp2 (consider gp3 to reduce $/GB & provision IOPS separately)"
            fi
        done
    fi
    
    # EBS 快照檢查
    local snaps
    snaps="$(aws_try "$region" aws ec2 describe-snapshots --owner-ids self --output json || true)"
    if [[ "$snaps" == __ERROR__* || -z "$snaps" ]]; then
        emit "EBS:DescribeSnapshotsError" "-" "$region" "INFO" "LOW" "${snaps:0:200}"
    else
        # 舊快照檢查
        printf '%s' "$snaps" \
        | jq -rc --argjson T "$EBS_SNAPSHOT_OLD_DAYS" '
            .Snapshots[]?
            | select(.StartTime!=null)
            | .ts = (.StartTime| sub("\\.[0-9]+\\+00:00$"; "Z")| sub("\\+00:00$"; "Z")| strptime("%Y-%m-%dT%H:%M:%SZ")| mktime)
            | .days = ((now - .ts)/86400 | floor)
            | select(.days>$T)
            | {id:.SnapshotId, vol:.VolumeId, days:.days, tier:(.StorageTier // "standard")}' \
        | while read -r row; do
            sid="$(printf '%s' "$row" | jq -r '.id')"
            vol="$(printf '%s' "$row" | jq -r '.vol')"
            days="$(printf '%s' "$row" | jq -r '.days')"
            tier="$(printf '%s' "$row" | jq -r '.tier')"
            
            # 根據儲存層級設定嚴重程度
            sev="LOW"
            msg="age_days=${days},tier=${tier}"
            [[ "$tier" == "standard" ]] && sev="MEDIUM"
            
            emit "EBS:OldSnapshot" "$sid($vol)" "$region" "WARN" "$sev" "$msg"
        done
    fi
}

check_efs_storage_cost() {
    local region="$1"
    log_info "檢查 EFS 儲存成本 (區域: $region)..."
    
    local fs
    fs="$(aws_try "$region" aws efs describe-file-systems --output json || true)"
    if [[ "$fs" == __ERROR__* || -z "$fs" ]]; then
        emit "EFS:DescribeFSError" "-" "$region" "INFO" "LOW" "${fs:0:200}"
        return
    fi
    
    echo "$fs" | jq -r '.FileSystems[]? | [.FileSystemId, .PerformanceMode, .ThroughputMode] | @tsv' \
    | while read -r fid perf tmode; do
        # 生命週期政策檢查
        local lc
        lc="$(aws efs describe-lifecycle-configuration --region "$region" --file-system-id "$fid" --output json 2>/dev/null || echo '{"LifecyclePolicies":[]}')"
        local lcount
        lcount="$(echo "$lc" | jq '.LifecyclePolicies|length')"
        
        if [[ "$EFS_REQUIRE_LIFECYCLE" == "1" && "$lcount" -eq 0 ]]; then
            emit "EFS:NoLifecycle" "$fid" "$region" "WARN" "MEDIUM" "No lifecycle policies (enable IA/Archive transitions to reduce cost)"
        else
            emit "EFS:Lifecycle" "$fid" "$region" "INFO" "LOW" "Policies=${lcount}"
        fi
        
        # 輸送量模式檢查
        if [[ "$tmode" == "provisioned" ]]; then
            emit "EFS:ThroughputMode" "$fid" "$region" "INFO" "LOW" "ThroughputMode=provisioned (verify needed level; consider Bursting if usage low)"
        else
            emit "EFS:ThroughputMode" "$fid" "$region" "INFO" "LOW" "ThroughputMode=$tmode"
        fi
    done
}

log_info "執行儲存成本檢查..."
check_s3_storage_cost
check_ebs_storage_cost "$REGION"
check_efs_storage_cost "$REGION"

# ========== 生成報告 ==========

log_info "生成成本優化檢查報告..."

# 統計結果
TOTAL_CHECKS=$(wc -l < "$DETAILED_OUTPUT_FILE" | tr -d ' ')
HIGH_COST_ISSUES=$(grep '"severity":"HIGH"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')
MEDIUM_COST_ISSUES=$(grep '"severity":"MEDIUM"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')
FAILED_CHECKS=$(grep '"status":"FAIL"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')
WARNING_CHECKS=$(grep '"status":"WARN"' "$DETAILED_OUTPUT_FILE" | wc -l | tr -d ' ')

# 計算潛在節省
UNATTACHED_VOLUMES=$(grep '"check":"EBS:Unused"' "$DETAILED_OUTPUT_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')
UNATTACHED_EIPS=$(grep '"check":"EIP:Unattached"' "$DETAILED_OUTPUT_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')

# 生成 JSON 報告
cat > "$OUTPUT_FILE" << EOF
{
  "pillar": "Cost Optimization",
  "account_id": "$ACCOUNT_ID",
  "region": "$REGION",
  "timestamp": "$TIMESTAMP",
  "summary": {
    "total_checks": $TOTAL_CHECKS,
    "high_cost_issues": $HIGH_COST_ISSUES,
    "medium_cost_issues": $MEDIUM_COST_ISSUES,
    "failed_checks": $FAILED_CHECKS,
    "warning_checks": $WARNING_CHECKS,
    "potential_savings": {
      "unattached_ebs_volumes": $UNATTACHED_VOLUMES,
      "unattached_elastic_ips": $UNATTACHED_EIPS
    }
  },
  "detailed_results_file": "cost-optimization_detailed_${TIMESTAMP}.jsonl",
  "key_findings": [
EOF

# 添加關鍵發現
if [[ $UNATTACHED_VOLUMES -gt 0 ]]; then
    echo '    "發現 '$UNATTACHED_VOLUMES' 個未附加的 EBS 磁碟區，可立即刪除節省成本",' >> "$OUTPUT_FILE"
fi
if [[ $UNATTACHED_EIPS -gt 0 ]]; then
    echo '    "發現 '$UNATTACHED_EIPS' 個未關聯的 Elastic IP，可釋放節省成本",' >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF
    "詳細檢查結果請參考 cost-optimization_detailed_${TIMESTAMP}.jsonl 文件"
  ],
  "recommendations": [
    "立即刪除未使用的 EBS 磁碟區",
    "釋放未關聯的 Elastic IP 地址",
    "將 EBS gp2 磁碟區遷移到 gp3 以節省成本",
    "為 S3 儲存桶設定生命週期政策",
    "檢查 CloudFront 價格等級設定",
    "為長期運行的 EC2 實例購買 Savings Plans 或 Reserved Instances",
    "考慮將適合的工作負載遷移到 Graviton 處理器",
    "為 CloudWatch Logs 設定適當的保留期限",
    "檢查 Lambda 預配置並發的必要性",
    "優化 Lambda 函數記憶體配置以降低成本",
    "檢查 Auto Scaling Group 是否過度佈署",
    "評估 EKS NodeGroup 的縮容機會",
    "將 RDS gp2 儲存遷移到 gp3 以節省成本",
    "為 RDS 啟用儲存自動擴展避免過度佈建",
    "檢查並調整 RDS 備份保留期",
    "定期清理 RDS 舊快照",
    "分析 RDS 實例使用率並調整大小",
    "評估 DynamoDB 計費模式 (On-Demand vs Provisioned)",
    "為 DynamoDB Provisioned 表啟用 Auto Scaling",
    "啟用 DynamoDB TTL 自動清理過期資料",
    "識別並處理閒置的 DynamoDB 表",
    "為 ECR 儲存庫設定生命週期政策",
    "檢查 Load Balancer 的目標群組使用情況",
    "評估 NAT Gateway 的使用模式和替代方案",
    "調整 CloudFront 價格等級以降低分發成本",
    "清理閒置的 Network Load Balancer",
    "為 VPC Endpoints 啟用私有 DNS 以減少 NAT 流量",
    "檢查 Transit Gateway 連接的必要性",
    "    "    "使用 VPC Endpoints 減少 NAT Gateway 流量成本",
    "為 CloudWatch Logs 設定適當的保留期限",
    "清理不必要的 CloudWatch Alarms",
    "優化 Kinesis Data Streams 的 Shard 配置",
    "檢查並清理非活躍的 Kinesis Streams",
    "    "縮短過長的日誌和資料保留期",
    "調整 CloudFront 價格等級以降低分發成本",
    "檢查 S3 跨區複寫的必要性",
    "優化 NLB Cross-Zone Load Balancing 配置",
    "評估 VPC Peering 和 Transit Gateway 的使用",
    "使用 VPC Endpoints 減少 NAT Gateway 資料傳輸成本",
    "監控跨 AZ 和跨區域的資料流量成本""",
    "為 S3 儲存桶設定生命週期規則以降低儲存成本",
    "清理 S3 版本控制儲存桶的舊版本物件",
    "刪除未掛載的 EBS 磁碟區",
    "將 EBS gp2 磁碟區遷移到 gp3",
    "設定 EBS 快照生命週期管理並清理舊快照",
    "為 EFS 檔案系統啟用 Intelligent-Tiering 或 IA 轉換",
    "檢查 EFS 輸送量模式是否需要 Provisioned""
  ]
}
EOF

log_success "Cost Optimization 檢查完成！"
log_info "總檢查項目: $TOTAL_CHECKS"
log_info "高成本問題: $HIGH_COST_ISSUES"
log_info "中成本問題: $MEDIUM_COST_ISSUES"
log_info "失敗檢查: $FAILED_CHECKS"
log_info "警告檢查: $WARNING_CHECKS"
log_info "未附加 EBS 磁碟區: $UNATTACHED_VOLUMES"
log_info "未關聯 Elastic IP: $UNATTACHED_EIPS"
log_info "詳細報告: $OUTPUT_FILE"
log_info "詳細結果: $DETAILED_OUTPUT_FILE"

if [[ $ENABLE_IDLE_METRICS == "0" ]]; then
    log_warning "EC2 閒置指標檢查已關閉，如需啟用請設定 ENABLE_IDLE_METRICS=1"
fi