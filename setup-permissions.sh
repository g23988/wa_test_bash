#!/bin/bash

# AWS Well-Architected Assessment Tool 權限設定腳本
# 為所有腳本文件設定適當的執行權限

set -euo pipefail

# 顏色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SETUP]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[SETUP]${NC} $1"
}

log_error() {
    echo -e "${RED}[SETUP]${NC} $1"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "AWS Well-Architected Assessment Tool - 權限設定"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 檢查是否在正確的目錄
if [[ ! -f "scripts/wa-assessment.sh" ]]; then
    log_error "請在項目根目錄執行此腳本"
    exit 1
fi

log_info "開始設定腳本執行權限..."

# 主要腳本
log_info "設定主要腳本權限..."
chmod +x scripts/wa-assessment.sh
chmod +x scripts/generate-report.sh
chmod +x scripts/set-region.sh
chmod +x scripts/quick-region.sh

# 支柱檢查腳本
log_info "設定支柱檢查腳本權限..."
chmod +x scripts/pillars/operational-excellence.sh
chmod +x scripts/pillars/security.sh
chmod +x scripts/pillars/reliability.sh
chmod +x scripts/pillars/performance-efficiency.sh
chmod +x scripts/pillars/cost-optimization.sh
chmod +x scripts/pillars/sustainability.sh

# 分析腳本
log_info "設定分析腳本權限..."
chmod +x scripts/analyze-all.sh
chmod +x scripts/analyze-security.sh
chmod +x scripts/analyze-cost.sh
chmod +x scripts/analyze-compute-cost.sh
chmod +x scripts/analyze-database-cost.sh
chmod +x scripts/analyze-network-cost.sh
chmod +x scripts/analyze-monitoring-cost.sh
chmod +x scripts/analyze-datatransfer-cost.sh

# 配置腳本
log_info "設定配置腳本權限..."
chmod +x config/aws-config.sh

# 設定此腳本本身的權限
chmod +x setup-permissions.sh

log_success "所有腳本權限設定完成！"

# 驗證權限設定
log_info "驗證權限設定..."

failed_files=()

# 檢查主要腳本
for script in \
    "scripts/wa-assessment.sh" \
    "scripts/generate-report.sh" \
    "scripts/set-region.sh" \
    "scripts/quick-region.sh" \
    "config/aws-config.sh" \
    "setup-permissions.sh"
do
    if [[ -x "$script" ]]; then
        echo "  ✅ $script"
    else
        echo "  ❌ $script"
        failed_files+=("$script")
    fi
done

# 檢查支柱腳本
for script in scripts/pillars/*.sh; do
    if [[ -x "$script" ]]; then
        echo "  ✅ $script"
    else
        echo "  ❌ $script"
        failed_files+=("$script")
    fi
done

# 檢查分析腳本
for script in scripts/analyze-*.sh; do
    if [[ -x "$script" ]]; then
        echo "  ✅ $script"
    else
        echo "  ❌ $script"
        failed_files+=("$script")
    fi
done

echo

if [[ ${#failed_files[@]} -eq 0 ]]; then
    log_success "所有腳本權限驗證通過！"
    echo
    echo "現在可以執行評估："
    echo "  ./scripts/wa-assessment.sh"
else
    log_error "以下文件權限設定失敗："
    for file in "${failed_files[@]}"; do
        echo "  - $file"
    done
    echo
    echo "請手動設定權限："
    echo "  chmod +x ${failed_files[*]}"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"