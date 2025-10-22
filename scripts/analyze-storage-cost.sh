#!/bin/bash

# 儲存成本分析工具
# 專注於 S3、EBS、EFS 的成本優化

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
    echo -e "${BLUE}[STORAGE-COST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[STORAGE-COST]${NC} $1"
}

# 使用方式
usage() {
    echo "使用方式: $0 <cost-optimization_detailed_TIMESTAMP.jsonl>"
    echo "範例: $0 reports/cost-optimization_detailed_20241016_143022.jsonl"
    exit 1
}

# 檢查參數
if [[ $# -ne 1 ]]; then
    usage
fi

DETAILED_FILE="$1"

if [[ ! -f "$DETAILED_FILE" ]]; then
    log_info "文件不存在: $DETAILED_FILE"
    exit 1
fi

log_info "分析儲存成本優化結果: $DETAILED_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}💾 儲存成本分析報告${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# S3 分析
echo
echo -e "${BLUE}🪣 S3 儲存分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

S3_BUCKET_COUNT=$(grep '"check":"S3:BucketCount"' "$DETAILED_FILE" | jq -r '.details' | grep -o 'count=[0-9]*' | cut -d'=' -f2 | head -1 || echo 0)
if [[ $S3_BUCKET_COUNT -gt 0 ]]; then
    echo -e "${BLUE}🪣 S3 儲存桶總數: $S3_BUCKET_COUNT 個${NC}"
    
    # 無生命週期政策
    S3_NO_LC=$(grep '"check":"S3:Lifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $S3_NO_LC -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  無生命週期政策: $S3_NO_LC 個儲存桶${NC}"
        grep '"check":"S3:Lifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' | jq -r '"  🪣 " + .resource' | head -5
        [[ $S3_NO_LC -gt 5 ]] && echo "  ... 還有 $((S3_NO_LC - 5)) 個"
        echo -e "  ${GREEN}💰 預估節省: ~\$$(( S3_NO_LC * 50 )) USD/月 (透過 IA/Glacier 轉換)${NC}"
        echo
    fi
    
    # 版本控制但無生命週期清理
    S3_VER_NO_LC=$(grep '"check":"S3:VersioningNoLC"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $S3_VER_NO_LC -gt 0 ]]; then
        echo -e "${RED}🚨 版本控制但無清理規則: $S3_VER_NO_LC 個儲存桶${NC}"
        grep '"check":"S3:VersioningNoLC"' "$DETAILED_FILE" | grep '"status":"WARN"' | jq -r '"  📚 " + .resource' | head -3
        echo "  建議: 立即設定生命週期規則清理舊版本"
        echo -e "  ${GREEN}💰 預估節省: ~\$$(( S3_VER_NO_LC * 100 )) USD/月 (清理舊版本)${NC}"
        echo
    fi
    
    # S3 儲存桶詳細資訊
    echo -e "${CYAN}📊 S3 儲存桶配置概覽:${NC}"
    grep '"check":"S3:BucketInfo"' "$DETAILED_FILE" | jq -r '"  🪣 " + .resource + " - " + .details' | head -10
    [[ $(grep '"check":"S3:BucketInfo"' "$DETAILED_FILE" | wc -l) -gt 10 ]] && echo "  ... 還有更多儲存桶"
    echo
else
    echo -e "${GREEN}✅ 未使用 S3 或未發現問題${NC}"
    echo
fi

# EBS 分析
echo
echo -e "${PURPLE}💾 EBS 儲存分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 未掛載磁碟區
EBS_UNATTACHED=$(grep '"check":"EBS:UnattachedVolume"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $EBS_UNATTACHED -gt 0 ]]; then
    echo -e "${RED}💸 未掛載的 EBS 磁碟區: $EBS_UNATTACHED 個${NC}"
    grep '"check":"EBS:UnattachedVolume"' "$DETAILED_FILE" | jq -r '"  💾 " + .resource + " (" + .region + ") - " + .details' | head -5
    [[ $EBS_UNATTACHED -gt 5 ]] && echo "  ... 還有 $((EBS_UNATTACHED - 5)) 個"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( EBS_UNATTACHED * 10 )) USD/月 (刪除未使用磁碟區)${NC}"
    echo
fi

# gp2 磁碟區
EBS_GP2=$(grep '"check":"EBS:gp2Storage"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $EBS_GP2 -gt 0 ]]; then
    echo -e "${YELLOW}📀 gp2 磁碟區: $EBS_GP2 個${NC}"
    echo "  建議: 遷移到 gp3 以獲得更好的性價比"
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( EBS_GP2 * 5 )) USD/月 (gp2→gp3 遷移)${NC}"
    echo
fi

# 舊快照
EBS_OLD_SNAP=$(grep '"check":"EBS:OldSnapshot"' "$DETAILED_FILE" | wc -l | tr -d ' ')
if [[ $EBS_OLD_SNAP -gt 0 ]]; then
    echo -e "${YELLOW}📸 舊 EBS 快照: $EBS_OLD_SNAP 個${NC}"
    
    # 按儲存層級分類
    STANDARD_SNAPS=$(grep '"check":"EBS:OldSnapshot"' "$DETAILED_FILE" | grep 'tier=standard' | wc -l | tr -d ' ')
    if [[ $STANDARD_SNAPS -gt 0 ]]; then
        echo -e "  📸 Standard 層級: $STANDARD_SNAPS 個 (建議歸檔到 Archive)"
    fi
    
    echo "詳細列表 (前5個):"
    grep '"check":"EBS:OldSnapshot"' "$DETAILED_FILE" | jq -r '"  📸 " + .resource + " (" + .region + ") - " + .details' | head -5
    echo -e "  ${GREEN}💰 預估節省: ~\$$(( EBS_OLD_SNAP * 4 )) USD/月 (歸檔或刪除)${NC}"
    echo
fi

if [[ $EBS_UNATTACHED -eq 0 && $EBS_GP2 -eq 0 && $EBS_OLD_SNAP -eq 0 ]]; then
    echo -e "${GREEN}✅ EBS 配置看起來已優化${NC}"
    echo
fi

# EFS 分析
echo
echo -e "${GREEN}📁 EFS 儲存分析${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EFS_NO_LC=$(grep '"check":"EFS:NoLifecycle"' "$DETAILED_FILE" | wc -l | tr -d ' ')
EFS_TOTAL=$(grep '"check":"EFS:Lifecycle\|EFS:NoLifecycle"' "$DETAILED_FILE" | wc -l | tr -d ' ')

if [[ $EFS_TOTAL -gt 0 ]]; then
    echo -e "${BLUE}📁 EFS 檔案系統總數: $EFS_TOTAL 個${NC}"
    
    if [[ $EFS_NO_LC -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  無生命週期政策: $EFS_NO_LC 個檔案系統${NC}"
        grep '"check":"EFS:NoLifecycle"' "$DETAILED_FILE" | jq -r '"  📁 " + .resource + " (" + .region + ")"' | head -5
        echo "  建議: 啟用 Intelligent-Tiering 或設定 IA/Archive 轉換"
        echo -e "  ${GREEN}💰 預估節省: ~\$$(( EFS_NO_LC * 40 )) USD/月 (85% 儲存成本節省)${NC}"
        echo
    else
        echo -e "${GREEN}✅ 所有 EFS 檔案系統都已配置生命週期政策${NC}"
        echo
    fi
    
    # 輸送量模式檢查
    EFS_PROVISIONED=$(grep '"check":"EFS:ThroughputMode"' "$DETAILED_FILE" | grep 'provisioned' | wc -l | tr -d ' ')
    if [[ $EFS_PROVISIONED -gt 0 ]]; then
        echo -e "${CYAN}⚡ 使用 Provisioned 輸送量模式: $EFS_PROVISIONED 個${NC}"
        echo "  建議: 檢查是否真的需要 Provisioned 模式"
        echo
    fi
else
    echo -e "${GREEN}✅ 未使用 EFS${NC}"
    echo
fi

# 儲存成本節省建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}💰 儲存成本節省建議${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_storage_savings=0

echo "立即行動項目 (高優先級):"
if [[ $EBS_UNATTACHED -gt 0 ]]; then
    ebs_unattached_savings=$((EBS_UNATTACHED * 10))
    total_storage_savings=$((total_storage_savings + ebs_unattached_savings))
    echo "  🗑️  刪除 $EBS_UNATTACHED 個未掛載 EBS 磁碟區: ~\$${ebs_unattached_savings} USD/月"
fi

if [[ $S3_VER_NO_LC -gt 0 ]]; then
    s3_ver_savings=$((S3_VER_NO_LC * 100))
    total_storage_savings=$((total_storage_savings + s3_ver_savings))
    echo "  📚 為 $S3_VER_NO_LC 個 S3 儲存桶設定版本清理: ~\$${s3_ver_savings} USD/月"
fi

echo
echo "短期優化 (1-2週):"
if [[ $S3_NO_LC -gt 0 ]]; then
    s3_lc_savings=$((S3_NO_LC * 50))
    total_storage_savings=$((total_storage_savings + s3_lc_savings))
    echo "  🪣 為 $S3_NO_LC 個 S3 儲存桶設定生命週期: ~\$${s3_lc_savings} USD/月"
fi

if [[ $EFS_NO_LC -gt 0 ]]; then
    efs_lc_savings=$((EFS_NO_LC * 40))
    total_storage_savings=$((total_storage_savings + efs_lc_savings))
    echo "  📁 為 $EFS_NO_LC 個 EFS 啟用生命週期: ~\$${efs_lc_savings} USD/月"
fi

echo
echo "中期優化 (1個月):"
if [[ $EBS_GP2 -gt 0 ]]; then
    ebs_gp2_savings=$((EBS_GP2 * 5))
    total_storage_savings=$((total_storage_savings + ebs_gp2_savings))
    echo "  📀 將 $EBS_GP2 個 EBS 遷移到 gp3: ~\$${ebs_gp2_savings} USD/月"
fi

if [[ $EBS_OLD_SNAP -gt 0 ]]; then
    ebs_snap_savings=$((EBS_OLD_SNAP * 4))
    total_storage_savings=$((total_storage_savings + ebs_snap_savings))
    echo "  📸 清理 $EBS_OLD_SNAP 個舊 EBS 快照: ~\$${ebs_snap_savings} USD/月"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}💵 儲存預估總節省: ~\$${total_storage_savings} USD/月${NC}"
echo -e "${CYAN}💵 年度節省: ~\$$((total_storage_savings * 12)) USD${NC}"

# 儲存成本最佳實務
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 儲存成本最佳實務${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "S3 最佳實務:"
echo "  ✅ 設定生命週期規則自動轉換到 IA/Glacier"
echo "  ✅ 啟用 Intelligent-Tiering 自動優化"
echo "  ✅ 為版本控制儲存桶設定舊版本清理"
echo "  ✅ 使用 S3 Storage Lens 分析使用模式"
echo "  ✅ 定期檢查並刪除不完整的多部分上傳"
echo

echo "EBS 最佳實務:"
echo "  ✅ 使用 gp3 而非 gp2 獲得更好性價比"
echo "  ✅ 定期檢查並刪除未使用的磁碟區"
echo "  ✅ 設定快照生命週期管理 (DLM)"
echo "  ✅ 將舊快照歸檔到 Archive 層級"
echo "  ✅ 監控磁碟區使用率，適時調整大小"
echo

echo "EFS 最佳實務:"
echo "  ✅ 啟用 Intelligent-Tiering 或手動設定 IA 轉換"
echo "  ✅ 使用 Archive 儲存類別處理冷資料"
echo "  ✅ 根據使用模式選擇適當的輸送量模式"
echo "  ✅ 定期檢查檔案存取模式"
echo "  ✅ 考慮使用 EFS One Zone 降低成本"

# 實施計畫
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 儲存成本優化實施計畫${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "第 1 週 - 立即清理:"
echo "  ✅ 刪除所有未掛載的 EBS 磁碟區"
echo "  ✅ 為有版本控制的 S3 儲存桶緊急設定清理規則"
echo

echo "第 2 週 - 生命週期配置:"
echo "  ✅ 為所有 S3 儲存桶設定適當的生命週期規則"
echo "  ✅ 為 EFS 檔案系統啟用 Intelligent-Tiering"
echo

echo "第 3 週 - 儲存類型優化:"
echo "  ✅ 規劃並執行 EBS gp2 到 gp3 遷移"
echo "  ✅ 設定 EBS 快照生命週期管理"
echo

echo "第 4 週 - 監控和自動化:"
echo "  ✅ 設定儲存成本警報和預算"
echo "  ✅ 建立定期儲存檢查和清理流程"
echo "  ✅ 實施自動化儲存優化工具"

log_success "儲存成本分析完成"
echo "建議每月執行此分析以持續優化儲存成本"