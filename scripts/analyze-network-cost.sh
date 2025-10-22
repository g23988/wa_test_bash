#!/bin/bash

# 網路成本分析工具
# 專注於 NAT Gateway、CloudFront、Transit Gateway、VPC Endpoints、NLB 的成本優化

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
    echo -e "${BLUE}[NET-COST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[NET-COST]${NC} $1"
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

log_info "分析網路成本優化結果: $DETAILED_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}🌐 網路成本分析報告${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# NAT Gateway 分析
echo
echo -e "${BLUE}🔀 NAT Gateway 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

NAT_COUNT=$(grep '"check":"NET:NATGatewayCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $NAT_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}🔀 NAT Gateway 總數: $NAT_COUNT 個${NC}"
    echo "成本組成:"
    echo "  💰 每小時固定費用: ~\$$(( NAT_COUNT * 24 * 30 )) USD/月 (假設 \$0.045/小時)"
    echo "  📊 資料處理費用: 依流量而定 (\$0.045/GB)"
    echo
    
    echo "詳細分佈:"
    grep '"check":"NET:NATGatewayDetail"' "$DETAILED_FILE" | jq -r '"  🔀 " + .resource + " (" + .region + ") - " + .details' | head -10
    
    echo
    echo -e "${CYAN}💡 優化建議:${NC}"
    echo "  • 考慮使用 VPC Endpoints 減少 NAT Gateway 流量"
    echo "  • 評估是否所有子網路都需要 NAT Gateway"
    echo "  • 考慮合併多個私有子網路使用單一 NAT Gateway"
    echo
else
    echo -e "${GREEN}✅ 未發現 NAT Gateway (或已優化)${NC}"
    echo
fi

# CloudFront 分析
echo
echo -e "${CYAN}🌍 CloudFront 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CF_COUNT=$(grep '"check":"NET:CloudFrontCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | head -1 || echo 0)
if [[ $CF_COUNT -gt 0 ]]; then
    echo -e "${BLUE}🌍 CloudFront 分發總數: $CF_COUNT 個${NC}"
    
    # 價格等級分析
    CF_PRICE_ALL=$(grep '"check":"NET:CloudFrontPriceClass"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $CF_PRICE_ALL -gt 0 ]]; then
        echo -e "${YELLOW}💸 使用 PriceClass_All 的分發: $CF_PRICE_ALL 個${NC}"
        grep '"check":"NET:CloudFrontPriceClass"' "$DETAILED_FILE" | grep '"status":"WARN"' | jq -r '"  🌍 " + .resource + " - " + .details' | head -5
        echo -e "  ${GREEN}💰 預估節省: ~\$$(( CF_PRICE_ALL * 50 )) USD/月 (切換到 PriceClass_200)${NC}"
        echo
    fi
    
    # HTTPS 重定向
    CF_REDIRECT=$(grep '"check":"NET:CloudFrontHTTPSRedirect"' "$DETAILED_FILE" | wc -l | tr -d ' ')
    if [[ $CF_REDIRECT -gt 0 ]]; then
        echo -e "${YELLOW}🔄 使用 HTTPS 重定向: $CF_REDIRECT 個分發${NC}"
        echo "  建議: 考慮使用 https-only 以減少重定向開銷"
        echo
    fi
else
    echo -e "${GREEN}✅ 未使用 CloudFront${NC}"
    echo
fi

# Transit Gateway 分析
echo
echo -e "${PURPLE}🚇 Transit Gateway 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TGW_COUNT=$(grep '"check":"NET:TransitGatewayCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $TGW_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}🚇 Transit Gateway 總數: $TGW_COUNT 個${NC}"
    echo "成本組成:"
    echo "  💰 每小時固定費用: ~\$$(( TGW_COUNT * 24 * 30 )) USD/月 (假設 \$0.05/小時)"
    echo "  📊 資料處理費用: \$0.02/GB"
    echo
    
    echo "詳細配置:"
    grep '"check":"NET:TransitGatewayDetail"' "$DETAILED_FILE" | jq -r '"  🚇 " + .resource + " (" + .region + ") - " + .details' | head -5
    echo
else
    echo -e "${GREEN}✅ 未使用 Transit Gateway${NC}"
    echo
fi

# VPC Endpoints 分析
echo
echo -e "${GREEN}🔗 VPC Endpoints 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VPCE_COUNT=$(grep '"check":"NET:VPCECount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $VPCE_COUNT -gt 0 ]]; then
    echo -e "${BLUE}🔗 VPC Endpoints 總數: $VPCE_COUNT 個${NC}"
    
    # Interface Endpoints
    INTERFACE_COUNT=$(grep '"check":"NET:VPCETypeCount"' "$DETAILED_FILE" | grep 'Interface' | jq -r '.details' | grep -o 'available=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
    if [[ $INTERFACE_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🔌 Interface Endpoints: $INTERFACE_COUNT 個${NC}"
        echo "  💰 預估成本: ~\$$(( INTERFACE_COUNT * 7 * 30 )) USD/月 (每個 \$0.01/小時)"
        
        # 私有 DNS 未啟用
        VPCE_NO_DNS=$(grep '"check":"NET:VPCEInterfacePrivateDNS"' "$DETAILED_FILE" | wc -l | tr -d ' ')
        if [[ $VPCE_NO_DNS -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠️  私有 DNS 未啟用: $VPCE_NO_DNS 個${NC}"
            echo "  建議: 啟用私有 DNS 以最大化 NAT Gateway 流量節省"
        fi
        echo
    fi
    
    # Gateway Endpoints
    GATEWAY_COUNT=$(grep '"check":"NET:VPCETypeCount"' "$DETAILED_FILE" | grep 'Gateway' | jq -r '.details' | grep -o 'available=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
    if [[ $GATEWAY_COUNT -gt 0 ]]; then
        echo -e "${GREEN}🚪 Gateway Endpoints: $GATEWAY_COUNT 個 (通常免費)${NC}"
        echo "  💰 節省: 減少 NAT Gateway 對 S3/DynamoDB 的流量成本"
        echo
    fi
else
    echo -e "${YELLOW}⚠️  未使用 VPC Endpoints${NC}"
    echo "  建議: 考慮使用 VPC Endpoints 減少 NAT Gateway 成本"
    echo
fi

# NLB 分析
echo
echo -e "${CYAN}⚖️  Network Load Balancer 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

NLB_IDLE=$(grep '"check":"NET:NLBIdle"' "$DETAILED_FILE" | wc -l | tr -d ' ')
NLB_ACTIVE=$(grep '"check":"NET:NLBDetail"' "$DETAILED_FILE" | wc -l | tr -d ' ')
NLB_TOTAL=$((NLB_IDLE + NLB_ACTIVE))

if [[ $NLB_TOTAL -gt 0 ]]; then
    echo -e "${BLUE}⚖️  NLB 總數: $NLB_TOTAL 個${NC}"
    echo -e "  ${GREEN}✅ 活躍: $NLB_ACTIVE 個${NC}"
    echo -e "  ${RED}😴 閒置: $NLB_IDLE 個${NC}"
    
    if [[ $NLB_IDLE -gt 0 ]]; then
        echo
        echo -e "${RED}閒置的 NLB:${NC}"
        grep '"check":"NET:NLBIdle"' "$DETAILED_FILE" | jq -r '"  ⚖️  " + .resource + " (" + .region + ") - " + .details' | head -5
        echo -e "  ${GREEN}💰 預估節省: ~\$$(( NLB_IDLE * 16 * 30 )) USD/月 (刪除閒置 NLB)${NC}"
        echo
    fi
else
    echo -e "${GREEN}✅ 未使用 NLB 或未發現問題${NC}"
    echo
fi

# 網路成本節省建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}💰 網路成本節省建議${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_network_savings=0

echo "立即行動項目:"
if [[ $NLB_IDLE -gt 0 ]]; then
    nlb_savings=$((NLB_IDLE * 16 * 30))
    total_network_savings=$((total_network_savings + nlb_savings))
    echo "  🗑️  刪除 $NLB_IDLE 個閒置 NLB: ~\$${nlb_savings} USD/月"
fi

echo
echo "短期優化 (1-2週):"
if [[ $CF_PRICE_ALL -gt 0 ]]; then
    cf_savings=$((CF_PRICE_ALL * 50))
    total_network_savings=$((total_network_savings + cf_savings))
    echo "  🌍 調整 $CF_PRICE_ALL 個 CloudFront 價格等級: ~\$${cf_savings} USD/月"
fi

if [[ $VPCE_NO_DNS -gt 0 ]]; then
    echo "  🔗 啟用 $VPCE_NO_DNS 個 VPC Endpoint 私有 DNS"
fi

echo
echo "中期優化 (1個月):"
if [[ $NAT_COUNT -gt 0 ]]; then
    echo "  🔀 評估 NAT Gateway 使用模式，考慮 VPC Endpoints 替代"
    echo "  📊 分析 NAT Gateway 流量，優化資料傳輸路徑"
fi

if [[ $TGW_COUNT -gt 0 ]]; then
    echo "  🚇 檢查 Transit Gateway 連接，移除不必要的連接"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}💵 網路預估總節省: ~\$${total_network_savings} USD/月${NC}"
echo -e "${CYAN}💵 年度節省: ~\$$((total_network_savings * 12)) USD${NC}"

# 網路成本最佳實務
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 網路成本最佳實務${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "NAT Gateway 優化:"
echo "  ✅ 使用 VPC Endpoints 減少對外流量"
echo "  ✅ 合併私有子網路共用 NAT Gateway"
echo "  ✅ 監控 NAT Gateway 流量模式"
echo "  ✅ 考慮使用 NAT Instance (小流量場景)"
echo

echo "CloudFront 優化:"
echo "  ✅ 根據用戶分佈選擇適當的價格等級"
echo "  ✅ 使用 https-only 而非 redirect-to-https"
echo "  ✅ 優化快取策略減少回源流量"
echo "  ✅ 使用 CloudFront 函數處理邊緣邏輯"
echo

echo "VPC Endpoints 優化:"
echo "  ✅ 為常用 AWS 服務建立 VPC Endpoints"
echo "  ✅ 啟用私有 DNS 解析"
echo "  ✅ 使用 Gateway Endpoints (S3, DynamoDB)"
echo "  ✅ 監控 Interface Endpoints 使用率"
echo

echo "Load Balancer 優化:"
echo "  ✅ 定期檢查並清理未使用的 Load Balancer"
echo "  ✅ 合併低流量的應用程式"
echo "  ✅ 使用適當的 Load Balancer 類型"

# 實施計畫
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 網路成本優化實施計畫${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "第 1 週 - 清理未使用資源:"
echo "  ✅ 刪除閒置的 Load Balancer"
echo "  ✅ 檢查並清理未使用的 Elastic IP"
echo

echo "第 2 週 - CloudFront 優化:"
echo "  ✅ 調整 CloudFront 價格等級"
echo "  ✅ 優化 HTTPS 配置"
echo

echo "第 3 週 - VPC Endpoints 部署:"
echo "  ✅ 為常用服務建立 VPC Endpoints"
echo "  ✅ 啟用私有 DNS 解析"
echo

echo "第 4 週 - 流量分析和監控:"
echo "  ✅ 分析 NAT Gateway 流量模式"
echo "  ✅ 設置網路成本警報"
echo "  ✅ 建立定期檢查流程"

log_success "網路成本分析完成"
echo "建議每月執行此分析以持續優化網路成本"