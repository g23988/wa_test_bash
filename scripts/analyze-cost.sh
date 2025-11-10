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

echo
log_success "成本優化分析完成"
echo "詳細結果請參考: $DETAILED_FILE"
