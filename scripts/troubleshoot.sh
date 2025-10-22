#!/bin/bash

# AWS Well-Architected Assessment Tool 故障排除工具

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[TROUBLESHOOT]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[TROUBLESHOOT]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[TROUBLESHOOT]${NC} $1"
}

log_error() {
    echo -e "${RED}[TROUBLESHOOT]${NC} $1"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}AWS Well-Architected Assessment Tool - 故障排除${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 檢查項目計數器
total_checks=0
passed_checks=0
failed_checks=0

check_item() {
    local description="$1"
    local command="$2"
    
    ((total_checks++))
    echo -n "檢查 $description... "
    
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✅ 通過${NC}"
        ((passed_checks++))
        return 0
    else
        echo -e "${RED}❌ 失敗${NC}"
        ((failed_checks++))
        return 1
    fi
}

# 1. 檢查基本環境
log_info "檢查基本環境..."

check_item "Bash 版本" "bash --version | head -1"
check_item "jq 工具" "command -v jq"
check_item "Python3" "command -v python3"
check_item "AWS CLI" "command -v aws"

# 2. 檢查 AWS 配置
log_info "檢查 AWS 配置..."

check_item "AWS 憑證" "aws sts get-caller-identity"
check_item "AWS 區域設定" "aws configure get region"

# 3. 檢查文件權限
log_info "檢查文件權限..."

check_item "主評估腳本權限" "test -x scripts/wa-assessment.sh"
check_item "配置腳本權限" "test -x config/aws-config.sh"

# 檢查支柱腳本權限
pillar_scripts=(
    "scripts/pillars/operational-excellence.sh"
    "scripts/pillars/security.sh"
    "scripts/pillars/reliability.sh"
    "scripts/pillars/performance-efficiency.sh"
    "scripts/pillars/cost-optimization.sh"
    "scripts/pillars/sustainability.sh"
)

for script in "${pillar_scripts[@]}"; do
    if [[ -f "$script" ]]; then
        check_item "$(basename "$script") 權限" "test -x $script"
    fi
done

# 4. 檢查目錄結構
log_info "檢查目錄結構..."

required_dirs=(
    "scripts"
    "scripts/pillars"
    "config"
    "templates"
    "docs"
)

for dir in "${required_dirs[@]}"; do
    check_item "$dir 目錄" "test -d $dir"
done

# 5. 檢查必要文件
log_info "檢查必要文件..."

required_files=(
    "scripts/wa-assessment.sh"
    "scripts/generate-report.sh"
    "config/aws-config.sh"
    "README.md"
)

for file in "${required_files[@]}"; do
    check_item "$file 文件" "test -f $file"
done

# 6. 檢查 AWS 權限
log_info "檢查 AWS 權限..."

aws_permissions=(
    "ec2:DescribeInstances"
    "iam:ListUsers"
    "s3:ListAllMyBuckets"
)

for perm in "${aws_permissions[@]}"; do
    service=$(echo "$perm" | cut -d':' -f1)
    action=$(echo "$perm" | cut -d':' -f2)
    
    case "$service" in
        "ec2")
            check_item "EC2 讀取權限" "aws ec2 describe-instances --max-items 1"
            ;;
        "iam")
            check_item "IAM 讀取權限" "aws iam list-users --max-items 1"
            ;;
        "s3")
            check_item "S3 讀取權限" "aws s3api list-buckets"
            ;;
    esac
done

# 7. 檢查網路連接
log_info "檢查網路連接..."

check_item "AWS API 連接" "aws sts get-caller-identity"

# 顯示結果摘要
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}檢查結果摘要${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "總檢查項目: $total_checks"
echo -e "通過: ${GREEN}$passed_checks${NC}"
echo -e "失敗: ${RED}$failed_checks${NC}"

if [[ $failed_checks -eq 0 ]]; then
    echo
    log_success "所有檢查都通過！系統已準備好執行評估。"
    echo
    echo "建議執行順序:"
    echo "  1. ./scripts/wa-assessment.sh"
    echo "  2. 查看 reports/ 目錄中的報告"
else
    echo
    log_warning "發現 $failed_checks 個問題需要解決。"
    echo
    echo "常見解決方案:"
    echo
    
    if ! command -v jq &>/dev/null; then
        echo "安裝 jq:"
        echo "  # macOS"
        echo "  brew install jq"
        echo "  # Ubuntu/Debian"
        echo "  sudo apt-get install jq"
        echo
    fi
    
    if ! command -v aws &>/dev/null; then
        echo "安裝 AWS CLI:"
        echo "  # macOS"
        echo "  brew install awscli"
        echo "  # 或參考: https://aws.amazon.com/cli/"
        echo
    fi
    
    if ! aws sts get-caller-identity &>/dev/null; then
        echo "配置 AWS 憑證:"
        echo "  aws configure"
        echo
    fi
    
    if [[ ! -x "scripts/wa-assessment.sh" ]]; then
        echo "設定腳本權限:"
        echo "  ./setup-permissions.sh"
        echo "  # 或手動設定"
        echo "  chmod +x scripts/*.sh scripts/pillars/*.sh config/*.sh"
        echo
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 如果有失敗項目，退出碼為 1
if [[ $failed_checks -gt 0 ]]; then
    exit 1
fi