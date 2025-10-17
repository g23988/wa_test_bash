#!/bin/bash

# 資料傳輸成本分析工具
# 專注於 CloudFront、S3 跨區複寫、ELB Cross-Zone、VPC Peering、Transit Gateway 的資料傳輸成本優化

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
    echo -e "${BLUE}[DT-COST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[DT-COST]${NC} $1"
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

log_info "分析資料傳輸成本優化結果: $DETAILED_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}🔄 資料傳輸成本分析報告${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# CloudFront 分析
echo
echo -e "${CYAN}🌍 CloudFront 資料傳輸分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CF_COUNT=$(grep '"check":"DT:CloudFrontCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | head -1 || echo 0)
if [[ $CF_COUNT -gt 0 ]]; then
    echo -e "${BLUE}🌍 CloudFront 分發總數: $CF_COUNT 個${NC}"
    
    # 價格等級分析
    CF_PRICE_ALL=$(grep '"check":"DT:CloudFrontPriceClass"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $CF_PRICE_ALL -gt 0 ]]; then
        echo -e "${YELLOW}💸 使用 PriceClass_All 的分發: $CF_PRICE_ALL 個${NC}"
        grep '"check":"DT:CloudFrontPriceClass"' "$DETAILED_FILE" | grep '"status":"WARN"' | jq -r '"  🌍 " + .resource + " - " + .details' | head -5
        echo -e "  ${GREEN}💰 預估節省: ~\$$(( CF_PRICE_ALL * 60 )) USD/月 (切換到 PriceClass_200)${NC}"
        echo
    fi
    
    # Origin 類型分析
    CF_ORIGINS=$(grep '"check":"DT:CloudFrontOrigin"' "$DETAILED_FILE" | wc -l | tr -d ' ')
    if [[ $CF_ORIGINS -gt 0 ]]; then
        echo -e "${CYAN}📡 CloudFront Origins: $CF_ORIGINS 個${NC}"
        echo "Origin 類型分佈:"
        grep '"check":"DT:CloudFrontOrigin"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'OriginType=[^[:space:]]*' | sort | uniq -c | while read -r count type; do
            echo "  ${type/OriginType=/}: $count 個"
        done
        echo "  提示: AWS Origin (S3/ALB) 與 CloudFront 間無額外資料傳輸費"
        echo
    fi
else
    echo -e "${GREEN}✅ 未使用 CloudFront${NC}"
    echo
fi

# S3 跨區複寫分析
echo
echo -e "${BLUE}🪣 S3 跨區複寫分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

S3_CRR_COUNT=$(grep '"check":"DT:S3CRR"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $S3_CRR_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}🔄 啟用跨區複寫的 S3 儲存桶: $S3_CRR_COUNT 個${NC}"
    echo "跨區複寫詳情:"
    grep '"check":"DT:S3CRR"' "$DETAILED_FILE" | jq -r '"  🪣 " + .resource + " - " + .details' | head -10
    [[ $S3_CRR_COUNT -gt 10 ]] && echo "  ... 還有 $((S3_CRR_COUNT - 10)) 個"
    echo
    echo -e "${CYAN}💡 成本影響:${NC}"
    echo "  • 跨區資料傳輸費: \$0.02/GB (依區域而異)"
    echo "  • 目標區域儲存費用"
    echo "  • 複寫 API 請求費用"
    echo -e "  ${GREEN}💰 預估成本: ~\$$(( S3_CRR_COUNT * 50 )) USD/月 (假設每個儲存桶 100GB/月)${NC}"
    echo
else
    echo -e "${GREEN}✅ 未發現 S3 跨區複寫${NC}"
    echo
fi

# ELB Cross-Zone 分析
echo
echo -e "${GREEN}⚖️  ELB Cross-Zone 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ELB_CROSSZONE=$(grep '"check":"DT:ELBv2CrossZone"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $ELB_CROSSZONE -gt 0 ]]; then
    echo -e "${BLUE}⚖️  ELB 總數: $ELB_CROSSZONE 個${NC}"
    
    # Cross-Zone 啟用統計
    CZ_ENABLED=$(grep '"check":"DT:ELBv2CrossZone"' "$DETAILED_FILE" | grep 'cross_zone=true' | wc -l | tr -d ' ')
    CZ_DISABLED=$(grep '"check":"DT:ELBv2CrossZone"' "$DETAILED_FILE" | grep 'cross_zone=false' | wc -l | tr -d ' ')
    
    echo "Cross-Zone Load Balancing 狀態:"
    echo -e "  ${YELLOW}✅ 啟用: $CZ_ENABLED 個${NC}"
    echo -e "  ${GREEN}❌ 停用: $CZ_DISABLED 個${NC}"
    echo
    
    # NLB 跨 AZ 風險
    NLB_INTERAZ_RISK=$(grep '"check":"DT:NLBInterAZRisk"' "$DETAILED_FILE" | wc -l | tr -d ' ')
    if [[ $NLB_INTERAZ_RISK -gt 0 ]]; then
        echo -e "${RED}⚠️  NLB 跨 AZ 資料傳輸風險: $NLB_INTERAZ_RISK 個${NC}"
        grep '"check":"DT:NLBInterAZRisk"' "$DETAILED_FILE" | jq -r '"  ⚖️  " + .resource + " (" + .region + ") - " + .details' | head -5
        echo -e "  ${GREEN}💰 預估節省: ~\$$(( NLB_INTERAZ_RISK * 30 )) USD/月 (關閉 Cross-Zone 或調整架構)${NC}"
        echo
    fi
else
    echo -e "${GREEN}✅ 未發現 ELB${NC}"
    echo
fi

# VPC Peering 分析
echo
echo -e "${PURPLE}🔗 VPC Peering 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VPC_PEERING_COUNT=$(grep '"check":"DT:PeeringCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $VPC_PEERING_COUNT -gt 0 ]]; then
    echo -e "${BLUE}🔗 VPC Peering 連接總數: $VPC_PEERING_COUNT 個${NC}"
    
    echo "Peering 連接詳情:"
    grep '"check":"DT:Peering"' "$DETAILED_FILE" | jq -r '"  🔗 " + .resource + " (" + .region + ") - " + .details' | head -10
    
    echo
    echo -e "${CYAN}💡 成本影響:${NC}"
    echo "  • 同區域 VPC Peering: 免費"
    echo "  • 跨區域 VPC Peering: \$0.01/GB"
    echo "  • 跨 AZ 流量: \$0.01/GB (每個方向)"
    echo
else
    echo -e "${GREEN}✅ 未使用 VPC Peering${NC}"
    echo
fi

# Transit Gateway 分析
echo
echo -e "${CYAN}🚇 Transit Gateway 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TGW_COUNT=$(grep '"check":"DT:TGWCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $TGW_COUNT -gt 0 ]]; then
    echo -e "${BLUE}🚇 Transit Gateway 總數: $TGW_COUNT 個${NC}"
    
    echo "Transit Gateway 詳情:"
    grep '"check":"DT:TGW"' "$DETAILED_FILE" | jq -r '"  🚇 " + .resource + " (" + .region + ")"' | head -5
    
    echo
    echo -e "${CYAN}💡 成本影響:${NC}"
    echo "  • 每小時固定費用: \$0.05/小時"
    echo "  • 資料處理費用: \$0.02/GB"
    echo "  • 跨區域連接: 額外的跨區域資料傳輸費"
    echo -e "  ${GREEN}💰 預估成本: ~\$$(( TGW_COUNT * 36 )) USD/月 (固定費用)${NC}"
    echo
else
    echo -e "${GREEN}✅ 未使用 Transit Gateway${NC}"
    echo
fi

# NAT Gateway 分析
echo
echo -e "${YELLOW}🔀 NAT Gateway 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

NAT_COUNT=$(grep '"check":"DT:NATCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'active=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $NAT_COUNT -gt 0 ]]; then
    echo -e "${BLUE}🔀 活躍的 NAT Gateway: $NAT_COUNT 個${NC}"
    
    echo
    echo -e "${CYAN}💡 成本影響:${NC}"
    echo "  • 每小時固定費用: \$0.045/小時"
    echo "  • 資料處理費用: \$0.045/GB"
    echo -e "  ${GREEN}💰 預估成本: ~\$$(( NAT_COUNT * 32 )) USD/月 (固定費用)${NC}"
    echo "  建議: 使用 VPC Endpoints 減少 NAT Gateway 流量"
    echo
else
    echo -e "${GREEN}✅ 未使用 NAT Gateway${NC}"
    echo
fi

# VPC Endpoints 分析
echo
echo -e "${GREEN}🔗 VPC Endpoints 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VPCE_TOTAL=$(grep '"check":"DT:VPCECount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $VPCE_TOTAL -gt 0 ]]; then
    echo -e "${BLUE}🔗 VPC Endpoints 總數: $VPCE_TOTAL 個${NC}"
    
    # 類型統計
    INTERFACE_COUNT=$(grep '"check":"DT:VPCETypeCount"' "$DETAILED_FILE" | grep 'Interface' | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
    GATEWAY_COUNT=$(grep '"check":"DT:VPCETypeCount"' "$DETAILED_FILE" | grep 'Gateway' | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
    GWLB_COUNT=$(grep '"check":"DT:VPCETypeCount"' "$DETAILED_FILE" | grep 'GatewayLoadBalancer' | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
    
    echo "VPC Endpoints 類型分佈:"
    echo -e "  🔌 Interface Endpoints: $INTERFACE_COUNT 個"
    echo -e "  🚪 Gateway Endpoints: $GATEWAY_COUNT 個"
    echo -e "  ⚖️  Gateway Load Balancer Endpoints: $GWLB_COUNT 個"
    
    echo
    echo -e "${CYAN}💡 成本影響:${NC}"
    echo "  • Interface Endpoints: \$0.01/小時 + \$0.01/GB"
    echo "  • Gateway Endpoints: 免費 (S3, DynamoDB)"
    echo "  • Gateway Load Balancer Endpoints: \$0.0125/小時 + \$0.001/GB"
    
    if [[ $INTERFACE_COUNT -gt 0 ]]; then
        echo -e "  ${GREEN}💰 Interface Endpoints 成本: ~\$$(( INTERFACE_COUNT * 7 )) USD/月 (固定費用)${NC}"
    fi
    echo
else
    echo -e "${YELLOW}⚠️  未使用 VPC Endpoints${NC}"
    echo "  建議: 考慮使用 VPC Endpoints 減少 NAT Gateway 成本"
    echo
fi

# 資料傳輸成本節省建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}💰 資料傳輸成本節省建議${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_dt_savings=0

echo "立即行動項目:"
if [[ $CF_PRICE_ALL -gt 0 ]]; then
    cf_savings=$((CF_PRICE_ALL * 60))
    total_dt_savings=$((total_dt_savings + cf_savings))
    echo "  🌍 調整 $CF_PRICE_ALL 個 CloudFront 價格等級: ~\$${cf_savings} USD/月"
fi

if [[ $NLB_INTERAZ_RISK -gt 0 ]]; then
    nlb_savings=$((NLB_INTERAZ_RISK * 30))
    total_dt_savings=$((total_dt_savings + nlb_savings))
    echo "  ⚖️  優化 $NLB_INTERAZ_RISK 個 NLB Cross-Zone 配置: ~\$${nlb_savings} USD/月"
fi

echo
echo "短期優化 (1-2週):"
if [[ $S3_CRR_COUNT -gt 0 ]]; then
    echo "  🪣 檢查 $S3_CRR_COUNT 個 S3 跨區複寫的必要性"
fi

if [[ $VPCE_TOTAL -eq 0 && $NAT_COUNT -gt 0 ]]; then
    echo "  🔗 部署 VPC Endpoints 減少 NAT Gateway 流量"
fi

echo
echo "中期優化 (1個月):"
if [[ $TGW_COUNT -gt 0 ]]; then
    echo "  🚇 檢查 Transit Gateway 連接的必要性"
fi

if [[ $VPC_PEERING_COUNT -gt 0 ]]; then
    echo "  🔗 分析 VPC Peering 流量模式"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}💵 資料傳輸預估總節省: ~\$${total_dt_savings} USD/月${NC}"
echo -e "${CYAN}💵 年度節省: ~\$$((total_dt_savings * 12)) USD${NC}"

# 資料傳輸成本最佳實務
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 資料傳輸成本最佳實務${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "CloudFront 最佳實務:"
echo "  ✅ 根據用戶分佈選擇適當的價格等級"
echo "  ✅ 使用 AWS Origin 減少回源成本"
echo "  ✅ 優化快取策略減少回源流量"
echo "  ✅ 使用 CloudFront 函數處理邊緣邏輯"
echo

echo "S3 跨區複寫最佳實務:"
echo "  ✅ 評估跨區複寫的業務必要性"
echo "  ✅ 使用 S3 Intelligent-Tiering 降低儲存成本"
echo "  ✅ 考慮使用 S3 Transfer Acceleration"
echo "  ✅ 設定適當的複寫規則和篩選器"
echo

echo "網路架構最佳實務:"
echo "  ✅ 使用 VPC Endpoints 減少 NAT Gateway 流量"
echo "  ✅ 將相關資源部署在同一 AZ"
echo "  ✅ 謹慎使用 NLB Cross-Zone Load Balancing"
echo "  ✅ 評估 Transit Gateway vs VPC Peering 的成本效益"
echo "  ✅ 監控跨 AZ 和跨區域的資料流量"

# 實施計畫
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 資料傳輸成本優化實施計畫${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "第 1 週 - CloudFront 優化:"
echo "  ✅ 調整 CloudFront 價格等級"
echo "  ✅ 檢查 Origin 配置"
echo

echo "第 2 週 - Load Balancer 優化:"
echo "  ✅ 檢查 NLB Cross-Zone 設定"
echo "  ✅ 分析目標分佈和流量模式"
echo

echo "第 3 週 - VPC 網路優化:"
echo "  ✅ 部署必要的 VPC Endpoints"
echo "  ✅ 檢查 S3 跨區複寫需求"
echo

echo "第 4 週 - 監控和分析:"
echo "  ✅ 設置資料傳輸成本警報"
echo "  ✅ 分析流量模式和成本趨勢"
echo "  ✅ 建立定期檢查流程"

log_success "資料傳輸成本分析完成"
echo "建議每月執行此分析以持續優化資料傳輸成本"