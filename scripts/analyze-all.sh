#!/bin/bash

# AWS Well-Architected 綜合分析工具
# 分析安全性和成本優化的詳細結果

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[WA-ANALYZE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[WA-ANALYZE]${NC} $1"
}

# 使用方式
usage() {
    echo "使用方式: $0 <timestamp>"
    echo "範例: $0 20241016_143022"
    echo "或者: $0 reports/security_detailed_20241016_143022.jsonl reports/cost-optimization_detailed_20241016_143022.jsonl"
    exit 1
}

# 檢查參數
if [[ $# -eq 1 ]]; then
    TIMESTAMP="$1"
    SECURITY_FILE="reports/security_detailed_${TIMESTAMP}.jsonl"
    COST_FILE="reports/cost-optimization_detailed_${TIMESTAMP}.jsonl"
elif [[ $# -eq 2 ]]; then
    SECURITY_FILE="$1"
    COST_FILE="$2"
else
    usage
fi

# 檢查文件存在
for file in "$SECURITY_FILE" "$COST_FILE"; do
    if [[ ! -f "$file" ]]; then
        log_info "文件不存在: $file，跳過該部分分析"
    fi
done

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}🏗️  AWS Well-Architected 綜合分析報告${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 安全性分析
if [[ -f "$SECURITY_FILE" ]]; then
    echo
    echo -e "${RED}🔒 安全性分析摘要${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    SEC_TOTAL=$(wc -l < "$SECURITY_FILE" | tr -d ' ')
    SEC_CRITICAL=$(grep '"severity":"CRITICAL"' "$SECURITY_FILE" | wc -l | tr -d ' ')
    SEC_HIGH=$(grep '"severity":"HIGH"' "$SECURITY_FILE" | wc -l | tr -d ' ')
    SEC_FAIL=$(grep '"status":"FAIL"' "$SECURITY_FILE" | wc -l | tr -d ' ')
    
    echo "🔍 安全檢查總數: $SEC_TOTAL"
    echo -e "🚨 嚴重安全問題: ${RED}$SEC_CRITICAL${NC}"
    echo -e "⚠️  高風險問題: ${YELLOW}$SEC_HIGH${NC}"
    echo -e "❌ 失敗檢查: ${RED}$SEC_FAIL${NC}"
    
    if [[ $SEC_CRITICAL -gt 0 ]]; then
        echo
        echo -e "${RED}🚨 需要立即處理的嚴重安全問題:${NC}"
        grep '"severity":"CRITICAL"' "$SECURITY_FILE" | jq -r '"  ❌ " + .check + ": " + .resource + " - " + .details' | head -3
    fi
fi

# 成本優化分析  
if [[ -f "$COST_FILE" ]]; then
    echo
    echo -e "${GREEN}💰 成本優化分析摘要${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    COST_TOTAL=$(wc -l < "$COST_FILE" | tr -d ' ')
    COST_FAIL=$(grep '"status":"FAIL"' "$COST_FILE" | wc -l | tr -d ' ')
    COST_WARN=$(grep '"status":"WARN"' "$COST_FILE" | wc -l | tr -d ' ')
    
    EBS_UNUSED=$(grep '"check":"EBS:Unused"' "$COST_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')
    EIP_UNUSED=$(grep '"check":"EIP:Unattached"' "$COST_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')
    
    echo "💸 成本檢查總數: $COST_TOTAL"
    echo -e "🔴 立即節省機會: ${RED}$COST_FAIL${NC}"
    echo -e "🟡 優化建議: ${YELLOW}$COST_WARN${NC}"
    
    if [[ $COST_FAIL -gt 0 ]]; then
        savings=$((EBS_UNUSED * 10 + EIP_UNUSED * 4))
        echo -e "💵 預估月節省: ${GREEN}\$${savings} USD${NC}"
    fi
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}🎯 綜合建議與行動計畫${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "優先級 1 - 立即處理 (24小時內):"
if [[ -f "$SECURITY_FILE" && $SEC_CRITICAL -gt 0 ]]; then
    echo "  🚨 處理所有嚴重安全問題"
fi
if [[ -f "$COST_FILE" && $EBS_UNUSED -gt 0 ]]; then
    echo "  💾 刪除 $EBS_UNUSED 個未使用的 EBS 磁碟區"
fi
if [[ -f "$COST_FILE" && $EIP_UNUSED -gt 0 ]]; then
    echo "  🌐 釋放 $EIP_UNUSED 個未關聯的 Elastic IP"
fi

echo
echo "優先級 2 - 本週內處理:"
if [[ -f "$SECURITY_FILE" && $SEC_FAIL -gt 0 ]]; then
    echo "  🔒 修復安全檢查失敗項目"
fi
echo "  📀 規劃 EBS gp2 到 gp3 遷移"
echo "  🪣 設定 S3 生命週期政策"

echo
echo "優先級 3 - 本月內處理:"
echo "  💳 評估 Savings Plans 購買"
echo "  🗄️  優化資料庫配置和成本"
echo "  🏗️  架構優化和最佳實務實施"

log_success "綜合分析完成"
echo "詳細分析請使用:"
echo "  ./scripts/analyze-security.sh $SECURITY_FILE"
echo "  ./scripts/analyze-cost.sh $COST_FILE"
echo "  ./scripts/analyze-compute-cost.sh $COST_FILE"
echo "  ./scripts/analyze-database-cost.sh $COST_FILE"
echo "  ./scripts/analyze-network-cost.sh $COST_FILE"
echo "  ./scripts/analyze-monitoring-cost.sh $COST_FILE"
echo "  ./scripts/analyze-datatransfer-cost.sh $COST_FILE"
echo "  ./scripts/analyze-storage-cost.sh $COST_FILE"