#!/bin/bash

# AWS Region 設定工具
# 用於設定和管理 AWS Well-Architected Assessment Tool 的區域配置

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
    echo -e "${BLUE}[REGION-CONFIG]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[REGION-CONFIG]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[REGION-CONFIG]${NC} $1"
}

log_error() {
    echo -e "${RED}[REGION-CONFIG]${NC} $1"
}

# 使用方式
usage() {
    echo "AWS Well-Architected Assessment Tool - Region 設定"
    echo
    echo "使用方式:"
    echo "  $0                    # 互動式設定區域"
    echo "  $0 <region>           # 直接設定指定區域"
    echo "  $0 --list             # 列出所有可用區域"
    echo "  $0 --current          # 顯示當前區域設定"
    echo "  $0 --reset            # 重設為預設區域"
    echo "  $0 --help             # 顯示此說明"
    echo
    echo "範例:"
    echo "  $0 us-east-1          # 設定為 us-east-1"
    echo "  $0 ap-southeast-1     # 設定為 ap-southeast-1"
    echo
    exit 1
}

# 檢查 AWS CLI 是否可用
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安裝或不在 PATH 中"
        echo "請先安裝 AWS CLI: https://aws.amazon.com/cli/"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 憑證未配置或無效"
        echo "請執行: aws configure"
        exit 1
    fi
}

# 獲取當前區域設定
get_current_region() {
    local current_region
    current_region=$(aws configure get region 2>/dev/null || echo "")
    
    if [[ -z "$current_region" ]]; then
        # 嘗試從環境變數獲取
        current_region="${AWS_DEFAULT_REGION:-}"
        if [[ -z "$current_region" ]]; then
            echo "未設定"
        else
            echo "$current_region (環境變數)"
        fi
    else
        echo "$current_region"
    fi
}

# 獲取所有可用區域
get_available_regions() {
    log_info "獲取可用區域列表..."
    aws ec2 describe-regions --all-regions --query 'Regions[].{Name:RegionName,Description:OptInStatus}' --output table 2>/dev/null || {
        log_warning "無法獲取完整區域列表，使用預設列表"
        echo "常用區域:"
        echo "  us-east-1      (美國東部 - 維吉尼亞北部)"
        echo "  us-west-2      (美國西部 - 奧勒岡)"
        echo "  eu-west-1      (歐洲 - 愛爾蘭)"
        echo "  ap-southeast-1 (亞太 - 新加坡)"
        echo "  ap-northeast-1 (亞太 - 東京)"
        echo "  ap-southeast-2 (亞太 - 雪梨)"
    }
}

# 驗證區域是否有效
validate_region() {
    local region="$1"
    
    log_info "驗證區域: $region"
    
    # 嘗試列出該區域的 EC2 實例來驗證區域有效性
    if aws ec2 describe-instances --region "$region" --max-items 1 &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 設定區域
set_region() {
    local region="$1"
    
    if ! validate_region "$region"; then
        log_error "無效的區域: $region"
        echo "請使用 '$0 --list' 查看可用區域"
        return 1
    fi
    
    log_info "設定 AWS 區域為: $region"
    
    # 設定 AWS CLI 預設區域
    aws configure set region "$region"
    
    # 也設定環境變數（對當前 session 有效）
    export AWS_DEFAULT_REGION="$region"
    
    log_success "區域已設定為: $region"
    
    # 驗證設定
    local new_region
    new_region=$(aws configure get region)
    if [[ "$new_region" == "$region" ]]; then
        log_success "設定驗證成功"
    else
        log_error "設定驗證失敗"
        return 1
    fi
    
    # 顯示區域資訊
    show_region_info "$region"
}

# 顯示區域資訊
show_region_info() {
    local region="$1"
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}區域資訊${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 獲取區域描述
    local region_info
    region_info=$(aws ec2 describe-regions --region-names "$region" --query 'Regions[0].{Name:RegionName,Endpoint:Endpoint}' --output json 2>/dev/null || echo '{}')
    
    if [[ "$region_info" != "{}" ]]; then
        local endpoint
        endpoint=$(echo "$region_info" | jq -r '.Endpoint // "N/A"')
        echo "區域名稱: $region"
        echo "端點: $endpoint"
    else
        echo "區域名稱: $region"
        echo "端點: 無法獲取"
    fi
    
    # 檢查區域中的可用區域
    local azs
    azs=$(aws ec2 describe-availability-zones --region "$region" --query 'AvailabilityZones[].ZoneName' --output text 2>/dev/null || echo "無法獲取")
    echo "可用區域: $azs"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 互動式區域選擇
interactive_region_selection() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${PURPLE}AWS Region 互動式設定${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local current_region
    current_region=$(get_current_region)
    echo "當前區域: $current_region"
    echo
    
    echo "常用區域選項:"
    echo "  1) us-east-1      (美國東部 - 維吉尼亞北部)"
    echo "  2) us-west-2      (美國西部 - 奧勒岡)"
    echo "  3) eu-west-1      (歐洲 - 愛爾蘭)"
    echo "  4) ap-southeast-1 (亞太 - 新加坡)"
    echo "  5) ap-northeast-1 (亞太 - 東京)"
    echo "  6) ap-southeast-2 (亞太 - 雪梨)"
    echo "  7) 自訂區域"
    echo "  8) 顯示所有可用區域"
    echo "  0) 取消"
    echo
    
    while true; do
        read -p "請選擇 (0-8): " choice
        
        case $choice in
            1) set_region "us-east-1"; break;;
            2) set_region "us-west-2"; break;;
            3) set_region "eu-west-1"; break;;
            4) set_region "ap-southeast-1"; break;;
            5) set_region "ap-northeast-1"; break;;
            6) set_region "ap-southeast-2"; break;;
            7) 
                echo
                read -p "請輸入區域名稱 (例如: eu-central-1): " custom_region
                if [[ -n "$custom_region" ]]; then
                    set_region "$custom_region"
                    break
                else
                    log_warning "區域名稱不能為空"
                fi
                ;;
            8) 
                echo
                get_available_regions
                echo
                ;;
            0) 
                log_info "取消設定"
                exit 0
                ;;
            *) 
                log_warning "無效選擇，請輸入 0-8"
                ;;
        esac
    done
}

# 重設為預設區域
reset_to_default() {
    local default_region="us-east-1"
    
    log_info "重設區域為預設值: $default_region"
    set_region "$default_region"
}

# 顯示當前區域狀態
show_current_status() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}當前 AWS 區域設定${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local current_region
    current_region=$(get_current_region)
    echo "當前區域: $current_region"
    
    # 顯示 AWS 帳戶資訊
    local account_info
    account_info=$(aws sts get-caller-identity 2>/dev/null || echo '{}')
    if [[ "$account_info" != "{}" ]]; then
        local account_id user_arn
        account_id=$(echo "$account_info" | jq -r '.Account // "N/A"')
        user_arn=$(echo "$account_info" | jq -r '.Arn // "N/A"')
        echo "AWS 帳戶: $account_id"
        echo "使用者/角色: $user_arn"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 如果區域有效，顯示詳細資訊
    if [[ "$current_region" != "未設定" && "$current_region" != *"環境變數"* ]]; then
        show_region_info "$current_region"
    fi
}

# 主函數
main() {
    # 檢查 AWS CLI
    check_aws_cli
    
    # 處理命令列參數
    case "${1:-}" in
        --help|-h)
            usage
            ;;
        --list|-l)
            echo "可用的 AWS 區域:"
            get_available_regions
            ;;
        --current|-c)
            show_current_status
            ;;
        --reset|-r)
            reset_to_default
            ;;
        "")
            # 無參數，進入互動模式
            interactive_region_selection
            ;;
        *)
            # 直接設定指定區域
            set_region "$1"
            ;;
    esac
}

# 執行主函數
main "$@"