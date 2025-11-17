#!/bin/bash

# 成本優化檢查結果分析工具

set -uo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[ANALYZE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[ANALYZE]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ANALYZE]${NC} $1"
}

log_error() {
    echo -e "${RED}[ANALYZE]${NC} $1"
}

# 使用方式
usage() {
    echo "使用方式: $0 <cost-optimization_detailed_TIMESTAMP.jsonl>"
    echo "範例: $0 reports/cost-optimization_detailed_20241016_143022.jsonl"
    exit 1
}

# 檢查參數
if [[ $# -ne 1 ]]; then
    usage
fi

DETAILED_FILE="$1"

if [[ ! -f "$DETAILED_FILE" ]]; then
    log_error "文件不存在: $DETAILED_FILE"
    exit 1
fi

log_info "分析成本優化檢查結果: $DETAILED_FILE"

# 統計總覽
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}💰 成本優化檢查結果統計總覽${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 先嘗試標準方式計算行數
TOTAL=$(wc -l < "$DETAILED_FILE" | tr -d ' ')

# 初始化所有變數為 0
HIGH=0
MEDIUM=0
LOW=0
FAIL=0
WARN=0
OK=0
INFO=0

# 如果只有 0 或 1 行，可能所有 JSON 都在一行，使用 grep -o 計數
if [[ "$TOTAL" -le 1 ]]; then
    log_warning "檢測到 JSONL 格式異常，使用替代計數方式..."
    TOTAL=$(grep -o '{"timestamp"' "$DETAILED_FILE" | wc -l | tr -d ' ')
    HIGH=$( (grep -o '"severity":"HIGH"' "$DETAILED_FILE" || true) | wc -l | tr -d ' ')
    MEDIUM=$( (grep -o '"severity":"MEDIUM"' "$DETAILED_FILE" || true) | wc -l | tr -d ' ')
    LOW=$( (grep -o '"severity":"LOW"' "$DETAILED_FILE" || true) | wc -l | tr -d ' ')
    FAIL=$( (grep -o '"status":"FAIL"' "$DETAILED_FILE" || true) | wc -l | tr -d ' ')
    WARN=$( (grep -o '"status":"WARN"' "$DETAILED_FILE" || true) | wc -l | tr -d ' ')
    OK=$( (grep -o '"status":"OK"' "$DETAILED_FILE" || true) | wc -l | tr -d ' ')
    INFO=$( (grep -o '"status":"INFO"' "$DETAILED_FILE" || true) | wc -l | tr -d ' ')
else
    # 標準 JSONL 格式，每行一個 JSON
    HIGH=$( (grep '"severity":"HIGH"' "$DETAILED_FILE" 2>/dev/null || true) | wc -l | tr -d ' ')
    MEDIUM=$( (grep '"severity":"MEDIUM"' "$DETAILED_FILE" 2>/dev/null || true) | wc -l | tr -d ' ')
    LOW=$( (grep '"severity":"LOW"' "$DETAILED_FILE" 2>/dev/null || true) | wc -l | tr -d ' ')
    FAIL=$( (grep '"status":"FAIL"' "$DETAILED_FILE" 2>/dev/null || true) | wc -l | tr -d ' ')
    WARN=$( (grep '"status":"WARN"' "$DETAILED_FILE" 2>/dev/null || true) | wc -l | tr -d ' ')
    OK=$( (grep '"status":"OK"' "$DETAILED_FILE" 2>/dev/null || true) | wc -l | tr -d ' ')
    INFO=$( (grep '"status":"INFO"' "$DETAILED_FILE" 2>/dev/null || true) | wc -l | tr -d ' ')
fi

# 確保所有變數都有值
TOTAL=${TOTAL:-0}
HIGH=${HIGH:-0}
MEDIUM=${MEDIUM:-0}
LOW=${LOW:-0}
FAIL=${FAIL:-0}
WARN=${WARN:-0}
OK=${OK:-0}
INFO=${INFO:-0}

echo "總檢查項目: $TOTAL"
echo
echo "按成本影響分類:"
echo -e "  ${RED}高成本影響 (HIGH): $HIGH${NC}"
echo -e "  ${YELLOW}中成本影響 (MEDIUM): $MEDIUM${NC}"
echo -e "  ${GREEN}低成本影響 (LOW): $LOW${NC}"
echo
echo "按狀態分類:"
echo -e "  ${RED}需要處理 (FAIL): $FAIL${NC}"
echo -e "  ${YELLOW}建議優化 (WARN): $WARN${NC}"
echo -e "  ${GREEN}狀態良好 (OK): $OK${NC}"
echo -e "  ${BLUE}資訊參考 (INFO): $INFO${NC}"

# 立即節省機會
if [[ $FAIL -gt 0 ]]; then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${RED}💸 立即節省機會 (可立即處理)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 先將文件轉換為正確的 JSONL 格式
    temp_file=$(mktemp)
    sed 's/}{/}\n{/g' "$DETAILED_FILE" > "$temp_file"
    
    sed 's/}{/}\n{/g' "$DETAILED_FILE" | grep '"status":"FAIL"' | jq -r '"  ❌ " + .check + ": " + .resource + " (" + .region + ") - " + .details' 2>/dev/null
    
    rm -f "$temp_file"
fi

# 優化建議
if [[ $WARN -gt 0 ]]; then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}⚡ 成本優化建議${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    sed 's/}{/}\n{/g' "$DETAILED_FILE" | grep '"status":"WARN"' | jq -r '"  ⚠️  " + .check + ": " + .resource + " (" + .region + ") - " + .details' 2>/dev/null
fi

# 按檢查類型分組統計
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}📊 按檢查類型分組統計${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 先將文件轉換為正確的 JSONL 格式
temp_file=$(mktemp)
sed 's/}{/}\n{/g' "$DETAILED_FILE" > "$temp_file"

jq -r '.check' "$temp_file" 2>/dev/null | sort | uniq -c | sort -nr | while read -r count check; do
    fail_count=$( (grep "\"check\":\"$check\"" "$temp_file" | grep '"status":"FAIL"' || true) | wc -l | tr -d ' ')
    warn_count=$( (grep "\"check\":\"$check\"" "$temp_file" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    
    status_info=""
    [[ $fail_count -gt 0 ]] && status_info="${status_info}${RED}需處理:$fail_count${NC} "
    [[ $warn_count -gt 0 ]] && status_info="${status_info}${YELLOW}可優化:$warn_count${NC} "
    
    echo -e "  $check: $count 項檢查 $status_info"
done

rm -f "$temp_file"

# 按區域分組統計
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}🌍 按區域分組統計${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 先將文件轉換為正確的 JSONL 格式
temp_file=$(mktemp)
sed 's/}{/}\n{/g' "$DETAILED_FILE" > "$temp_file"

jq -r '.region' "$temp_file" 2>/dev/null | sort | uniq -c | sort -nr | while read -r count region; do
    fail_count=$( (grep "\"region\":\"$region\"" "$temp_file" | grep '"status":"FAIL"' || true) | wc -l | tr -d ' ')
    warn_count=$( (grep "\"region\":\"$region\"" "$temp_file" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    
    status_info=""
    [[ $fail_count -gt 0 ]] && status_info="${status_info}${RED}需處理:$fail_count${NC} "
    [[ $warn_count -gt 0 ]] && status_info="${status_info}${YELLOW}可優化:$warn_count${NC} "
    
    echo -e "  $region: $count 項檢查 $status_info"
done

rm -f "$temp_file"

# 建議優先處理順序
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 建議優先處理順序${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "1. 🔴 立即處理 - 直接成本浪費 (FAIL)"
echo "2. 🟠 短期優化 - 顯著節省 (HIGH + WARN)"
echo "3. 🟡 中期優化 - 持續節省 (MEDIUM + WARN)"
echo "4. 🟢 長期優化 - 架構改進 (LOW + INFO)"

# 生成主要優化建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}🔧 主要優化建議${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 檢查常見問題並給出建議
if grep -q '"check":"EBS:Unused"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"EBS:Unused"' "$DETAILED_FILE" | grep '"status":"FAIL"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 💾 刪除 $count 個未使用的 EBS 磁碟區"
fi

if grep -q '"check":"EIP:Unattached"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"EIP:Unattached"' "$DETAILED_FILE" | grep '"status":"FAIL"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 🌐 釋放 $count 個未關聯的 Elastic IP"
fi

if grep -q '"check":"EBS:gp2"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"EBS:gp2"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 📀 將 $count 個 EBS gp2 磁碟區遷移到 gp3 (節省 20%)"
fi

if grep -q '"check":"EC2:SavingsPlanCandidate"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"EC2:SavingsPlanCandidate"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 💳 為 $count 個長期運行實例購買 Savings Plans (節省高達 72%)"
fi

if grep -q '"check":"EC2:SpotOpportunity"' "$DETAILED_FILE" 2>/dev/null; then
    echo "• 🎯 評估 Spot Instance 使用機會 (節省高達 90%)"
fi

if grep -q '"check":"S3:Lifecycle"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"S3:Lifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 🪣 為 $count 個 S3 儲存桶設定生命週期政策 (節省 30-80%)"
fi

if grep -q '"check":"EBS:OldSnapshot"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"EBS:OldSnapshot"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 📸 清理 $count 個 EBS 舊快照"
fi

if grep -q '"check":"RDS:OldSnapshot"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"RDS:OldSnapshot"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 📸 清理 $count 個 RDS 舊快照"
fi

if grep -q '"check":"Lambda:OversizedMemory"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"Lambda:OversizedMemory"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 🧠 優化 $count 個 Lambda 函數記憶體配置 (節省 10-30%)"
fi

if grep -q '"check":"RDS:LowCPU"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"RDS:LowCPU"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 🗄️  調整 $count 個 RDS 實例大小 (節省 30-50%)"
fi

if grep -q '"check":"ASG:OverProvision"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"ASG:OverProvision"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 📈 優化 $count 個 Auto Scaling Group 配置 (節省 15-25%)"
fi

if grep -q '"check":"EKS:NodeGroupRightsize"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"EKS:NodeGroupRightsize"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• ☸️  調整 $count 個 EKS NodeGroup 大小 (節省 20-40%)"
fi

if grep -q '"check":"CWLogs:Retention"' "$DETAILED_FILE" 2>/dev/null || grep -q '"check":"CW:NoRetention"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( ( (grep '"check":"CWLogs:Retention"' "$DETAILED_FILE" || true) | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    count2=$( ( (grep '"check":"CW:NoRetention"' "$DETAILED_FILE" || true) | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    total=$((count + count2))
    [[ $total -gt 0 ]] && echo "• 📊 設定 $total 個 CloudWatch Logs 保留政策"
fi

if grep -q '"check":"DDB:Idle"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"DDB:Idle"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 📊 優化 $count 個閒置 DynamoDB 表"
fi

if grep -q '"check":"NET:CloudFrontPriceClass"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"NET:CloudFrontPriceClass"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 🌍 調整 $count 個 CloudFront 價格等級 (節省 20-50%)"
fi

if grep -q '"check":"EFS:NoLifecycle"' "$DETAILED_FILE" 2>/dev/null; then
    count=$( (grep '"check":"EFS:NoLifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
    [[ $count -gt 0 ]] && echo "• 📁 為 $count 個 EFS 檔案系統啟用生命週期政策 (節省 85%)"
fi

# 預估成本節省計算
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}💰 預估成本節省計算${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_monthly_savings=0

# 未使用的 EBS 磁碟區 (假設平均 100GB gp3 @ $0.08/GB/月)
ebs_unused_count=$( (grep '"check":"EBS:Unused"' "$DETAILED_FILE" | grep '"status":"FAIL"' || true) | wc -l | tr -d ' ')
if [[ $ebs_unused_count -gt 0 ]]; then
    ebs_savings=$((ebs_unused_count * 8))
    total_monthly_savings=$((total_monthly_savings + ebs_savings))
    echo "💾 刪除 $ebs_unused_count 個未使用 EBS 磁碟區: ~\$$ebs_savings USD/月"
fi

# 未關聯的 Elastic IP ($0.005/小時 = ~$3.6/月)
eip_unused_count=$( (grep '"check":"EIP:Unattached"' "$DETAILED_FILE" | grep '"status":"FAIL"' || true) | wc -l | tr -d ' ')
if [[ $eip_unused_count -gt 0 ]]; then
    eip_savings=$((eip_unused_count * 4))
    total_monthly_savings=$((total_monthly_savings + eip_savings))
    echo "🌐 釋放 $eip_unused_count 個未關聯 Elastic IP: ~\$$eip_savings USD/月"
fi

# gp2 到 gp3 遷移 (節省約 20%)
gp2_count=$( (grep '"check":"EBS:gp2"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $gp2_count -gt 0 ]]; then
    gp2_savings=$((gp2_count * 2))
    total_monthly_savings=$((total_monthly_savings + gp2_savings))
    echo "📀 EBS gp2→gp3 遷移 ($gp2_count 個磁碟區): ~\$$gp2_savings USD/月"
fi

# EBS 舊快照 (假設平均 50GB @ $0.05/GB/月)
ebs_snap_count=$( (grep '"check":"EBS:OldSnapshot"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $ebs_snap_count -gt 0 ]]; then
    ebs_snap_savings=$((ebs_snap_count * 3))
    total_monthly_savings=$((total_monthly_savings + ebs_snap_savings))
    echo "📸 清理 $ebs_snap_count 個 EBS 舊快照: ~\$$ebs_snap_savings USD/月"
fi

# RDS 舊快照 (假設平均 100GB @ $0.095/GB/月)
rds_snap_count=$( (grep '"check":"RDS:OldSnapshot"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $rds_snap_count -gt 0 ]]; then
    rds_snap_savings=$((rds_snap_count * 10))
    total_monthly_savings=$((total_monthly_savings + rds_snap_savings))
    echo "📸 清理 $rds_snap_count 個 RDS 舊快照: ~\$$rds_snap_savings USD/月"
fi

# S3 生命週期政策 (假設平均節省 50%)
s3_lc_count=$( (grep '"check":"S3:Lifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $s3_lc_count -gt 0 ]]; then
    s3_lc_savings=$((s3_lc_count * 50))
    total_monthly_savings=$((total_monthly_savings + s3_lc_savings))
    echo "🪣 S3 生命週期政策 ($s3_lc_count 個儲存桶): ~\$$s3_lc_savings USD/月"
fi

# Lambda 記憶體優化 (假設平均節省 20%)
lambda_mem_count=$( (grep '"check":"Lambda:OversizedMemory"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $lambda_mem_count -gt 0 ]]; then
    lambda_savings=$((lambda_mem_count * 5))
    total_monthly_savings=$((total_monthly_savings + lambda_savings))
    echo "🧠 Lambda 記憶體優化 ($lambda_mem_count 個函數): ~\$$lambda_savings USD/月"
fi

# RDS 實例調整 (假設平均節省 40%)
rds_cpu_count=$( (grep '"check":"RDS:LowCPU"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $rds_cpu_count -gt 0 ]]; then
    rds_savings=$((rds_cpu_count * 100))
    total_monthly_savings=$((total_monthly_savings + rds_savings))
    echo "🗄️  RDS 實例調整 ($rds_cpu_count 個實例): ~\$$rds_savings USD/月"
fi

# ASG 優化 (假設平均節省 20%)
asg_count=$( (grep '"check":"ASG:OverProvision"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $asg_count -gt 0 ]]; then
    asg_savings=$((asg_count * 50))
    total_monthly_savings=$((total_monthly_savings + asg_savings))
    echo "📈 ASG 配置優化 ($asg_count 個群組): ~\$$asg_savings USD/月"
fi

# EKS NodeGroup 調整 (假設平均節省 30%)
eks_count=$( (grep '"check":"EKS:NodeGroupRightsize"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $eks_count -gt 0 ]]; then
    eks_savings=$((eks_count * 80))
    total_monthly_savings=$((total_monthly_savings + eks_savings))
    echo "☸️  EKS NodeGroup 調整 ($eks_count 個群組): ~\$$eks_savings USD/月"
fi

# CloudWatch Logs 保留政策
cw_logs_count=$( ( (grep '"check":"CWLogs:Retention"' "$DETAILED_FILE" || true) | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
cw_logs_count2=$( ( (grep '"check":"CW:NoRetention"' "$DETAILED_FILE" || true) | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
cw_logs_total=$((cw_logs_count + cw_logs_count2))
if [[ $cw_logs_total -gt 0 ]]; then
    cw_savings=$((cw_logs_total * 10))
    total_monthly_savings=$((total_monthly_savings + cw_savings))
    echo "📊 CloudWatch Logs 保留政策 ($cw_logs_total 個日誌群組): ~\$$cw_savings USD/月"
fi

# DynamoDB 優化
ddb_count=$( (grep '"check":"DDB:Idle"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $ddb_count -gt 0 ]]; then
    ddb_savings=$((ddb_count * 20))
    total_monthly_savings=$((total_monthly_savings + ddb_savings))
    echo "📊 DynamoDB 優化 ($ddb_count 個表): ~\$$ddb_savings USD/月"
fi

# CloudFront 價格等級
cf_count=$( (grep '"check":"NET:CloudFrontPriceClass"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $cf_count -gt 0 ]]; then
    cf_savings=$((cf_count * 30))
    total_monthly_savings=$((total_monthly_savings + cf_savings))
    echo "🌍 CloudFront 價格等級 ($cf_count 個分發): ~\$$cf_savings USD/月"
fi

# EFS 生命週期政策 (節省 85%)
efs_count=$( (grep '"check":"EFS:NoLifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $efs_count -gt 0 ]]; then
    efs_savings=$((efs_count * 40))
    total_monthly_savings=$((total_monthly_savings + efs_savings))
    echo "📁 EFS 生命週期政策 ($efs_count 個檔案系統): ~\$$efs_savings USD/月"
fi

# NLB 閒置
nlb_idle_count=$( (grep '"check":"NET:NLBIdle"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $nlb_idle_count -gt 0 ]]; then
    nlb_savings=$((nlb_idle_count * 25))
    total_monthly_savings=$((total_monthly_savings + nlb_savings))
    echo "⚖️  閒置 NLB 清理 ($nlb_idle_count 個): ~\$$nlb_savings USD/月"
fi

# Kinesis 優化
kinesis_count=$( (grep '"check":"Kinesis:ProvisionedHigh"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $kinesis_count -gt 0 ]]; then
    kinesis_savings=$((kinesis_count * 40))
    total_monthly_savings=$((total_monthly_savings + kinesis_savings))
    echo "🌊 Kinesis 配置優化 ($kinesis_count 個串流): ~\$$kinesis_savings USD/月"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}💵 預估總節省 (立即可實現):${NC}"
echo -e "${GREEN}   每月: ~\$$total_monthly_savings USD${NC}"
echo -e "${GREEN}   每年: ~\$$((total_monthly_savings * 12)) USD${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Savings Plans 額外節省 (需要承諾)
sp_count=$( (grep '"check":"EC2:SavingsPlanCandidate"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $sp_count -gt 0 ]]; then
    echo
    echo -e "${YELLOW}📈 額外節省機會 (需要承諾):${NC}"
    echo "   💳 Savings Plans ($sp_count 個實例):"
    echo "      - 1 年期: 可額外節省高達 42% EC2 成本"
    echo "      - 3 年期: 可額外節省高達 72% EC2 成本"
    
    # 估算 Savings Plans 潛在節省
    # 假設平均每個實例 $100/月，節省 50%
    sp_potential=$((sp_count * 50))
    echo "      - 預估額外節省: ~\$$sp_potential USD/月 (假設 50% 平均節省)"
fi

# Spot Instance 機會
spot_opp=$( (grep '"check":"EC2:SpotOpportunity"' "$DETAILED_FILE" | grep '"status":"WARN"' || true) | wc -l | tr -d ' ')
if [[ $spot_opp -gt 0 ]]; then
    echo
    echo "   🎯 Spot Instance 機會:"
    echo "      - 適用於容錯工作負載"
    echo "      - 可節省高達 90% EC2 成本"
fi

echo
log_success "成本優化分析完成"
echo "詳細結果請參考: $DETAILED_FILE"
echo
echo -e "${CYAN}💡 提示:${NC} 以上節省估算基於行業平均值，實際節省可能因資源大小和使用模式而異"
