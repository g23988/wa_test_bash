#!/bin/bash

# AWS Well-Architected 6 Pillars Assessment Tool
# 主要檢查腳本

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
REPORTS_DIR="$PROJECT_ROOT/reports"
TEMPLATES_DIR="$PROJECT_ROOT/templates"

# 創建報告目錄
mkdir -p "$REPORTS_DIR"

# 日誌函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查前置需求
check_prerequisites() {
    log_info "檢查前置需求..."
    
    # 檢查 AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安裝"
        exit 1
    fi
    
    # 檢查 jq
    if ! command -v jq &> /dev/null; then
        log_error "jq 未安裝"
        exit 1
    fi
    
    # 檢查 AWS 憑證
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 憑證配置錯誤"
        exit 1
    fi
    
    log_success "前置需求檢查完成"
}

# 主函數
main() {
    # 檢查命令列參數
    case "${1:-}" in
        --set-region|-r)
            log_info "啟動區域設定工具..."
            "$SCRIPT_DIR/set-region.sh"
            exit 0
            ;;
        --help|-h)
            echo "AWS Well-Architected 6 Pillars Assessment Tool"
            echo
            echo "使用方式:"
            echo "  $0                # 執行完整評估"
            echo "  $0 --set-region   # 設定評估區域"
            echo "  $0 --help         # 顯示此說明"
            echo
            echo "評估前建議:"
            echo "  1. 確認 AWS 憑證已正確配置"
            echo "  2. 設定適當的評估區域"
            echo "  3. 確保具有必要的 readonly 權限"
            exit 0
            ;;
    esac
    
    log_info "開始 AWS Well-Architected 6 Pillars 評估"
    
    check_prerequisites
    
    # 獲取 AWS 帳戶資訊
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region || echo "us-east-1")
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    
    log_info "AWS 帳戶: $ACCOUNT_ID"
    log_info "評估區域: $REGION"
    
    # 確認區域設定
    if [[ "$REGION" == "us-east-1" ]] && [[ -z "$(aws configure get region)" ]]; then
        log_warning "使用預設區域 us-east-1，如需變更請執行: $0 --set-region"
    fi
    
    # 執行各支柱檢查
    log_info "執行 6 個支柱檢查..."
    
    log_info "1/6 執行 Operational Excellence 檢查..."
    "$SCRIPT_DIR/pillars/operational-excellence.sh" "$ACCOUNT_ID" "$REGION" "$TIMESTAMP"
    
    log_info "2/6 執行 Security 檢查 (詳細版本)..."
    "$SCRIPT_DIR/pillars/security.sh" "$ACCOUNT_ID" "$REGION" "$TIMESTAMP"
    
    log_info "3/6 執行 Reliability 檢查..."
    "$SCRIPT_DIR/pillars/reliability.sh" "$ACCOUNT_ID" "$REGION" "$TIMESTAMP"
    
    log_info "4/6 執行 Performance Efficiency 檢查..."
    "$SCRIPT_DIR/pillars/performance-efficiency.sh" "$ACCOUNT_ID" "$REGION" "$TIMESTAMP"
    
    log_info "5/6 執行 Cost Optimization 檢查 (詳細版本)..."
    "$SCRIPT_DIR/pillars/cost-optimization.sh" "$ACCOUNT_ID" "$REGION" "$TIMESTAMP"
    
    log_info "6/6 執行 Sustainability 檢查..."
    "$SCRIPT_DIR/pillars/sustainability.sh" "$ACCOUNT_ID" "$REGION" "$TIMESTAMP"
    
    # 生成綜合報告
    "$SCRIPT_DIR/generate-report.sh" "$ACCOUNT_ID" "$REGION" "$TIMESTAMP"
    
    log_success "評估完成！報告已生成在 $REPORTS_DIR 目錄"
}

# 執行主函數
main "$@"