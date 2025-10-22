#!/bin/bash

# AWS Well-Architected Assessment Tool - 統一管理工具
# 整合所有功能的單一入口點

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() {
    echo -e "${BLUE}[WA-TOOL]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[WA-TOOL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WA-TOOL]${NC} $1"
}

log_error() {
    echo -e "${RED}[WA-TOOL]${NC} $1"
}

# 顯示標題
show_header() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${PURPLE}AWS Well-Architected Assessment Tool${NC}"
    echo -e "${CYAN}6 Pillars Security & Cost Optimization Analysis${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 使用說明
usage() {
    show_header
    echo
    echo "使用方式: $0 <command> [options]"
    echo
    echo "主要命令:"
    echo "  setup                 初始化設定 (權限、AWS 配置)"
    echo "  assess                執行完整的 6 支柱評估"
    echo "  analyze               分析評估結果"
    echo "  region                管理 AWS 區域設定"
    echo "  check                 檢查系統狀態和故障排除"
    echo
    echo "設定命令:"
    echo "  setup permissions     設定腳本執行權限"
    echo "  setup aws             檢查 AWS 配置"
    echo "  setup all             執行完整初始化"
    echo
    echo "評估命令:"
    echo "  assess run            執行完整評估"
    echo "  assess security       只執行安全性評估"
    echo "  assess cost           只執行成本優化評估"
    echo
    echo "分析命令:"
    echo "  analyze all           綜合分析所有結果"
    echo "  analyze security      分析安全檢查結果"
    echo "  analyze cost          分析成本優化結果"
    echo "  analyze compute       分析計算資源成本"
    echo "  analyze database      分析資料庫成本"
    echo "  analyze network       分析網路成本"
    echo "  analyze monitoring    分析監控成本"
    echo "  analyze datatransfer  分析資料傳輸成本"
    echo
    echo "區域管理:"
    echo "  region set            設定評估區域"
    echo "  region current        顯示當前區域"
    echo "  region list           列出可用區域"
    echo "  region quick <code>   快速切換區域 (us1, ap1, eu1 等)"
    echo
    echo "系統檢查:"
    echo "  check system          檢查系統環境"
    echo "  check aws             檢查 AWS 配置"
    echo "  check permissions     檢查文件權限"
    echo
    echo "範例:"
    echo "  $0 setup all          # 完整初始化"
    echo "  $0 region set         # 設定區域"
    echo "  $0 assess run         # 執行評估"
    echo "  $0 analyze all        # 分析結果"
    echo
    exit 1
}

# 檢查必要文件
check_required_files() {
    local missing_files=()
    
    # 檢查主要腳本
    local required_scripts=(
        "scripts/wa-assessment.sh"
        "scripts/generate-report.sh"
        "config/aws-config.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            missing_files+=("$script")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "缺少必要文件:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        exit 1
    fi
}

# 設定權限
setup_permissions() {
    log_info "設定腳本執行權限..."
    
    # 設定主要腳本權限
    chmod +x wa-tool.sh 2>/dev/null || true
    chmod +x setup-permissions.sh 2>/dev/null || true
    
    # 設定其他腳本權限
    find scripts -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find config -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    
    log_success "權限設定完成"
}

# AWS 配置檢查
setup_aws() {
    log_info "檢查 AWS 配置..."
    
    if [[ -x "config/aws-config.sh" ]]; then
        ./config/aws-config.sh
    else
        log_error "AWS 配置腳本不存在或無執行權限"
        exit 1
    fi
}

# 完整初始化
setup_all() {
    show_header
    log_info "開始完整初始化..."
    
    setup_permissions
    setup_aws
    
    log_success "初始化完成！現在可以執行評估了"
    echo
    echo "下一步:"
    echo "  $0 region set         # 設定評估區域 (可選)"
    echo "  $0 assess run         # 執行評估"
}

# 執行評估
run_assessment() {
    local pillar="${1:-all}"
    
    check_required_files
    
    case "$pillar" in
        "all"|"run")
            log_info "執行完整的 6 支柱評估..."
            ./scripts/wa-assessment.sh
            ;;
        "security")
            log_info "執行安全性支柱評估..."
            # 這裡可以添加單獨執行安全性評估的邏輯
            log_warning "單獨支柱評估功能開發中，執行完整評估..."
            ./scripts/wa-assessment.sh
            ;;
        "cost")
            log_info "執行成本優化支柱評估..."
            # 這裡可以添加單獨執行成本評估的邏輯
            log_warning "單獨支柱評估功能開發中，執行完整評估..."
            ./scripts/wa-assessment.sh
            ;;
        *)
            log_error "未知的評估類型: $pillar"
            exit 1
            ;;
    esac
}

# 分析結果
analyze_results() {
    local analysis_type="${1:-all}"
    
    # 尋找最新的結果文件
    local latest_timestamp
    latest_timestamp=$(ls reports/*_detailed_*.jsonl 2>/dev/null | head -1 | grep -o '[0-9]\{8\}_[0-9]\{6\}' | head -1 || echo "")
    
    if [[ -z "$latest_timestamp" ]]; then
        log_error "找不到評估結果文件，請先執行評估"
        echo "執行: $0 assess run"
        exit 1
    fi
    
    local security_file="reports/security_detailed_${latest_timestamp}.jsonl"
    local cost_file="reports/cost-optimization_detailed_${latest_timestamp}.jsonl"
    
    case "$analysis_type" in
        "all")
            if [[ -x "scripts/analyze-all.sh" ]]; then
                ./scripts/analyze-all.sh "$latest_timestamp"
            else
                log_error "綜合分析腳本不存在"
                exit 1
            fi
            ;;
        "security")
            if [[ -f "$security_file" && -x "scripts/analyze-security.sh" ]]; then
                ./scripts/analyze-security.sh "$security_file"
            else
                log_error "安全分析腳本或結果文件不存在"
                exit 1
            fi
            ;;
        "cost")
            if [[ -f "$cost_file" && -x "scripts/analyze-cost.sh" ]]; then
                ./scripts/analyze-cost.sh "$cost_file"
            else
                log_error "成本分析腳本或結果文件不存在"
                exit 1
            fi
            ;;
        "compute"|"database"|"network"|"monitoring"|"datatransfer")
            local script="scripts/analyze-${analysis_type}-cost.sh"
            local legacy_script="scripts/legacy/analyze-${analysis_type}-cost.sh"
            
            if [[ -f "$cost_file" ]]; then
                if [[ -x "$script" ]]; then
                    ./"$script" "$cost_file"
                elif [[ -x "$legacy_script" ]]; then
                    log_info "使用 legacy 腳本: $legacy_script"
                    ./"$legacy_script" "$cost_file"
                else
                    log_error "${analysis_type} 分析腳本不存在"
                    exit 1
                fi
            else
                log_error "成本分析結果文件不存在"
                exit 1
            fi
            ;;
        *)
            log_error "未知的分析類型: $analysis_type"
            exit 1
            ;;
    esac
}

# 區域管理
manage_region() {
    local action="${1:-set}"
    local region_code="${2:-}"
    
    case "$action" in
        "set")
            if [[ -x "scripts/set-region.sh" ]]; then
                ./scripts/set-region.sh
            elif [[ -x "scripts/legacy/set-region.sh" ]]; then
                ./scripts/legacy/set-region.sh
            else
                log_error "區域設定腳本不存在"
                exit 1
            fi
            ;;
        "current")
            local current_region
            current_region=$(aws configure get region 2>/dev/null || echo "未設定")
            echo "當前區域: $current_region"
            ;;
        "list")
            if [[ -x "scripts/set-region.sh" ]]; then
                ./scripts/set-region.sh --list
            elif [[ -x "scripts/legacy/set-region.sh" ]]; then
                ./scripts/legacy/set-region.sh --list
            else
                log_error "區域設定腳本不存在"
                exit 1
            fi
            ;;
        "quick")
            if [[ -n "$region_code" ]]; then
                if [[ -x "scripts/quick-region.sh" ]]; then
                    ./scripts/quick-region.sh "$region_code"
                elif [[ -x "scripts/legacy/quick-region.sh" ]]; then
                    ./scripts/legacy/quick-region.sh "$region_code"
                else
                    log_error "快速區域腳本不存在"
                    exit 1
                fi
            else
                log_error "請提供區域代碼"
                exit 1
            fi
            ;;
        *)
            log_error "未知的區域操作: $action"
            exit 1
            ;;
    esac
}

# 系統檢查
check_system() {
    local check_type="${1:-system}"
    
    case "$check_type" in
        "system")
            if [[ -x "scripts/troubleshoot.sh" ]]; then
                ./scripts/troubleshoot.sh
            elif [[ -x "scripts/legacy/troubleshoot.sh" ]]; then
                ./scripts/legacy/troubleshoot.sh
            else
                log_error "故障排除腳本不存在"
                exit 1
            fi
            ;;
        "aws")
            if [[ -x "config/aws-config.sh" ]]; then
                ./config/aws-config.sh
            else
                log_error "AWS 配置腳本不存在"
                exit 1
            fi
            ;;
        "permissions")
            setup_permissions
            ;;
        *)
            log_error "未知的檢查類型: $check_type"
            exit 1
            ;;
    esac
}

# 主函數
main() {
    local command="${1:-}"
    local subcommand="${2:-}"
    local option="${3:-}"
    
    case "$command" in
        "setup")
            case "$subcommand" in
                "permissions") setup_permissions ;;
                "aws") setup_aws ;;
                "all"|"") setup_all ;;
                *) log_error "未知的設定命令: $subcommand"; usage ;;
            esac
            ;;
        "assess")
            run_assessment "$subcommand"
            ;;
        "analyze")
            analyze_results "$subcommand"
            ;;
        "region")
            manage_region "$subcommand" "$option"
            ;;
        "check")
            check_system "$subcommand"
            ;;
        "help"|"--help"|"-h"|"")
            usage
            ;;
        *)
            log_error "未知命令: $command"
            usage
            ;;
    esac
}

# 執行主函數
main "$@"