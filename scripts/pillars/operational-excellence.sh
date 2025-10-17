#!/bin/bash

# Operational Excellence Pillar 檢查
# 營運卓越支柱

ACCOUNT_ID=$1
REGION=$2
TIMESTAMP=$3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
REPORTS_DIR="$PROJECT_ROOT/reports"

# 顏色定義
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[OPS-EXCELLENCE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OPS-EXCELLENCE]${NC} $1"
}

# 輸出文件
OUTPUT_FILE="$REPORTS_DIR/operational-excellence_${TIMESTAMP}.json"

log_info "開始 Operational Excellence 支柱檢查..."

# 初始化 JSON 結構
cat > "$OUTPUT_FILE" << EOF
{
  "pillar": "Operational Excellence",
  "account_id": "$ACCOUNT_ID",
  "region": "$REGION",
  "timestamp": "$TIMESTAMP",
  "checks": {
EOF

# CloudTrail 檢查
log_info "檢查 CloudTrail 配置..."
CLOUDTRAIL_DATA=$(aws cloudtrail describe-trails --region "$REGION" 2>/dev/null || echo '{"trailList":[]}')

# CloudWatch 檢查
log_info "檢查 CloudWatch 監控..."
CLOUDWATCH_ALARMS=$(aws cloudwatch describe-alarms --region "$REGION" --max-records 100 2>/dev/null || echo '{"MetricAlarms":[]}')

# Config 檢查
log_info "檢查 AWS Config..."
CONFIG_STATUS=$(aws configservice describe-configuration-recorders --region "$REGION" 2>/dev/null || echo '{"ConfigurationRecorders":[]}')

# Systems Manager 檢查
log_info "檢查 Systems Manager..."
SSM_DOCUMENTS=$(aws ssm list-documents --region "$REGION" --max-items 50 2>/dev/null || echo '{"DocumentIdentifiers":[]}')

# 寫入檢查結果
cat >> "$OUTPUT_FILE" << EOF
    "cloudtrail": $CLOUDTRAIL_DATA,
    "cloudwatch_alarms": $CLOUDWATCH_ALARMS,
    "config_service": $CONFIG_STATUS,
    "systems_manager": $SSM_DOCUMENTS
  },
  "recommendations": [
    "確保 CloudTrail 已啟用並記錄所有 API 調用",
    "設置適當的 CloudWatch 警報監控關鍵指標",
    "啟用 AWS Config 以追蹤資源配置變更",
    "使用 Systems Manager 自動化運維任務"
  ]
}
EOF

log_success "Operational Excellence 檢查完成，結果保存至: $OUTPUT_FILE"