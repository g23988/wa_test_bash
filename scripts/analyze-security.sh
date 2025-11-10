#!/bin/bash

# 安全檢查結果分析工具

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[ANALYZE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[ANALYZE]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ANALYZE]${NC} $1"
}

log_error() {
    echo -e "${RED}[ANALYZE]${NC} $1"
}

# 使用方式
usage() {
    echo "使用方式: $0 <security_detailed_TIMESTAMP.jsonl>"
    echo "範例: $0 reports/security_detailed_20241016_143022.jsonl"
    exit 1
}

# 檢查參數
if [[ $# -ne 1 ]]; then
    usage
fi

DETAILED_FILE="$1"

if [[ ! -f "$DETAILED_FILE" ]]; then
    log_error "文件不存在: $DETAILED_FILE"
    exit 1
fi

log_info "分析安全檢查結果: $DETAILED_FILE"

# 統計總覽
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}安全檢查結果統計總覽${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOTAL=$(wc -l < "$DETAILED_FILE" | tr -d ' ')
CRITICAL=$(grep '"severity":"CRITICAL"' "$DETAILED_FILE" | wc -l | tr -d ' ')
HIGH=$(grep '"severity":"HIGH"' "$DETAILED_FILE" | wc -l | tr -d ' ')
MEDIUM=$(grep '"severity":"MEDIUM"' "$DETAILED_FILE" | wc -l | tr -d ' ')
LOW=$(grep '"severity":"LOW"' "$DETAILED_FILE" | wc -l | tr -d ' ')

FAIL=$(grep '"status":"FAIL"' "$DETAILED_FILE" | wc -l | tr -d ' ')
WARN=$(grep '"status":"WARN"' "$DETAILED_FILE" | wc -l | tr -d ' ')
OK=$(grep '"status":"OK"' "$DETAILED_FILE" | wc -l | tr -d ' ')
INFO=$(grep '"status":"INFO"' "$DETAILED_FILE" | wc -l | tr -d ' ')

echo "總檢查項目: $TOTAL"
echo
echo "按嚴重程度分類:"
echo -e "  ${RED}嚴重 (CRITICAL): $CRITICAL${NC}"
echo -e "  ${YELLOW}高風險 (HIGH): $HIGH${NC}"
echo -e "  ${BLUE}中風險 (MEDIUM): $MEDIUM${NC}"
echo -e "  ${GREEN}低風險 (LOW): $LOW${NC}"
echo
echo "按狀態分類:"
echo -e "  ${RED}失敗 (FAIL): $FAIL${NC}"
echo -e "  ${YELLOW}警告 (WARN): $WARN${NC}"
echo -e "  ${GREEN}正常 (OK): $OK${NC}"
echo -e "  ${BLUE}資訊 (INFO): $INFO${NC}"

# 嚴重和高風險問題詳情
if [[ $CRITICAL -gt 0 || $FAIL -gt 0 ]]; then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${RED}🚨 需要立即處理的問題${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 嚴重問題
    if [[ $CRITICAL -gt 0 ]]; then
        echo -e "${RED}嚴重問題:${NC}"
        grep '"severity":"CRITICAL"' "$DETAILED_FILE" | jq -r '"  ❌ " + .check + ": " + .resource + " - " + .details'
        echo
    fi
    
    # 失敗的檢查
    echo -e "${RED}失敗的檢查:${NC}"
    grep '"status":"FAIL"' "$DETAILED_FILE" | jq -r '"  ❌ " + .check + ": " + .resource + " (" + .region + ") - " + .details'
fi

# 警告問題
if [[ $WARN -gt 0 ]]; then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}⚠️  需要關注的警告${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    grep '"status":"WARN"' "$DETAILED_FILE" | jq -r '"  ⚠️  " + .check + ": " + .resource + " (" + .region + ") - " + .details'
fi

# 按檢查類型分組統計
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}按檢查類型分組統計${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

jq -r '.check' "$DETAILED_FILE" | sort | uniq -c | sort -nr | while read -r count check; do
    fail_count=$(grep "\"check\":\"$check\"" "$DETAILED_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')
    warn_count=$(grep "\"check\":\"$check\"" "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    
    status_info=""
    if [[ $fail_count -gt 0 ]]; then
        status_info="${status_info}${RED}失敗:$fail_count${NC} "
    fi
    if [[ $warn_count -gt 0 ]]; then
        status_info="${status_info}${YELLOW}警告:$warn_count${NC} "
    fi
    
    echo -e "  $check: $count 項檢查 $status_info"
done

# 按區域分組統計
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}按區域分組統計${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

jq -r '.region' "$DETAILED_FILE" | sort | uniq -c | sort -nr | while read -r count region; do
    fail_count=$(grep "\"region\":\"$region\"" "$DETAILED_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')
    warn_count=$(grep "\"region\":\"$region\"" "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    
    status_info=""
    if [[ $fail_count -gt 0 ]]; then
        status_info="${status_info}${RED}失敗:$fail_count${NC} "
    fi
    if [[ $warn_count -gt 0 ]]; then
        status_info="${status_info}${YELLOW}警告:$warn_count${NC} "
    fi
    
    echo -e "  $region: $count 項檢查 $status_info"
done

# 建議優先處理順序
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 建議優先處理順序${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "1. 🔴 立即處理嚴重問題 (CRITICAL)"
echo "2. 🟠 處理高風險失敗項目 (HIGH + FAIL)"
echo "3. 🟡 檢視並處理警告項目 (WARN)"
echo "4. 🔵 檢視中風險問題 (MEDIUM)"
echo "5. 🟢 定期檢視低風險項目 (LOW)"

# 生成修復建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}🔧 主要修復建議${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 檢查常見問題並給出建議
if grep -q "Root MFA NOT enabled" "$DETAILED_FILE"; then
    echo "• 🚨 啟用 Root 帳戶 MFA (最高優先級)"
fi

if grep -q "User has NO MFA" "$DETAILED_FILE"; then
    echo "• 🔐 為所有 IAM 使用者啟用 MFA"
fi

if grep -q "Open 22/3389 to world" "$DETAILED_FILE"; then
    echo "• 🔒 修正開放管理埠的 Security Groups"
fi

if grep -q "Bucket policy is PUBLIC" "$DETAILED_FILE"; then
    echo "• 🪣 檢查並修正公開的 S3 儲存桶"
fi

if grep -q "No default encryption" "$DETAILED_FILE"; then
    echo "• 🔐 為 S3 儲存桶啟用預設加密"
fi

if grep -q "StorageEncrypted=false" "$DETAILED_FILE"; then
    echo "• 💾 為 RDS 執行個體啟用儲存加密"
fi

if grep -q "EBS.*Not enabled" "$DETAILED_FILE"; then
    echo "• 💿 啟用 EBS 預設加密"
fi

if grep -q "CloudTrail.*No trails" "$DETAILED_FILE"; then
    echo "• 📊 設定 CloudTrail 記錄"
fi

echo
log_success "安全檢查結果分析完成"
echo "詳細結果請參考: $DETAILED_FILE"