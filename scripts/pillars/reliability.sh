#!/bin/bash

# Reliability Pillar 檢查
# 可靠性支柱

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
    echo -e "${BLUE}[RELIABILITY]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[RELIABILITY]${NC} $1"
}

# 輸出文件
OUTPUT_FILE="$REPORTS_DIR/reliability_${TIMESTAMP}.json"

log_info "開始 Reliability 支柱檢查..."

# 初始化 JSON 結構
cat > "$OUTPUT_FILE" << EOF
{
  "pillar": "Reliability",
  "account_id": "$ACCOUNT_ID",
  "region": "$REGION",
  "timestamp": "$TIMESTAMP",
  "checks": {
EOF

# EC2 實例檢查
log_info "檢查 EC2 實例..."
EC2_INSTANCES=$(aws ec2 describe-instances --region "$REGION" --max-items 100 2>/dev/null || echo '{"Reservations":[]}')

# Auto Scaling Groups 檢查
log_info "檢查 Auto Scaling Groups..."
ASG_GROUPS=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --max-items 50 2>/dev/null || echo '{"AutoScalingGroups":[]}')

# ELB/ALB 檢查
log_info "檢查 Load Balancers..."
LOAD_BALANCERS=$(aws elbv2 describe-load-balancers --region "$REGION" 2>/dev/null || echo '{"LoadBalancers":[]}')

# RDS 檢查
log_info "檢查 RDS 資料庫..."
RDS_INSTANCES=$(aws rds describe-db-instances --region "$REGION" --max-items 50 2>/dev/null || echo '{"DBInstances":[]}')

# S3 備份檢查
log_info "檢查 S3 儲存桶..."
S3_BUCKETS=$(aws s3api list-buckets 2>/dev/null || echo '{"Buckets":[]}')

# Route 53 檢查
log_info "檢查 Route 53..."
ROUTE53_ZONES=$(aws route53 list-hosted-zones --max-items 50 2>/dev/null || echo '{"HostedZones":[]}')

# 寫入檢查結果
cat >> "$OUTPUT_FILE" << EOF
    "ec2_instances": $EC2_INSTANCES,
    "auto_scaling_groups": $ASG_GROUPS,
    "load_balancers": $LOAD_BALANCERS,
    "rds_instances": $RDS_INSTANCES,
    "s3_buckets": $S3_BUCKETS,
    "route53_zones": $ROUTE53_ZONES
  },
  "recommendations": [
    "在多個可用區域部署資源",
    "設置 Auto Scaling 以處理流量變化",
    "使用 Load Balancer 分散流量",
    "啟用 RDS Multi-AZ 部署",
    "實施定期備份策略",
    "設置健康檢查和故障轉移機制"
  ]
}
EOF

log_success "Reliability 檢查完成，結果保存至: $OUTPUT_FILE"