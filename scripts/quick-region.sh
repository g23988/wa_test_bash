#!/bin/bash

# 快速區域切換工具
# 提供常用區域的快速切換功能

set -euo pipefail

# 顏色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[QUICK-REGION]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[QUICK-REGION]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[QUICK-REGION]${NC} $1"
}

# 常用區域定義
declare -A REGIONS=(
    ["us1"]="us-east-1"
    ["us2"]="us-west-2"
    ["eu1"]="eu-west-1"
    ["eu2"]="eu-central-1"
    ["ap1"]="ap-southeast-1"
    ["ap2"]="ap-northeast-1"
    ["ap3"]="ap-southeast-2"
)

declare -A REGION_NAMES=(
    ["us-east-1"]="美國東部 (維吉尼亞北部)"
    ["us-west-2"]="美國西部 (奧勒岡)"
    ["eu-west-1"]="歐洲 (愛爾蘭)"
    ["eu-central-1"]="歐洲 (法蘭克福)"
    ["ap-southeast-1"]="亞太 (新加坡)"
    ["ap-northeast-1"]="亞太 (東京)"
    ["ap-southeast-2"]="亞太 (雪梨)"
)

# 使用方式
usage() {
    echo "快速區域切換工具"
    echo
    echo "使用方式:"
    echo "  $0 <region-code>      # 切換到指定區域"
    echo "  $0 --list             # 列出可用的快速代碼"
    echo "  $0 --current          # 顯示當前區域"
    echo
    echo "快速代碼:"
    for code in "${!REGIONS[@]}"; do
        region="${REGIONS[$code]}"
        name="${REGION_NAMES[$region]:-}"
        printf "  %-4s -> %-15s %s\n" "$code" "$region" "$name"
    done | sort
    echo
    echo "範例:"
    echo "  $0 us1                # 切換到 us-east-1"
    echo "  $0 ap1                # 切換到 ap-southeast-1"
    exit 1
}

# 獲取當前區域
get_current_region() {
    aws configure get region 2>/dev/null || echo "未設定"
}

# 設定區域
set_region() {
    local region="$1"
    
    log_info "切換到區域: $region"
    aws configure set region "$region"
    export AWS_DEFAULT_REGION="$region"
    
    local name="${REGION_NAMES[$region]:-}"
    log_success "已切換到: $region ${name:+($name)}"
}

# 顯示當前狀態
show_current() {
    local current_region
    current_region=$(get_current_region)
    local name="${REGION_NAMES[$current_region]:-}"
    
    echo "當前區域: $current_region ${name:+($name)}"
}

# 主函數
main() {
    case "${1:-}" in
        --help|-h)
            usage
            ;;
        --list|-l)
            echo "可用的快速區域代碼:"
            for code in "${!REGIONS[@]}"; do
                region="${REGIONS[$code]}"
                name="${REGION_NAMES[$region]:-}"
                printf "  %-4s -> %-15s %s\n" "$code" "$region" "$name"
            done | sort
            ;;
        --current|-c)
            show_current
            ;;
        "")
            log_warning "請指定區域代碼"
            usage
            ;;
        *)
            local region_code="$1"
            if [[ -n "${REGIONS[$region_code]:-}" ]]; then
                set_region "${REGIONS[$region_code]}"
            else
                # 檢查是否直接輸入了區域名稱
                if [[ "$region_code" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
                    set_region "$region_code"
                else
                    log_warning "無效的區域代碼: $region_code"
                    echo "使用 '$0 --list' 查看可用代碼"
                    exit 1
                fi
            fi
            ;;
    esac
}

# 執行主函數
main "$@"