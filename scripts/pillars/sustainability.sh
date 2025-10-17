#!/bin/bash

# Sustainability Pillar 檢查
# 永續性支柱

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
    echo -e "${BLUE}[SUSTAINABILITY]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUSTAINABILITY]${NC} $1"
}

# 輸出文件
OUTPUT_FILE="$REPORTS_DIR/sustainability_${TIMESTAMP}.json"

log_info "開始 Sustainability 支柱檢查..."

# 初始化 JSON 結構
cat > "$OUTPUT_FILE" << EOF
{
  "pillar": "Sustainability",
  "account_id": "$ACCOUNT_ID",
  "region": "$REGION",
  "timestamp": "$TIMESTAMP",
  "checks": {
EOF

# EC2 實例效率檢查
log_info "檢查 EC2 實例效率..."
EC2_INSTANCES=$(aws ec2 describe-instances --region "$REGION" --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Platform]' --output json 2>/dev/null || echo '[]')

# Lambda 函數檢查
log_info "檢查 Lambda 函數配置..."
LAMBDA_FUNCTIONS=$(aws lambda list-functions --region "$REGION" --query 'Functions[].[FunctionName,Runtime,MemorySize,Timeout]' --output json 2>/dev/null || echo '[]')

# 儲存使用率檢查
log_info "檢查儲存使用率..."
EBS_VOLUMES=$(aws ec2 describe-volumes --region "$REGION" --query 'Volumes[].[VolumeId,VolumeType,Size,State]' --output json 2>/dev/null || echo '[]')

# 區域使用檢查
log_info "檢查區域分佈..."
REGIONS_USED=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output json 2>/dev/null || echo '[]')

# Auto Scaling 檢查
log_info "檢查 Auto Scaling 配置..."
ASG_GROUPS=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --query 'AutoScalingGroups[].[AutoScalingGroupName,MinSize,MaxSize,DesiredCapacity]' --output json 2>/dev/null || echo '[]')

# 寫入檢查結果
cat >> "$OUTPUT_FILE" << EOF
    "ec2_instances": $EC2_INSTANCES,
    "lambda_functions": $LAMBDA_FUNCTIONS,
    "ebs_volumes": $EBS_VOLUMES,
    "regions_used": $REGIONS_USED,
    "auto_scaling_groups": $ASG_GROUPS
  },
  "recommendations": [
    "使用最新一代的 EC2 實例類型以提升能源效率",
    "優化 Lambda 函數記憶體配置以減少執行時間",
    "選擇靠近用戶的 AWS 區域以減少網路延遲",
    "使用 Auto Scaling 根據需求動態調整資源",
    "實施資源標記以追蹤使用情況",
    "定期檢查並移除未使用的資源",
    "使用 Graviton 處理器實例以提升效能功耗比"
  ]
}
EOF

log_success "Sustainability 檢查完成，結果保存至: $OUTPUT_FILE"