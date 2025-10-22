#!/bin/bash

# 成本優化檢查結果分析工具

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
    echo -e "${BLUE}[COST-ANALYZE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[COST-ANALYZE]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[COST-ANALYZE]${NC} $1"
}

log_error() {
    echo -e "${RED}[COST-ANALYZE]${NC} $1"
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
    log_error "文件不存在: $DETAILED_FILE"
    exit 1
fi

log_info "分析成本優化檢查結果: $DETAILED_FILE"

# 統計總覽
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}💰 成本優化檢查結果統計總覽${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOTAL=$(wc -l < "$DETAILED_FILE" | tr -d ' ')
HIGH=$(grep '"severity":"HIGH"' "$DETAILED_FILE" | wc -l | tr -d ' ')
MEDIUM=$(grep '"severity":"MEDIUM"' "$DETAILED_FILE" | wc -l | tr -d ' ')
LOW=$(grep '"severity":"LOW"' "$DETAILED_FILE" | wc -l | tr -d ' ')

FAIL=$(grep '"status":"FAIL"' "$DETAILED_FILE" | wc -l | tr -d ' ')
WARN=$(grep '"status":"WARN"' "$DETAILED_FILE" | wc -l | tr -d ' ')
OK=$(grep '"status":"OK"' "$DETAILED_FILE" | wc -l | tr -d ' ')
INFO=$(grep '"status":"INFO"' "$DETAILED_FILE" | wc -l | tr -d ' ')

echo "總檢查項目: $TOTAL"
echo
echo "按成本影響分類:"
echo -e "  ${RED}高成本影響 (HIGH): $HIGH${NC}"
echo -e "  ${YELLOW}中成本影響 (MEDIUM): $MEDIUM${NC}"
echo -e "  ${GREEN}低成本影響 (LOW): $LOW${NC}"
echo
echo "按狀態分類:"
echo -e "  ${RED}需要處理 (FAIL): $FAIL${NC}"
echo -e "  ${YELLOW}建議優化 (WARN): $WARN${NC}"
echo -e "  ${GREEN}狀態良好 (OK): $OK${NC}"
echo -e "  ${BLUE}資訊參考 (INFO): $INFO${NC}"

# 立即節省機會
if [[ $FAIL -gt 0 ]]; then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${RED}💸 立即節省機會 (可立即處理)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 未使用的 EBS 磁碟區
    EBS_UNUSED=$(grep '"check":"EBS:Unused"' "$DETAILED_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')
    if [[ $EBS_UNUSED -gt 0 ]]; then
        echo -e "${RED}🔴 未附加的 EBS 磁碟區: $EBS_UNUSED 個${NC}"
        grep '"check":"EBS:Unused"' "$DETAILED_FILE" | grep '"status":"FAIL"' | jq -r '"  💾 " + .resource + " - " + .details' | head -5
        [[ $EBS_UNUSED -gt 5 ]] && echo "  ... 還有 $((EBS_UNUSED - 5)) 個"
        echo
    fi
    
    # 未關聯的 Elastic IP
    EIP_UNUSED=$(grep '"check":"EIP:Unattached"' "$DETAILED_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')
    if [[ $EIP_UNUSED -gt 0 ]]; then
        echo -e "${RED}🔴 未關聯的 Elastic IP: $EIP_UNUSED 個${NC}"
        grep '"check":"EIP:Unattached"' "$DETAILED_FILE" | grep '"status":"FAIL"' | jq -r '"  🌐 " + .resource + " - " + .details' | head -5
        [[ $EIP_UNUSED -gt 5 ]] && echo "  ... 還有 $((EIP_UNUSED - 5)) 個"
        echo
    fi
    
    # 計算預估節省
    echo -e "${CYAN}💡 預估每月節省:${NC}"
    if [[ $EBS_UNUSED -gt 0 ]]; then
        echo "  💾 EBS 磁碟區: 約 \$$(( EBS_UNUSED * 10 )) USD/月 (假設平均 100GB gp3)"
    fi
    if [[ $EIP_UNUSED -gt 0 ]]; then
        echo "  🌐 Elastic IP: 約 \$$(( EIP_UNUSED * 4 )) USD/月"
    fi
fi

# 優化建議
if [[ $WARN -gt 0 ]]; then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}⚡ 成本優化建議${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # gp2 到 gp3 遷移
    GP2_COUNT=$(grep '"check":"EBS:gp2"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $GP2_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📀 EBS gp2 → gp3 遷移機會: $GP2_COUNT 個磁碟區${NC}"
        echo "  💰 預估節省: 約 20% 儲存成本"
        echo
    fi
    
    # Savings Plan 候選
    SP_COUNT=$(grep '"check":"EC2:SavingsPlanCandidate"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $SP_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}💳 Savings Plan 候選: $SP_COUNT 個長期運行實例${NC}"
        echo "  💰 預估節省: 最高 72% EC2 成本"
        echo
    fi
    
    # S3 生命週期
    S3_LC_COUNT=$(grep '"check":"S3:Lifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $S3_LC_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🪣 S3 生命週期政策缺失: $S3_LC_COUNT 個儲存桶${NC}"
        echo "  💰 預估節省: 30-80% 儲存成本 (透過 IA/Glacier)"
        echo
    fi
    
    # CloudWatch Logs 保留
    CW_LOGS_COUNT=$(grep '"check":"CWLogs:Retention"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $CW_LOGS_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📊 CloudWatch Logs 無保留期限: $CW_LOGS_COUNT 個日誌群組${NC}"
        echo "  💰 預估節省: 避免無限制的日誌儲存成本"
        echo
    fi
    
    # Lambda 記憶體過大
    LAMBDA_MEM_COUNT=$(grep '"check":"Lambda:OversizedMemory"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $LAMBDA_MEM_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🧠 Lambda 記憶體可能過大: $LAMBDA_MEM_COUNT 個函數${NC}"
        echo "  💰 預估節省: 調整記憶體配置可節省 10-30% 成本"
        echo
    fi
    
    # ASG 過度佈署
    ASG_OVER_COUNT=$(grep '"check":"ASG:OverProvision"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $ASG_OVER_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📈 Auto Scaling Group 過度佈署: $ASG_OVER_COUNT 個群組${NC}"
        echo "  💰 預估節省: 調整 ASG 配置可節省 15-25% EC2 成本"
        echo
    fi
    
    # EKS NodeGroup 右調大小
    EKS_NG_COUNT=$(grep '"check":"EKS:NodeGroupRightsize"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $EKS_NG_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}☸️  EKS NodeGroup 可縮容: $EKS_NG_COUNT 個節點群組${NC}"
        echo "  💰 預估節省: 調整節點數量可節省 20-40% EKS 成本"
        echo
    fi
    
    # RDS 低 CPU 使用率
    RDS_LOW_CPU_COUNT=$(grep '"check":"RDS:LowCPU"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $RDS_LOW_CPU_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🗄️  RDS 低 CPU 使用率: $RDS_LOW_CPU_COUNT 個資料庫${NC}"
        echo "  💰 預估節省: 調整實例大小可節省 30-50% RDS 成本"
        echo
    fi
    
    # RDS 舊快照
    RDS_OLD_SNAP_COUNT=$(grep '"check":"RDS:OldSnapshot"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $RDS_OLD_SNAP_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📸 RDS 舊快照: $RDS_OLD_SNAP_COUNT 個快照${NC}"
        echo "  💰 預估節省: 刪除舊快照可節省儲存成本"
        echo
    fi
    
    # DynamoDB 閒置表
    DDB_IDLE_COUNT=$(grep '"check":"DDB:Idle"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $DDB_IDLE_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📊 DynamoDB 閒置表: $DDB_IDLE_COUNT 個表${NC}"
        echo "  💰 預估節省: 切換到 On-Demand 或刪除未使用的表"
        echo
    fi
    
    # DynamoDB 無 Auto Scaling
    DDB_NO_AS_COUNT=$(grep '"check":"DDB:NoAutoScaling"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $DDB_NO_AS_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}⚙️  DynamoDB 無 Auto Scaling: $DDB_NO_AS_COUNT 個表${NC}"
        echo "  💰 預估節省: 啟用 Auto Scaling 或切換到 On-Demand"
        echo
    fi
    
    # CloudFront 價格等級
    CF_PRICE_COUNT=$(grep '"check":"NET:CloudFrontPriceClass"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $CF_PRICE_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🌍 CloudFront 價格等級過高: $CF_PRICE_COUNT 個分發${NC}"
        echo "  💰 預估節省: 調整價格等級可節省 20-50% CloudFront 成本"
        echo
    fi
    
    # NLB 閒置
    NLB_IDLE_COUNT=$(grep '"check":"NET:NLBIdle"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $NLB_IDLE_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}⚖️  閒置的 NLB: $NLB_IDLE_COUNT 個${NC}"
        echo "  💰 預估節省: 刪除未使用的 NLB 可節省每小時成本"
        echo
    fi
    
    # VPC Endpoint 私有 DNS
    VPCE_DNS_COUNT=$(grep '"check":"NET:VPCEInterfacePrivateDNS"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $VPCE_DNS_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🔗 VPC Endpoint 私有 DNS 未啟用: $VPCE_DNS_COUNT 個${NC}"
        echo "  💰 預估節省: 啟用私有 DNS 可減少 NAT Gateway 流量成本"
        echo
    fi
    
    # CloudWatch Logs 無保留期
    CW_NO_RETENTION_COUNT=$(grep '"check":"CW:NoRetention"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $CW_NO_RETENTION_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📊 CloudWatch Logs 無保留期: $CW_NO_RETENTION_COUNT 個日誌群組${NC}"
        echo "  💰 預估節省: 設定保留期可避免無限制儲存成本"
        echo
    fi
    
    # CloudWatch Logs 長保留期
    CW_LONG_RETENTION_COUNT=$(grep '"check":"CW:LongRetention"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $CW_LONG_RETENTION_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📅 CloudWatch Logs 保留期過長: $CW_LONG_RETENTION_COUNT 個日誌群組${NC}"
        echo "  💰 預估節省: 縮短保留期可節省儲存成本"
        echo
    fi
    
    # Kinesis 高成本配置
    KINESIS_HIGH_COUNT=$(grep '"check":"Kinesis:ProvisionedHigh"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $KINESIS_HIGH_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🌊 Kinesis 高 Shard 數量: $KINESIS_HIGH_COUNT 個串流${NC}"
        echo "  💰 預估節省: 切換到 On-Demand 或調整 Shard 數量"
        echo
    fi
    
    # CloudWatch 過多 Alarms
    CW_TOO_MANY_ALARMS_COUNT=$(grep '"check":"CW:TooManyAlarms"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $CW_TOO_MANY_ALARMS_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🚨 CloudWatch Alarms 過多: $CW_TOO_MANY_ALARMS_COUNT 個區域${NC}"
        echo "  💰 預估節省: 整合或清理不必要的 Alarms"
        echo
    fi
    
    # NLB 跨 AZ 資料傳輸風險
    NLB_INTERAZ_COUNT=$(grep '"check":"DT:NLBInterAZRisk"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $NLB_INTERAZ_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}⚖️  NLB 跨 AZ 資料傳輸風險: $NLB_INTERAZ_COUNT 個${NC}"
        echo "  💰 預估節省: 關閉 Cross-Zone 或調整目標分佈"
        echo
    fi
    
    # S3 跨區複寫
    S3_CRR_COUNT=$(grep '"check":"DT:S3CRR"' "$DETAILED_FILE" | wc -l | tr -d ' ')
    if [[ $S3_CRR_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🪣 S3 跨區複寫: $S3_CRR_COUNT 個儲存桶${NC}"
        echo "  💰 預估成本: 跨區資料傳輸費用 (檢查必要性)"
        echo
    fi
    
    # S3 生命週期政策缺失 (更新版本)
    S3_NO_LC_COUNT=$(grep '"check":"S3:Lifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $S3_NO_LC_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}🪣 S3 無生命週期政策: $S3_NO_LC_COUNT 個儲存桶${NC}"
        echo "  💰 預估節省: 30-80% 儲存成本 (透過 IA/Glacier)"
        echo
    fi
    
    # S3 版本控制但無生命週期
    S3_VER_NO_LC_COUNT=$(grep '"check":"S3:VersioningNoLC"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $S3_VER_NO_LC_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📚 S3 版本控制無清理規則: $S3_VER_NO_LC_COUNT 個儲存桶${NC}"
        echo "  💰 預估節省: 清理舊版本可大幅降低儲存成本"
        echo
    fi
    
    # EBS 未掛載磁碟區
    EBS_UNATTACHED_COUNT=$(grep '"check":"EBS:UnattachedVolume"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $EBS_UNATTACHED_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}💾 EBS 未掛載磁碟區: $EBS_UNATTACHED_COUNT 個${NC}"
        echo "  💰 預估節省: 刪除未使用磁碟區可立即節省成本"
        echo
    fi
    
    # EBS 舊快照
    EBS_OLD_SNAP_COUNT=$(grep '"check":"EBS:OldSnapshot"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $EBS_OLD_SNAP_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📸 EBS 舊快照: $EBS_OLD_SNAP_COUNT 個${NC}"
        echo "  💰 預估節省: 歸檔或刪除舊快照可節省儲存成本"
        echo
    fi
    
    # EFS 無生命週期政策
    EFS_NO_LC_COUNT=$(grep '"check":"EFS:NoLifecycle"' "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    if [[ $EFS_NO_LC_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📁 EFS 無生命週期政策: $EFS_NO_LC_COUNT 個檔案系統${NC}"
        echo "  💰 預估節省: 啟用 IA/Archive 可節省 85% 儲存成本"
        echo
    fi
fi

# 按服務分組統計
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}📊 按 AWS 服務分組統計${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 統計各服務的檢查項目
declare -A service_stats
while IFS= read -r line; do
    check=$(echo "$line" | jq -r '.check')
    status=$(echo "$line" | jq -r '.status')
    
    # 從檢查名稱提取服務名稱
    service=$(echo "$check" | cut -d':' -f1)
    
    # 初始化統計
    if [[ -z "${service_stats[$service]:-}" ]]; then
        service_stats[$service]="0:0:0:0"  # total:fail:warn:info
    fi
    
    # 更新統計
    IFS=':' read -r total fail warn info <<< "${service_stats[$service]}"
    ((total++))
    case "$status" in
        "FAIL") ((fail++));;
        "WARN") ((warn++));;
        "INFO") ((info++));;
    esac
    service_stats[$service]="$total:$fail:$warn:$info"
done < "$DETAILED_FILE"

# 顯示服務統計
for service in $(printf '%s\n' "${!service_stats[@]}" | sort); do
    IFS=':' read -r total fail warn info <<< "${service_stats[$service]}"
    
    status_info=""
    [[ $fail -gt 0 ]] && status_info="${status_info}${RED}失敗:$fail${NC} "
    [[ $warn -gt 0 ]] && status_info="${status_info}${YELLOW}警告:$warn${NC} "
    [[ $info -gt 0 ]] && status_info="${status_info}${BLUE}資訊:$info${NC} "
    
    # 服務圖示
    case "$service" in
        "EC2") icon="🖥️ ";;
        "EBS") icon="💾 ";;
        "S3") icon="🪣 ";;
        "RDS") icon="🗄️ ";;
        "Lambda") icon="⚡ ";;
        "EIP") icon="🌐 ";;
        "CF") icon="🌍 ";;
        "ALB"|"NLB") icon="⚖️ ";;
        "DDB") icon="📊 ";;
        "ECR") icon="📦 ";;
        "NAT") icon="🔀 ";;
        "CWLogs") icon="📋 ";;
        "ASG") icon="📈 ";;
        "EKS") icon="☸️ ";;
        "RDS") icon="🗄️ ";;
        "DDB") icon="📊 ";;
        "NET") icon="🌐 ";;
        "EFS") icon="📁 ";;
        "CW") icon="📊 ";;
        "Kinesis") icon="🌊 ";;
        "DT") icon="🔄 ";;
        *) icon="🔧 ";;
    esac
    
    echo -e "  $icon$service: $total 項檢查 $status_info"
done

# 按區域分組統計
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${PURPLE}🌍 按區域分組統計${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

jq -r '.region' "$DETAILED_FILE" | sort | uniq -c | sort -nr | while read -r count region; do
    fail_count=$(grep "\"region\":\"$region\"" "$DETAILED_FILE" | grep '"status":"FAIL"' | wc -l | tr -d ' ')
    warn_count=$(grep "\"region\":\"$region\"" "$DETAILED_FILE" | grep '"status":"WARN"' | wc -l | tr -d ' ')
    
    status_info=""
    [[ $fail_count -gt 0 ]] && status_info="${status_info}${RED}需處理:$fail_count${NC} "
    [[ $warn_count -gt 0 ]] && status_info="${status_info}${YELLOW}可優化:$warn_count${NC} "
    
    echo -e "  🌍 $region: $count 項檢查 $status_info"
done

# 優先處理建議
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}🎯 優先處理建議 (按成本影響排序)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "1. 🔴 立即處理 - 直接成本浪費:"
echo "   • 刪除未使用的 EBS 磁碟區"
echo "   • 釋放未關聯的 Elastic IP"
echo

echo "2. 🟠 短期優化 - 顯著節省:"
echo "   • 將 EBS gp2 遷移到 gp3"
echo "   • 為長期運行實例購買 Savings Plans"
echo "   • 設定 S3 生命週期政策"
echo

echo "3. 🟡 中期優化 - 持續節省:"
echo "   • 評估 Graviton 處理器遷移"
echo "   • 優化 DynamoDB 計費模式"
echo "   • 檢查 Lambda 預配置並發"
echo

echo "4. 🟢 長期優化 - 架構改進:"
echo "   • 檢查 CloudFront 價格等級"
echo "   • 評估 NAT Gateway 替代方案"
echo "   • 設定 CloudWatch Logs 保留政策"

# 成本節省計算器
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}💰 預估成本節省計算器${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total_monthly_savings=0

# EBS 未使用磁碟區節省
if [[ $EBS_UNUSED -gt 0 ]]; then
    ebs_savings=$((EBS_UNUSED * 10))
    total_monthly_savings=$((total_monthly_savings + ebs_savings))
    echo "💾 刪除未使用 EBS 磁碟區: ~\$${ebs_savings} USD/月"
fi

# Elastic IP 節省
if [[ $EIP_UNUSED -gt 0 ]]; then
    eip_savings=$((EIP_UNUSED * 4))
    total_monthly_savings=$((total_monthly_savings + eip_savings))
    echo "🌐 釋放未關聯 Elastic IP: ~\$${eip_savings} USD/月"
fi

# gp2 到 gp3 節省
if [[ $GP2_COUNT -gt 0 ]]; then
    gp2_savings=$((GP2_COUNT * 2))
    total_monthly_savings=$((total_monthly_savings + gp2_savings))
    echo "📀 EBS gp2→gp3 遷移: ~\$${gp2_savings} USD/月"
fi

# Lambda 記憶體優化節省
if [[ $LAMBDA_MEM_COUNT -gt 0 ]]; then
    lambda_savings=$((LAMBDA_MEM_COUNT * 5))
    total_monthly_savings=$((total_monthly_savings + lambda_savings))
    echo "🧠 Lambda 記憶體優化: ~\$${lambda_savings} USD/月"
fi

# ASG 優化節省
if [[ $ASG_OVER_COUNT -gt 0 ]]; then
    asg_savings=$((ASG_OVER_COUNT * 50))
    total_monthly_savings=$((total_monthly_savings + asg_savings))
    echo "📈 ASG 配置優化: ~\$${asg_savings} USD/月"
fi

# RDS 優化節省
if [[ $RDS_LOW_CPU_COUNT -gt 0 ]]; then
    rds_savings=$((RDS_LOW_CPU_COUNT * 80))
    total_monthly_savings=$((total_monthly_savings + rds_savings))
    echo "🗄️  RDS 實例調整: ~\$${rds_savings} USD/月"
fi

# RDS 快照清理節省
if [[ $RDS_OLD_SNAP_COUNT -gt 0 ]]; then
    snap_savings=$((RDS_OLD_SNAP_COUNT * 5))
    total_monthly_savings=$((total_monthly_savings + snap_savings))
    echo "📸 RDS 快照清理: ~\$${snap_savings} USD/月"
fi

# DynamoDB 優化節省
if [[ $DDB_IDLE_COUNT -gt 0 ]]; then
    ddb_savings=$((DDB_IDLE_COUNT * 20))
    total_monthly_savings=$((total_monthly_savings + ddb_savings))
    echo "📊 DynamoDB 優化: ~\$${ddb_savings} USD/月"
fi

# CloudFront 價格等級優化
if [[ $CF_PRICE_COUNT -gt 0 ]]; then
    cf_savings=$((CF_PRICE_COUNT * 30))
    total_monthly_savings=$((total_monthly_savings + cf_savings))
    echo "🌍 CloudFront 價格等級: ~\$${cf_savings} USD/月"
fi

# NLB 閒置清理
if [[ $NLB_IDLE_COUNT -gt 0 ]]; then
    nlb_savings=$((NLB_IDLE_COUNT * 25))
    total_monthly_savings=$((total_monthly_savings + nlb_savings))
    echo "⚖️  閒置 NLB 清理: ~\$${nlb_savings} USD/月"
fi

# CloudWatch Logs 保留期優化
if [[ $CW_NO_RETENTION_COUNT -gt 0 ]]; then
    cw_savings=$((CW_NO_RETENTION_COUNT * 10))
    total_monthly_savings=$((total_monthly_savings + cw_savings))
    echo "📊 CloudWatch Logs 保留期: ~\$${cw_savings} USD/月"
fi

# Kinesis 優化
if [[ $KINESIS_HIGH_COUNT -gt 0 ]]; then
    kinesis_savings=$((KINESIS_HIGH_COUNT * 40))
    total_monthly_savings=$((total_monthly_savings + kinesis_savings))
    echo "🌊 Kinesis 配置優化: ~\$${kinesis_savings} USD/月"
fi

# EBS 未掛載磁碟區清理
if [[ $EBS_UNATTACHED_COUNT -gt 0 ]]; then
    ebs_unattached_savings=$((EBS_UNATTACHED_COUNT * 8))
    total_monthly_savings=$((total_monthly_savings + ebs_unattached_savings))
    echo "💾 EBS 未掛載磁碟區: ~\$${ebs_unattached_savings} USD/月"
fi

# EBS 舊快照清理
if [[ $EBS_OLD_SNAP_COUNT -gt 0 ]]; then
    ebs_snap_savings=$((EBS_OLD_SNAP_COUNT * 3))
    total_monthly_savings=$((total_monthly_savings + ebs_snap_savings))
    echo "📸 EBS 舊快照清理: ~\$${ebs_snap_savings} USD/月"
fi

# S3 生命週期優化
if [[ $S3_NO_LC_COUNT -gt 0 ]]; then
    s3_lc_savings=$((S3_NO_LC_COUNT * 40))
    total_monthly_savings=$((total_monthly_savings + s3_lc_savings))
    echo "🪣 S3 生命週期優化: ~\$${s3_lc_savings} USD/月"
fi

# EFS 生命週期優化
if [[ $EFS_NO_LC_COUNT -gt 0 ]]; then
    efs_lc_savings=$((EFS_NO_LC_COUNT * 30))
    total_monthly_savings=$((total_monthly_savings + efs_lc_savings))
    echo "📁 EFS 生命週期優化: ~\$${efs_lc_savings} USD/月"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}💵 預估總節省: ~\$${total_monthly_savings} USD/月${NC}"
echo -e "${GREEN}💵 預估年節省: ~\$$((total_monthly_savings * 12)) USD/年${NC}"

if [[ $SP_COUNT -gt 0 ]]; then
    echo
    echo -e "${YELLOW}📈 額外節省機會:${NC}"
    echo "   Savings Plans 可額外節省高達 72% 的 EC2 成本"
    echo "   S3 生命週期政策可節省 30-80% 的儲存成本"
fi

echo
log_success "成本優化分析完成"
echo "詳細結果請參考: $DETAILED_FILE"

# 生成行動計畫
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}📋 建議行動計畫${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "第一週:"
echo "  ✅ 刪除所有未使用的 EBS 磁碟區"
echo "  ✅ 釋放所有未關聯的 Elastic IP"
echo

echo "第二週:"
echo "  ✅ 開始 EBS gp2 到 gp3 的遷移計畫"
echo "  ✅ 為重要 S3 儲存桶設定生命週期政策"
echo

echo "第三週:"
echo "  ✅ 分析長期運行的 EC2 實例，規劃 Savings Plans"
echo "  ✅ 設定 CloudWatch Logs 保留政策"
echo "  ✅ 檢查 Lambda 函數記憶體配置"
echo

echo "第四週:"
echo "  ✅ 優化 Auto Scaling Group 配置"
echo "  ✅ 檢查 EKS NodeGroup 縮容機會"
echo "  ✅ 建立定期成本檢查流程"