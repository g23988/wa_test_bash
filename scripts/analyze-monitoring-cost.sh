#!/bin/bash

# 監控成本分析工具
# 專注於 CloudWatch Logs、CloudWatch Metrics/Alarms、Kinesis Data Streams 的成本優化

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
    echo -e "${BLUE}[MONITORING-COST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[MONITORING-COST]${NC} $1"
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

log_info "分析監控成本優化結果: $DETAILED_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}📊 監控成本分析報告${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# CloudWatch Logs 分析
echo
echo -e "${BLUE}📋 CloudWatch Logs 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 日誌群組總數
CW_LOG_GROUPS=$(grep '"check":"CW:LogGroupCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $CW_LOG_GROUPS -gt 0 ]]; then
    echo -e "${BLUE}📋 CloudWatch Logs 群組總數: $CW_LOG_GROUPS 個${NC}"
    echo
fi

# 無保留期的日誌群組
CW_NO_RETENTION=$(grep '"check":"CW:NoRetention"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $CW_NO_RETENTION -gt 0 ]]; then
    echo -e "${RED}⚠️  無保留期限的日誌群組: $CW_NO_RETENTION 個${NC}"
    echo "風險: 這些日誌群組會無限期儲存，造成持續增長的成本"
    grep '"check":"CW:NoRetention"' "$DETAILED_FILE" | jq -r '"  📋 " + .resource + " (" + .region + ")"' | head -10
    [[ $CW_NO_RETENTION -gt 10 ]] && echo "  ... 還有 $((CW_NO_RETENTION - 10)) 個"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( CW_NO_RETENTION * 15 )) USD/月 (設定 30 天保留期)${NC}"
    echo
fi

# 長保留期的日誌群組
CW_LONG_RETENTION=$(grep '"check":"CW:LongRetention"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $CW_LONG_RETENTION -gt 0 ]]; then
    echo -e "${YELLOW}📅 保留期過長的日誌群組: $CW_LONG_RETENTION 個${NC}"
    grep '"check":"CW:LongRetention"' "$DETAILED_FILE" | jq -r '"  📅 " + .resource + " (" + .region + ") - " + .details' | head -5
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( CW_LONG_RETENTION * 8 )) USD/月 (縮短保留期)${NC}"
    echo
fi

# 中等保留期的日誌群組
CW_MODERATE_RETENTION=$(grep '"check":"CW:ModerateRetention"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $CW_MODERATE_RETENTION -gt 0 ]]; then
    echo -e "${CYAN}📊 中等保留期的日誌群組: $CW_MODERATE_RETENTION 個${NC}"
    echo "  建議: 檢查是否可以進一步縮短保留期"
    echo
fi

# CloudWatch Metrics 和 Alarms 分析
echo
echo -e "${GREEN}📈 CloudWatch Metrics 和 Alarms 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Alarms 總數
CW_ALARMS_TOTAL=$(grep '"check":"CW:AlarmsCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $CW_ALARMS_TOTAL -gt 0 ]]; then
    echo -e "${BLUE}🚨 CloudWatch Alarms 總數: $CW_ALARMS_TOTAL 個${NC}"
    echo "  💰 成本: ~\$$(( CW_ALARMS_TOTAL * 1 )) USD/月 (每個 Alarm \$0.10/月)"
    echo
fi

# 過多 Alarms
CW_TOO_MANY_ALARMS=$(grep '"check":"CW:TooManyAlarms"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $CW_TOO_MANY_ALARMS -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Alarms 過多的區域: $CW_TOO_MANY_ALARMS 個${NC}"
    grep '"check":"CW:TooManyAlarms"' "$DETAILED_FILE" | jq -r '"  🚨 " + .region + " - " + .details'
    echo "  建議: 整合相似的 Alarms 或清理不必要的監控"
    echo
fi

# 資料不足的 Alarms
CW_INSUFFICIENT_DATA=$(grep '"check":"CW:InsufficientDataAlarm"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $CW_INSUFFICIENT_DATA -gt 0 ]]; then
    echo -e "${YELLOW}📊 資料不足的 Alarms: $CW_INSUFFICIENT_DATA 個${NC}"
    echo "  建議: 檢查這些 Alarms 是否仍然需要"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( CW_INSUFFICIENT_DATA / 10 )) USD/月 (清理不必要的 Alarms)${NC}"
    echo
fi

# Kinesis Data Streams 分析
echo
echo -e "${CYAN}🌊 Kinesis Data Streams 分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Streams 總數
KINESIS_STREAMS=$(grep '"check":"Kinesis:StreamCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | paste -sd+ | bc 2>/dev/null || echo 0)
if [[ $KINESIS_STREAMS -gt 0 ]]; then
    echo -e "${BLUE}🌊 Kinesis Streams 總數: $KINESIS_STREAMS 個${NC}"
    echo
fi

# 高 Shard 數量的 Provisioned Streams
KINESIS_HIGH_SHARDS=$(grep '"check":"Kinesis:ProvisionedHigh"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $KINESIS_HIGH_SHARDS -gt 0 ]]; then
    echo -e "${YELLOW}📊 高 Shard 數量的 Provisioned Streams: $KINESIS_HIGH_SHARDS 個${NC}"
    grep '"check":"Kinesis:ProvisionedHigh"' "$DETAILED_FILE" | jq -r '"  🌊 " + .resource + " (" + .region + ") - " + .details' | head -5
    echo "  建議: 考慮切換到 On-Demand 模式或調整 Shard 數量"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( KINESIS_HIGH_SHARDS * 50 )) USD/月${NC}"
    echo
fi

# 長保留期的 Streams
KINESIS_LONG_RETENTION=$(grep '"check":"Kinesis:LongRetention"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $KINESIS_LONG_RETENTION -gt 0 ]]; then
    echo -e "${YELLOW}📅 保留期過長的 Streams: $KINESIS_LONG_RETENTION 個${NC}"
    echo "  建議: 檢查是否需要如此長的資料保留期"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( KINESIS_LONG_RETENTION * 20 )) USD/月${NC}"
    echo
fi

# 非活躍的 Streams
KINESIS_INACTIVE=$(grep '"check":"Kinesis:InactiveStream"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $KINESIS_INACTIVE -gt 0 ]]; then
    echo -e "${RED}😴 非活躍的 Streams: $KINESIS_INACTIVE 個${NC}"
    grep '"check":"Kinesis:InactiveStream"' "$DETAILED_FILE" | jq -r '"  😴 " + .resource + " (" + .region + ") - " + .details'
    echo "  建議: 清理不再使用的 Streams"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( KINESIS_INACTIVE * 30 )) USD/月${NC}"
    echo
fi

# 監控成本節省建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}💰 監控成本節省建議${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_monitoring_savings=0

echo "立即行動項目:"
if [[ $CW_NO_RETENTION -gt 0 ]]; then
    cw_savings=$((CW_NO_RETENTION * 15))
    total_monitoring_savings=$((total_monitoring_savings + cw_savings))
    echo "  📋 為 $CW_NO_RETENTION 個日誌群組設定保留期: ~\$${cw_savings} USD/月"
fi

if [[ $KINESIS_INACTIVE -gt 0 ]]; then
    inactive_savings=$((KINESIS_INACTIVE * 30))
    total_monitoring_savings=$((total_monitoring_savings + inactive_savings))
    echo "  🗑️  刪除 $KINESIS_INACTIVE 個非活躍 Kinesis Streams: ~\$${inactive_savings} USD/月"
fi

echo
echo "短期優化 (1-2週):"
if [[ $CW_LONG_RETENTION -gt 0 ]]; then
    retention_savings=$((CW_LONG_RETENTION * 8))
    total_monitoring_savings=$((total_monitoring_savings + retention_savings))
    echo "  📅 調整 $CW_LONG_RETENTION 個日誌群組保留期: ~\$${retention_savings} USD/月"
fi

if [[ $KINESIS_HIGH_SHARDS -gt 0 ]]; then
    kinesis_savings=$((KINESIS_HIGH_SHARDS * 50))
    total_monitoring_savings=$((total_monitoring_savings + kinesis_savings))
    echo "  🌊 優化 $KINESIS_HIGH_SHARDS 個 Kinesis Streams: ~\$${kinesis_savings} USD/月"
fi

echo
echo "中期優化 (1個月):"
if [[ $CW_TOO_MANY_ALARMS -gt 0 ]]; then
    echo "  🚨 整合和清理過多的 CloudWatch Alarms"
fi

if [[ $KINESIS_LONG_RETENTION -gt 0 ]]; then
    retention_kinesis_savings=$((KINESIS_LONG_RETENTION * 20))
    total_monitoring_savings=$((total_monitoring_savings + retention_kinesis_savings))
    echo "  📅 調整 Kinesis 保留期: ~\$${retention_kinesis_savings} USD/月"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}💵 監控預估總節省: ~\$${total_monitoring_savings} USD/月${NC}"
echo -e "${CYAN}💵 年度節省: ~\$$((total_monitoring_savings * 12)) USD${NC}"

# 監控成本最佳實務
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 監控成本最佳實務${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "CloudWatch Logs 最佳實務:"
echo "  ✅ 為所有日誌群組設定適當的保留期 (通常 7-30 天)"
echo "  ✅ 使用 Log Insights 而非長期儲存進行分析"
echo "  ✅ 考慮將舊日誌匯出到 S3 以降低成本"
echo "  ✅ 使用日誌篩選器減少不必要的日誌"
echo "  ✅ 定期檢查日誌使用量和成本"
echo

echo "CloudWatch Metrics 和 Alarms 最佳實務:"
echo "  ✅ 整合相似的 Alarms 以減少數量"
echo "  ✅ 清理不再需要的 Alarms"
echo "  ✅ 使用複合 Alarms 減少個別 Alarms 數量"
echo "  ✅ 定期檢查 Alarms 的有效性"
echo "  ✅ 使用 CloudWatch Synthetics 進行應用程式監控"
echo

echo "Kinesis Data Streams 最佳實務:"
echo "  ✅ 根據流量模式選擇 Provisioned 或 On-Demand 模式"
echo "  ✅ 定期檢查 Shard 使用率並調整"
echo "  ✅ 設定適當的資料保留期 (預設 24 小時)"
echo "  ✅ 使用 Kinesis Analytics 進行即時分析"
echo "  ✅ 考慮使用 Kinesis Data Firehose 進行資料傳輸"
echo "  ✅ 監控 Shard 層級的指標"

# 實施計畫
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 監控成本優化實施計畫${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "第 1 週 - 日誌保留期優化:"
echo "  ✅ 識別無保留期限的日誌群組"
echo "  ✅ 為關鍵日誌設定 30 天保留期"
echo "  ✅ 為一般日誌設定 7-14 天保留期"
echo

echo "第 2 週 - Kinesis 優化:"
echo "  ✅ 檢查 Kinesis Streams 使用情況"
echo "  ✅ 清理非活躍的 Streams"
echo "  ✅ 調整 Shard 數量或切換到 On-Demand"
echo

echo "第 3 週 - CloudWatch Alarms 整理:"
echo "  ✅ 檢查並清理不必要的 Alarms"
echo "  ✅ 整合相似的監控項目"
echo "  ✅ 修復資料不足的 Alarms"
echo

echo "第 4 週 - 監控和自動化:"
echo "  ✅ 設置監控成本警報"
echo "  ✅ 建立定期檢查流程"
echo "  ✅ 實施自動化日誌管理"

log_success "監控成本分析完成"
echo "建議每月執行此分析以持續優化監控成本"