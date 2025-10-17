#!/bin/bash

# AWS 配置檢查和設定腳本

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[CONFIG]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[CONFIG]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[CONFIG]${NC} $1"
}

log_error() {
    echo -e "${RED}[CONFIG]${NC} $1"
}

# 檢查 AWS CLI 配置
check_aws_config() {
    log_info "檢查 AWS CLI 配置..."
    
    # 檢查 AWS CLI 是否安裝
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安裝，請先安裝 AWS CLI"
        echo "安裝指令: brew install awscli (macOS) 或參考 https://aws.amazon.com/cli/"
        return 1
    fi
    
    # 檢查 AWS 憑證
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 憑證未配置或無效"
        echo "請執行: aws configure"
        return 1
    fi
    
    # 顯示當前配置
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    REGION=$(aws configure get region || echo "未設定")
    
    log_success "AWS 配置檢查完成"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "帳戶 ID: $ACCOUNT_ID"
    echo "使用者/角色: $USER_ARN"
    echo "預設區域: $REGION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 檢查必要權限
check_permissions() {
    log_info "檢查 readonly 權限..."
    
    local permissions_ok=true
    
    # 測試基本 readonly 權限
    local services=(
        "ec2:DescribeInstances"
        "iam:ListUsers"
        "s3:ListAllMyBuckets"
        "rds:DescribeDBInstances"
        "cloudtrail:DescribeTrails"
    )
    
    for service in "${services[@]}"; do
        local service_name=$(echo "$service" | cut -d':' -f1)
        local action=$(echo "$service" | cut -d':' -f2)
        
        case $service_name in
            "ec2")
                if ! aws ec2 describe-instances --max-items 1 &> /dev/null; then
                    log_warning "EC2 readonly 權限可能不足"
                    permissions_ok=false
                fi
                ;;
            "iam")
                if ! aws iam list-users --max-items 1 &> /dev/null; then
                    log_warning "IAM readonly 權限可能不足"
                    permissions_ok=false
                fi
                ;;
            "s3")
                if ! aws s3api list-buckets &> /dev/null; then
                    log_warning "S3 readonly 權限可能不足"
                    permissions_ok=false
                fi
                ;;
        esac
    done
    
    if [ "$permissions_ok" = true ]; then
        log_success "基本 readonly 權限檢查通過"
    else
        log_warning "部分服務權限不足，某些檢查可能會失敗"
    fi
}

# 設定區域
set_region() {
    local region=$1
    
    if [ -z "$region" ]; then
        log_info "可用的 AWS 區域:"
        aws ec2 describe-regions --query 'Regions[].[RegionName,OptInStatus]' --output table
        echo
        read -p "請輸入要使用的區域 (預設: us-east-1): " region
        region=${region:-us-east-1}
    fi
    
    aws configure set region "$region"
    log_success "區域已設定為: $region"
}

# 主函數
main() {
    echo "AWS Well-Architected Assessment Tool - 配置檢查"
    echo "================================================"
    
    check_aws_config
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    check_permissions
    
    # 如果沒有設定區域，提示設定
    if [ -z "$(aws configure get region)" ]; then
        log_warning "未設定預設區域"
        set_region
    fi
    
    log_success "配置檢查完成，可以開始執行評估"
}

# 如果直接執行此腳本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi