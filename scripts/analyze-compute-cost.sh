#!/bin/bash

# 計算資源成本分析工具
# 專注於 EC2、Lambda、EKS、ASG 等計算資源的成本優化

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
    echo -e "${BLUE}[COMPUTE-COST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[COMPUTE-COST]${NC} $1"
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
    log_info "文件不存在: $DETAILED_FILE"
    exit 1
fi

log_info "分析計算資源成本優化結果: $DETAILED_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}🖥️  計算資源成本分析報告${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# EC2 分析
echo
echo -e "${BLUE}🖥️  EC2 實例分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Savings Plan 候選
SP_CANDIDATES=$(grep '"check":"EC2:SavingsPlanCandidate"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $SP_CANDIDATES -gt 0 ]]; then
    echo -e "${YELLOW}💳 Savings Plan 候選實例: $SP_CANDIDATES 個${NC}"
    echo "詳細列表:"
    grep '"check":"EC2:SavingsPlanCandidate"' "$DETAILED_FILE" | jq -r '"  🖥️  " + .resource + " (" + .region + ") - " + .details' | head -10
    [[ $SP_CANDIDATES -gt 10 ]] && echo "  ... 還有 $((SP_CANDIDATES - 10)) 個"
    
    # 預估節省
    estimated_savings=$((SP_CANDIDATES * 100))  # 假設每個實例平均節省 $100/月
    echo -e "  ${GREEN}💰 預估節省: ~\$${estimated_savings} USD/月 (假設 30% 節省率)${NC}"
    echo
fi

# 實例類型統計
echo -e "${CYAN}📊 EC2 實例類型分佈:${NC}"
grep '"check":"EC2:TypeTally"' "$DETAILED_FILE" | jq -r '.resource + ": " + (.details | split("=")[1]) + " 個"' | sort -k2 -nr | head -10

# 閒置實例
IDLE_INSTANCES=$(grep '"check":"EC2:Idle"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $IDLE_INSTANCES -gt 0 ]]; then
    echo
    echo -e "${RED}😴 閒置實例: $IDLE_INSTANCES 個${NC}"
    echo "建議: 停止或調整這些低使用率實例"
fi

# Lambda 分析
echo
echo -e "${YELLOW}⚡ Lambda 函數分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 預配置並發
LAMBDA_PC=$(grep '"check":"Lambda:ProvisionedConcurrency"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $LAMBDA_PC -gt 0 ]]; then
    echo -e "${YELLOW}🔒 有預配置並發的函數: $LAMBDA_PC 個${NC}"
    grep '"check":"Lambda:ProvisionedConcurrency"' "$DETAILED_FILE" | jq -r '"  ⚡ " + .resource + " (" + .region + ")"' | head -5
    echo "  建議: 檢查是否真的需要預配置並發"
    echo
fi

# 記憶體過大
LAMBDA_MEM=$(grep '"check":"Lambda:OversizedMemory"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $LAMBDA_MEM -gt 0 ]]; then
    echo -e "${YELLOW}🧠 可能記憶體過大的函數: $LAMBDA_MEM 個${NC}"
    grep '"check":"Lambda:OversizedMemory"' "$DETAILED_FILE" | jq -r '"  🧠 " + .resource + " - " + .details' | head -5
    echo "  建議: 調整記憶體配置以優化成本"
    echo
fi

# Auto Scaling Group 分析
echo
echo -e "${GREEN}📈 Auto Scaling Group 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ASG_OVER=$(grep '"check":"ASG:OverProvision"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $ASG_OVER -gt 0 ]]; then
    echo -e "${YELLOW}📊 可能過度佈署的 ASG: $ASG_OVER 個${NC}"
    grep '"check":"ASG:OverProvision"' "$DETAILED_FILE" | jq -r '"  📈 " + .resource + " (" + .region + ") - " + .details' | head -5
    echo "  建議: 調整 Desired Capacity 和 Min Size 配置"
    echo
else
    echo -e "${GREEN}✅ 所有 ASG 配置看起來合理${NC}"
    echo
fi

# EKS 分析
echo
echo -e "${PURPLE}☸️  EKS 集群分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EKS_NG=$(grep '"check":"EKS:NodeGroupRightsize"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $EKS_NG -gt 0 ]]; then
    echo -e "${YELLOW}🔧 可縮容的 NodeGroup: $EKS_NG 個${NC}"
    grep '"check":"EKS:NodeGroupRightsize"' "$DETAILED_FILE" | jq -r '"  ☸️  " + .resource + " (" + .region + ") - " + .details' | head -5
    echo "  建議: 調整 NodeGroup 的 desired 和 min 配置"
    echo
else
    echo -e "${GREEN}✅ 所有 EKS NodeGroup 配置看起來合理${NC}"
    echo
fi

# 成本節省建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}💰 計算資源成本節省建議${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_compute_savings=0

echo "立即行動項目:"
if [[ $IDLE_INSTANCES -gt 0 ]]; then
    idle_savings=$((IDLE_INSTANCES * 50))
    total_compute_savings=$((total_compute_savings + idle_savings))
    echo "  🛑 停止 $IDLE_INSTANCES 個閒置實例: ~\$${idle_savings} USD/月"
fi

echo
echo "短期優化 (1-2週):"
if [[ $SP_CANDIDATES -gt 0 ]]; then
    sp_savings=$((SP_CANDIDATES * 30))
    total_compute_savings=$((total_compute_savings + sp_savings))
    echo "  💳 購買 Savings Plans: ~\$${sp_savings} USD/月 (30% 節省率)"
fi

if [[ $LAMBDA_MEM -gt 0 ]]; then
    lambda_savings=$((LAMBDA_MEM * 5))
    total_compute_savings=$((total_compute_savings + lambda_savings))
    echo "  🧠 優化 Lambda 記憶體: ~\$${lambda_savings} USD/月"
fi

echo
echo "中期優化 (1個月):"
if [[ $ASG_OVER -gt 0 ]]; then
    asg_savings=$((ASG_OVER * 40))
    total_compute_savings=$((total_compute_savings + asg_savings))
    echo "  📈 優化 ASG 配置: ~\$${asg_savings} USD/月"
fi

if [[ $EKS_NG -gt 0 ]]; then
    eks_savings=$((EKS_NG * 60))
    total_compute_savings=$((total_compute_savings + eks_savings))
    echo "  ☸️  優化 EKS NodeGroup: ~\$${eks_savings} USD/月"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}💵 計算資源預估總節省: ~\$${total_compute_savings} USD/月${NC}"
echo -e "${CYAN}💵 年度節省: ~\$$((total_compute_savings * 12)) USD${NC}"

# 實施計畫
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 計算資源優化實施計畫${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "第 1 週 - 立即行動:"
echo "  ✅ 識別並停止閒置的 EC2 實例"
echo "  ✅ 檢查 Lambda 函數的記憶體配置"
echo

echo "第 2 週 - Savings Plans:"
echo "  ✅ 分析長期運行實例的使用模式"
echo "  ✅ 購買適當的 1 年期 Savings Plans"
echo

echo "第 3 週 - 容器優化:"
echo "  ✅ 檢查 EKS NodeGroup 的資源使用率"
echo "  ✅ 調整 Auto Scaling Group 配置"
echo

echo "第 4 週 - 監控設置:"
echo "  ✅ 設置成本警報和預算"
echo "  ✅ 建立定期檢查流程"

log_success "計算資源成本分析完成"
echo "建議定期 (每月) 執行此分析以持續優化成本"