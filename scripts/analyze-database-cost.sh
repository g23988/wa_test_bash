#!/bin/bash

# 資料庫成本分析工具
# 專注於 RDS 和 DynamoDB 的成本優化

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
    echo -e "${BLUE}[DB-COST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[DB-COST]${NC} $1"
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

log_info "分析資料庫成本優化結果: $DETAILED_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}🗄️  資料庫成本分析報告${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# RDS 分析
echo
echo -e "${BLUE}🗄️  RDS 資料庫分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# gp2 儲存類型
RDS_GP2_COUNT=$(grep '"check":"RDS:gp2"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $RDS_GP2_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}💾 使用 gp2 儲存的 RDS: $RDS_GP2_COUNT 個${NC}"
    echo "詳細列表:"
    grep '"check":"RDS:gp2"' "$DETAILED_FILE" | jq -r '"  🗄️  " + .resource + " (" + .region + ")"' | head -5
    [[ $RDS_GP2_COUNT -gt 5 ]] && echo "  ... 還有 $((RDS_GP2_COUNT - 5)) 個"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( RDS_GP2_COUNT * 15 )) USD/月 (遷移到 gp3)${NC}"
    echo
fi

# 儲存自動擴展未配置
RDS_NO_AS_COUNT=$(grep '"check":"RDS:StorageAutoscaling"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $RDS_NO_AS_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}⚙️  未配置儲存自動擴展的 RDS: $RDS_NO_AS_COUNT 個${NC}"
    echo "建議: 啟用儲存自動擴展以避免過度佈建"
    echo
fi

# 備份保留期過長
RDS_LONG_BACKUP_COUNT=$(grep '"check":"RDS:LongBackupRetention"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $RDS_LONG_BACKUP_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}📅 備份保留期過長的 RDS: $RDS_LONG_BACKUP_COUNT 個${NC}"
    grep '"check":"RDS:LongBackupRetention"' "$DETAILED_FILE" | jq -r '"  📅 " + .resource + " - " + .details' | head -3
    echo "建議: 檢查是否需要如此長的備份保留期"
    echo
fi

# 低 CPU 使用率
RDS_LOW_CPU_COUNT=$(grep '"check":"RDS:LowCPU"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $RDS_LOW_CPU_COUNT -gt 0 ]]; then
    echo -e "${RED}📉 低 CPU 使用率的 RDS: $RDS_LOW_CPU_COUNT 個${NC}"
    grep '"check":"RDS:LowCPU"' "$DETAILED_FILE" | jq -r '"  📉 " + .resource + " (" + .region + ") - " + .details' | head -3
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( RDS_LOW_CPU_COUNT * 100 )) USD/月 (調整實例大小)${NC}"
    echo
fi

# 舊快照
RDS_OLD_SNAP_COUNT=$(grep '"check":"RDS:OldSnapshot"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $RDS_OLD_SNAP_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}📸 舊快照: $RDS_OLD_SNAP_COUNT 個${NC}"
    echo "建議: 刪除不需要的舊快照以節省儲存成本"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( RDS_OLD_SNAP_COUNT * 8 )) USD/月${NC}"
    echo
fi

# Multi-AZ 成本提示
RDS_MULTIAZ_COUNT=$(grep '"check":"RDS:MultiAZCost"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $RDS_MULTIAZ_COUNT -gt 0 ]]; then
    echo -e "${CYAN}🔄 Multi-AZ 配置: $RDS_MULTIAZ_COUNT 個${NC}"
    echo "提示: Multi-AZ 會產生約 2 倍的實例和儲存成本"
    echo "建議: 確認是否真的需要高可用性"
    echo
fi

# DynamoDB 分析
echo
echo -e "${GREEN}📊 DynamoDB 表分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 無 Auto Scaling 的 Provisioned 表
DDB_NO_AS_COUNT=$(grep '"check":"DDB:NoAutoScaling"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $DDB_NO_AS_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}⚙️  Provisioned 模式但無 Auto Scaling: $DDB_NO_AS_COUNT 個表${NC}"
    grep '"check":"DDB:NoAutoScaling"' "$DETAILED_FILE" | jq -r '"  📊 " + .resource + " (" + .region + ")"' | head -5
    echo "建議: 啟用 Auto Scaling 或切換到 On-Demand 模式"
    echo
fi

# TTL 未啟用
DDB_NO_TTL_COUNT=$(grep '"check":"DDB:TTLDisabled"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $DDB_NO_TTL_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}⏰ TTL 未啟用: $DDB_NO_TTL_COUNT 個表${NC}"
    echo "建議: 啟用 TTL 自動刪除過期資料以控制儲存成本"
    echo
fi

# 閒置表
DDB_IDLE_COUNT=$(grep '"check":"DDB:Idle"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $DDB_IDLE_COUNT -gt 0 ]]; then
    echo -e "${RED}😴 閒置或低使用率表: $DDB_IDLE_COUNT 個${NC}"
    grep '"check":"DDB:Idle"' "$DETAILED_FILE" | jq -r '"  😴 " + .resource + " (" + .region + ") - " + .details' | head -3
    echo "建議: 考慮刪除未使用的表或切換到 On-Demand 模式"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( DDB_IDLE_COUNT * 25 )) USD/月${NC}"
    echo
fi

# 成本節省建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}💰 資料庫成本節省建議${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_db_savings=0

echo "立即行動項目:"
if [[ $RDS_OLD_SNAP_COUNT -gt 0 ]]; then
    snap_savings=$((RDS_OLD_SNAP_COUNT * 8))
    total_db_savings=$((total_db_savings + snap_savings))
    echo "  🗑️  刪除 $RDS_OLD_SNAP_COUNT 個舊 RDS 快照: ~\$${snap_savings} USD/月"
fi

if [[ $DDB_IDLE_COUNT -gt 0 ]]; then
    idle_savings=$((DDB_IDLE_COUNT * 25))
    total_db_savings=$((total_db_savings + idle_savings))
    echo "  🛑 處理 $DDB_IDLE_COUNT 個閒置 DynamoDB 表: ~\$${idle_savings} USD/月"
fi

echo
echo "短期優化 (1-2週):"
if [[ $RDS_GP2_COUNT -gt 0 ]]; then
    gp2_savings=$((RDS_GP2_COUNT * 15))
    total_db_savings=$((total_db_savings + gp2_savings))
    echo "  💾 將 $RDS_GP2_COUNT 個 RDS 遷移到 gp3: ~\$${gp2_savings} USD/月"
fi

if [[ $RDS_LOW_CPU_COUNT -gt 0 ]]; then
    cpu_savings=$((RDS_LOW_CPU_COUNT * 100))
    total_db_savings=$((total_db_savings + cpu_savings))
    echo "  📉 調整 $RDS_LOW_CPU_COUNT 個低使用率 RDS 實例: ~\$${cpu_savings} USD/月"
fi

echo
echo "中期優化 (1個月):"
if [[ $DDB_NO_AS_COUNT -gt 0 ]]; then
    as_savings=$((DDB_NO_AS_COUNT * 20))
    total_db_savings=$((total_db_savings + as_savings))
    echo "  ⚙️  優化 $DDB_NO_AS_COUNT 個 DynamoDB 表計費模式: ~\$${as_savings} USD/月"
fi

if [[ $RDS_LONG_BACKUP_COUNT -gt 0 ]]; then
    backup_savings=$((RDS_LONG_BACKUP_COUNT * 10))
    total_db_savings=$((total_db_savings + backup_savings))
    echo "  📅 調整 $RDS_LONG_BACKUP_COUNT 個 RDS 備份保留期: ~\$${backup_savings} USD/月"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}💵 資料庫預估總節省: ~\$${total_db_savings} USD/月${NC}"
echo -e "${CYAN}💵 年度節省: ~\$$((total_db_savings * 12)) USD${NC}"

# 最佳實務建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 資料庫成本最佳實務${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "RDS 最佳實務:"
echo "  ✅ 使用 gp3 儲存類型而非 gp2"
echo "  ✅ 啟用儲存自動擴展避免過度佈建"
echo "  ✅ 定期檢查實例大小是否合適"
echo "  ✅ 設定合理的備份保留期 (通常 7-30 天)"
echo "  ✅ 定期清理不需要的快照"
echo "  ✅ 考慮使用 Reserved Instances 降低長期成本"
echo

echo "DynamoDB 最佳實務:"
echo "  ✅ 根據使用模式選擇 On-Demand 或 Provisioned 模式"
echo "  ✅ 為 Provisioned 表啟用 Auto Scaling"
echo "  ✅ 啟用 TTL 自動清理過期資料"
echo "  ✅ 定期檢查表的使用情況"
echo "  ✅ 使用 DynamoDB Contributor Insights 分析熱點"
echo "  ✅ 考慮使用 DynamoDB On-Demand Backup"

# 實施計畫
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 資料庫成本優化實施計畫${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "第 1 週 - 清理和立即優化:"
echo "  ✅ 刪除不需要的 RDS 快照"
echo "  ✅ 識別並處理閒置的 DynamoDB 表"
echo "  ✅ 啟用 DynamoDB TTL"
echo

echo "第 2 週 - 儲存優化:"
echo "  ✅ 規劃 RDS gp2 到 gp3 遷移"
echo "  ✅ 啟用 RDS 儲存自動擴展"
echo

echo "第 3 週 - 實例和容量優化:"
echo "  ✅ 分析低使用率 RDS 實例並調整大小"
echo "  ✅ 優化 DynamoDB 計費模式"
echo

echo "第 4 週 - 監控和自動化:"
echo "  ✅ 設置資料庫成本警報"
echo "  ✅ 建立定期檢查和清理流程"
echo "  ✅ 評估 RDS Reserved Instances 機會"

log_success "資料庫成本分析完成"
echo "建議每月執行此分析以持續優化資料庫成本"