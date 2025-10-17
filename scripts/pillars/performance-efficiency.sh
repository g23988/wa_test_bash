#!/bin/bash

# Performance Efficiency Pillar 檢查
# 效能效率支柱

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
    echo -e "${BLUE}[PERFORMANCE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PERFORMANCE]${NC} $1"
}

# 輸出文件
OUTPUT_FILE="$REPORTS_DIR/performance-efficiency_${TIMESTAMP}.json"

log_info "開始 Performance Efficiency 支柱檢查..."

# 初始化 JSON 結構
cat > "$OUTPUT_FILE" << EOF
{
  "pillar": "Performance Efficiency",
  "account_id": "$ACCOUNT_ID",
  "region": "$REGION",
  "timestamp": "$TIMESTAMP",
  "checks": {
EOF

# EC2 實例類型檢查
log_info "檢查 EC2 實例類型..."
EC2_INSTANCES=$(aws ec2 describe-instances --region "$REGION" --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output json 2>/dev/null || echo '[]')

# CloudFront 檢查
log_info "檢查 CloudFront 分發..."
CLOUDFRONT_DISTRIBUTIONS=$(aws cloudfront list-distributions --max-items 50 2>/dev/null || echo '{"DistributionList":{"Items":[]}}')

# ElastiCache 檢查
log_info "檢查 ElastiCache..."
ELASTICACHE_CLUSTERS=$(aws elasticache describe-cache-clusters --region "$REGION" --max-items 50 2>/dev/null || echo '{"CacheClusters":[]}')

# Lambda 函數檢查
log_info "檢查 Lambda 函數..."
LAMBDA_FUNCTIONS=$(aws lambda list-functions --region "$REGION" --max-items 100 2>/dev/null || echo '{"Functions":[]}')

# EBS 磁碟區檢查
log_info "檢查 EBS 磁碟區..."
EBS_VOLUMES=$(aws ec2 describe-volumes --region "$REGION" --max-items 100 2>/dev/null || echo '{"Volumes":[]}')

# CloudWatch 指標檢查
log_info "檢查 CloudWatch 指標..."
CLOUDWATCH_METRICS=$(aws cloudwatch list-metrics --region "$REGION" --max-records 50 2>/dev/null || echo '{"Metrics":[]}')

# 寫入檢查結果
cat >> "$OUTPUT_FILE" << EOF
    "ec2_instances": $EC2_INSTANCES,
    "cloudfront_distributions": $CLOUDFRONT_DISTRIBUTIONS,
    "elasticache_clusters": $ELASTICACHE_CLUSTERS,
    "lambda_functions": $LAMBDA_FUNCTIONS,
    "ebs_volumes": $EBS_VOLUMES,
    "cloudwatch_metrics": $CLOUDWATCH_METRICS
  },
  "recommendations": [
    "選擇適合工作負載的 EC2 實例類型",
    "使用 CloudFront 加速內容分發",
    "實施快取策略以提升效能",
    "優化 Lambda 函數記憶體配置",
    "使用 SSD 儲存以提升 I/O 效能",
    "監控效能指標並設置警報"
  ]
}
EOF

log_success "Performance Efficiency 檢查完成，結果保存至: $OUTPUT_FILE"