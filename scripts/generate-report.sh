#!/bin/bash

# 生成綜合報告腳本

ACCOUNT_ID=$1
REGION=$2
TIMESTAMP=$3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$PROJECT_ROOT/reports"
TEMPLATES_DIR="$PROJECT_ROOT/templates"

# 顏色定義
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[REPORT]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[REPORT]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[REPORT]${NC} $1"
}

# 綜合報告文件
SUMMARY_FILE="$REPORTS_DIR/wa-assessment-summary_${TIMESTAMP}.json"
HTML_REPORT="$REPORTS_DIR/wa-assessment-report_${TIMESTAMP}.html"

log_info "生成綜合報告..."

# 讀取安全檢查摘要
SECURITY_SUMMARY=""
if [[ -f "$REPORTS_DIR/security_${TIMESTAMP}.json" ]]; then
    SECURITY_SUMMARY=$(cat "$REPORTS_DIR/security_${TIMESTAMP}.json" | jq -r '.summary // empty')
fi

# 讀取成本優化摘要
COST_SUMMARY=""
if [[ -f "$REPORTS_DIR/cost-optimization_${TIMESTAMP}.json" ]]; then
    COST_SUMMARY=$(cat "$REPORTS_DIR/cost-optimization_${TIMESTAMP}.json" | jq -r '.summary // empty')
fi

# 創建 JSON 綜合報告
cat > "$SUMMARY_FILE" << EOF
{
  "assessment_summary": {
    "account_id": "$ACCOUNT_ID",
    "region": "$REGION",
    "timestamp": "$TIMESTAMP",
    "assessment_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "pillars": {
      "operational_excellence": {
        "status": "completed",
        "report_file": "operational-excellence_${TIMESTAMP}.json"
      },
      "security": {
        "status": "completed",
        "report_file": "security_${TIMESTAMP}.json",
        "detailed_file": "security_detailed_${TIMESTAMP}.jsonl",
        "summary": $SECURITY_SUMMARY
      },
      "reliability": {
        "status": "completed",
        "report_file": "reliability_${TIMESTAMP}.json"
      },
      "performance_efficiency": {
        "status": "completed",
        "report_file": "performance-efficiency_${TIMESTAMP}.json"
      },
      "cost_optimization": {
        "status": "completed",
        "report_file": "cost-optimization_${TIMESTAMP}.json",
        "detailed_file": "cost-optimization_detailed_${TIMESTAMP}.jsonl",
        "summary": $COST_SUMMARY
      },
      "sustainability": {
        "status": "completed",
        "report_file": "sustainability_${TIMESTAMP}.json"
      }
    },
    "overall_recommendations": [
      "定期執行 Well-Architected 評估",
      "實施自動化監控和警報",
      "建立災難復原計畫",
      "優化成本和效能",
      "加強安全性措施 (特別關注發現的安全問題)",
      "採用永續性最佳實務"
    ]
  }
}
EOF

# 生成 HTML 報告
log_info "生成 HTML 報告..."

cat > "$HTML_REPORT" << 'EOF'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS Well-Architected Assessment Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 0 20px rgba(0,0,0,0.1);
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
            padding-bottom: 20px;
            border-bottom: 3px solid #ff9900;
        }
        .header h1 {
            color: #232f3e;
            margin-bottom: 10px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .info-card {
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #ff9900;
        }
        .pillar-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .pillar-card {
            background-color: #fff;
            border: 1px solid #ddd;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .pillar-card h3 {
            color: #232f3e;
            margin-top: 0;
            padding-bottom: 10px;
            border-bottom: 2px solid #ff9900;
        }
        .status-completed {
            color: #28a745;
            font-weight: bold;
        }
        .recommendations {
            background-color: #e7f3ff;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #007bff;
        }
        .recommendations h3 {
            color: #232f3e;
            margin-top: 0;
        }
        .recommendations ul {
            margin: 0;
            padding-left: 20px;
        }
        .footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>AWS Well-Architected Framework</h1>
            <h2>6 Pillars Assessment Report</h2>
        </div>

        <div class="info-grid">
            <div class="info-card">
                <h4>AWS 帳戶</h4>
                <p>ACCOUNT_ID_PLACEHOLDER</p>
            </div>
            <div class="info-card">
                <h4>區域</h4>
                <p>REGION_PLACEHOLDER</p>
            </div>
            <div class="info-card">
                <h4>評估時間</h4>
                <p>TIMESTAMP_PLACEHOLDER</p>
            </div>
        </div>

        <div class="pillar-grid">
            <div class="pillar-card">
                <h3>🔧 Operational Excellence</h3>
                <p><strong>營運卓越</strong></p>
                <p>狀態: <span class="status-completed">已完成</span></p>
                <p>專注於運行和監控系統，持續改進流程和程序。</p>
            </div>

            <div class="pillar-card">
                <h3>🔒 Security</h3>
                <p><strong>安全性</strong></p>
                <p>狀態: <span class="status-completed">已完成</span></p>
                <p>保護資訊和系統，透過風險評估和緩解策略。</p>
            </div>

            <div class="pillar-card">
                <h3>🛡️ Reliability</h3>
                <p><strong>可靠性</strong></p>
                <p>狀態: <span class="status-completed">已完成</span></p>
                <p>確保工作負載執行其預期功能，並從故障中快速恢復。</p>
            </div>

            <div class="pillar-card">
                <h3>⚡ Performance Efficiency</h3>
                <p><strong>效能效率</strong></p>
                <p>狀態: <span class="status-completed">已完成</span></p>
                <p>有效使用 IT 和計算資源，隨需求變化維持效率。</p>
            </div>

            <div class="pillar-card">
                <h3>💰 Cost Optimization</h3>
                <p><strong>成本優化</strong></p>
                <p>狀態: <span class="status-completed">已完成</span></p>
                <p>避免不必要的成本，了解資金使用情況。</p>
            </div>

            <div class="pillar-card">
                <h3>🌱 Sustainability</h3>
                <p><strong>永續性</strong></p>
                <p>狀態: <span class="status-completed">已完成</span></p>
                <p>最小化雲端工作負載的環境影響。</p>
            </div>
        </div>

        <div class="recommendations">
            <h3>📋 整體建議</h3>
            <ul>
                <li>定期執行 Well-Architected 評估</li>
                <li>實施自動化監控和警報</li>
                <li>建立災難復原計畫</li>
                <li>優化成本和效能</li>
                <li>加強安全性措施</li>
                <li>採用永續性最佳實務</li>
            </ul>
        </div>

        <div class="footer">
            <p>此報告由 AWS Well-Architected Assessment Tool 生成</p>
            <p>建議定期重新評估以確保持續改進</p>
        </div>
    </div>
</body>
</html>
EOF

# 替換 HTML 中的佔位符
sed -i.bak "s/ACCOUNT_ID_PLACEHOLDER/$ACCOUNT_ID/g" "$HTML_REPORT"
sed -i.bak "s/REGION_PLACEHOLDER/$REGION/g" "$HTML_REPORT"
sed -i.bak "s/TIMESTAMP_PLACEHOLDER/$(date)/g" "$HTML_REPORT"
rm "${HTML_REPORT}.bak" 2>/dev/null || true

log_success "綜合報告已生成:"
log_info "JSON 報告: $SUMMARY_FILE"
log_info "HTML 報告: $HTML_REPORT"

# 顯示報告摘要
log_info "評估摘要:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "AWS 帳戶: $ACCOUNT_ID"
echo "區域: $REGION"
echo "評估時間: $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Operational Excellence - 已完成"
echo "✅ Security - 已完成"
echo "✅ Reliability - 已完成"
echo "✅ Performance Efficiency - 已完成"
echo "✅ Cost Optimization - 已完成"
echo "✅ Sustainability - 已完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_success "所有報告已生成完成！"