#!/bin/bash

# 重新組織項目結構
# 刪除重複功能，建立清晰的資料夾分類

set -euo pipefail

echo "開始重新組織項目結構..."

# 1. 刪除重複的獨立分析腳本（功能已整合到 wa-tool.sh）
echo "刪除重複的分析腳本..."
rm -f scripts/analyze-compute-cost.sh
rm -f scripts/analyze-database-cost.sh
rm -f scripts/analyze-network-cost.sh
rm -f scripts/analyze-monitoring-cost.sh
rm -f scripts/analyze-datatransfer-cost.sh

# 2. 刪除重複的區域管理腳本（功能已整合到 wa-tool.sh）
echo "刪除重複的區域管理腳本..."
rm -f scripts/set-region.sh
rm -f scripts/quick-region.sh

# 3. 刪除重複的故障排除腳本（功能已整合到 wa-tool.sh）
echo "刪除重複的故障排除腳本..."
rm -f scripts/troubleshoot.sh

# 4. 刪除不需要的清理腳本
echo "刪除不需要的腳本..."
rm -f cleanup-duplicates.sh

# 5. 創建新的資料夾結構
echo "創建新的資料夾結構..."

# 核心評估腳本
mkdir -p core/assessment
mkdir -p core/analysis
mkdir -p core/pillars

# 工具腳本
mkdir -p tools

# 配置和模板
mkdir -p config
mkdir -p templates

# 文檔
mkdir -p docs

# 報告輸出
mkdir -p reports

# 6. 移動文件到新結構
echo "移動文件到新結構..."

# 核心評估腳本
if [[ -f "scripts/wa-assessment.sh" ]]; then
    mv scripts/wa-assessment.sh core/assessment/
fi
if [[ -f "scripts/generate-report.sh" ]]; then
    mv scripts/generate-report.sh core/assessment/
fi

# 分析腳本
if [[ -f "scripts/analyze-all.sh" ]]; then
    mv scripts/analyze-all.sh core/analysis/
fi
if [[ -f "scripts/analyze-security.sh" ]]; then
    mv scripts/analyze-security.sh core/analysis/
fi
if [[ -f "scripts/analyze-cost.sh" ]]; then
    mv scripts/analyze-cost.sh core/analysis/
fi

# 支柱腳本
if [[ -d "scripts/pillars" ]]; then
    mv scripts/pillars/* core/pillars/ 2>/dev/null || true
    rmdir scripts/pillars 2>/dev/null || true
fi

# 工具腳本
mv setup-permissions.sh tools/ 2>/dev/null || true

# 刪除空的 scripts 目錄
if [[ -d "scripts" ]]; then
    rmdir scripts 2>/dev/null || true
fi

# 7. 更新 wa-tool.sh 中的路徑
echo "更新 wa-tool.sh 路徑引用..."

# 創建新的 wa-tool.sh
cat > wa-tool.sh << 'EOFMAIN'
#!/bin/bash

# AWS Well-Architected Assessment Tool - 統一管理工具

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_header() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${PURPLE}AWS Well-Architected Assessment Tool${NC}"
    echo -e "${CYAN}6 Pillars Security & Cost Optimization Analysis${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

usage() {
    show_header
    echo
    echo "使用方式: $0 <command> [options]"
    echo
    echo "主要命令:"
    echo "  setup       初始化設定"
    echo "  assess      執行評估"
    echo "  analyze     分析結果"
    echo "  region      管理區域"
    echo "  check       系統檢查"
    echo "  help        顯示說明"
    echo
    echo "範例:"
    echo "  $0 setup        # 初始化"
    echo "  $0 assess       # 執行評估"
    echo "  $0 analyze      # 分析結果"
    echo
    exit 1
}

setup_permissions() {
    log_info "設定執行權限..."
    chmod +x wa-tool.sh
    find core -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find config -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find tools -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    log_success "權限設定完成"
}

setup_aws() {
    log_info "檢查 AWS 配置..."
    if [[ -x "config/aws-config.sh" ]]; then
        ./config/aws-config.sh
    else
        log_error "AWS 配置腳本不存在"
        exit 1
    fi
}

run_assessment() {
    log_info "執行評估..."
    if [[ -x "core/assessment/wa-assessment.sh" ]]; then
        ./core/assessment/wa-assessment.sh
    else
        log_error "評估腳本不存在或無執行權限"
        exit 1
    fi
}

analyze_results() {
    local type="${1:-all}"
    
    # 尋找最新結果
    local latest_timestamp
    latest_timestamp=$(ls reports/*_detailed_*.jsonl 2>/dev/null | head -1 | grep -o '[0-9]\{8\}_[0-9]\{6\}' | head -1 || echo "")
    
    if [[ -z "$latest_timestamp" ]]; then
        log_error "找不到評估結果，請先執行評估"
        exit 1
    fi
    
    case "$type" in
        "all")
            if [[ -x "core/analysis/analyze-all.sh" ]]; then
                ./core/analysis/analyze-all.sh "$latest_timestamp"
            fi
            ;;
        "security")
            if [[ -x "core/analysis/analyze-security.sh" ]]; then
                ./core/analysis/analyze-security.sh "reports/security_detailed_${latest_timestamp}.jsonl"
            fi
            ;;
        "cost")
            if [[ -x "core/analysis/analyze-cost.sh" ]]; then
                ./core/analysis/analyze-cost.sh "reports/cost-optimization_detailed_${latest_timestamp}.jsonl"
            fi
            ;;
        *)
            log_error "未知的分析類型: $type"
            exit 1
            ;;
    esac
}

manage_region() {
    local action="${1:-current}"
    
    case "$action" in
        "set")
            log_info "設定區域..."
            read -p "請輸入區域 (例如: us-east-1): " region
            aws configure set region "$region"
            log_success "區域已設定為: $region"
            ;;
        "current")
            local region=$(aws configure get region 2>/dev/null || echo "未設定")
            echo "當前區域: $region"
            ;;
        "list")
            log_info "可用區域:"
            aws ec2 describe-regions --query 'Regions[].RegionName' --output table
            ;;
        *)
            log_error "未知操作: $action"
            exit 1
            ;;
    esac
}

check_system() {
    log_info "檢查系統環境..."
    
    local checks_passed=0
    local checks_failed=0
    
    # 檢查 AWS CLI
    if command -v aws &>/dev/null; then
        echo "✅ AWS CLI"
        ((checks_passed++))
    else
        echo "❌ AWS CLI"
        ((checks_failed++))
    fi
    
    # 檢查 jq
    if command -v jq &>/dev/null; then
        echo "✅ jq"
        ((checks_passed++))
    else
        echo "❌ jq"
        ((checks_failed++))
    fi
    
    # 檢查 AWS 憑證
    if aws sts get-caller-identity &>/dev/null; then
        echo "✅ AWS 憑證"
        ((checks_passed++))
    else
        echo "❌ AWS 憑證"
        ((checks_failed++))
    fi
    
    # 檢查核心腳本
    if [[ -x "core/assessment/wa-assessment.sh" ]]; then
        echo "✅ 評估腳本"
        ((checks_passed++))
    else
        echo "❌ 評估腳本"
        ((checks_failed++))
    fi
    
    echo
    echo "通過: $checks_passed, 失敗: $checks_failed"
    
    if [[ $checks_failed -gt 0 ]]; then
        log_warning "發現問題，請執行: $0 setup"
        exit 1
    else
        log_success "系統檢查通過"
    fi
}

main() {
    local command="${1:-help}"
    local option="${2:-}"
    
    case "$command" in
        "setup")
            setup_permissions
            setup_aws
            log_success "初始化完成"
            ;;
        "assess")
            run_assessment
            ;;
        "analyze")
            analyze_results "$option"
            ;;
        "region")
            manage_region "$option"
            ;;
        "check")
            check_system
            ;;
        "help"|"--help"|"-h")
            usage
            ;;
        *)
            log_error "未知命令: $command"
            usage
            ;;
    esac
}

main "$@"
EOFMAIN

chmod +x wa-tool.sh

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "重新組織完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "新的結構:"
echo "  core/assessment/    - 評估腳本"
echo "  core/analysis/      - 分析腳本"
echo "  core/pillars/       - 支柱檢查腳本"
echo "  tools/              - 工具腳本"
echo "  config/             - 配置文件"
echo "  templates/          - 報告模板"
echo "  docs/               - 文檔"
echo "  reports/            - 輸出報告"
echo
echo "使用方式:"
echo "  ./wa-tool.sh setup      # 初始化"
echo "  ./wa-tool.sh assess     # 執行評估"
echo "  ./wa-tool.sh analyze    # 分析結果"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"