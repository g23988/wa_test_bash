# 📁 項目結構說明

## 🎯 統一入口

```
wa-tool.sh                    # 🚀 統一管理工具 (主要入口)
```

## 📋 快速參考

```
QUICKSTART.md                 # 🚀 快速入門指南
README.md                     # 📖 項目說明
PROJECT-STRUCTURE.md          # 📁 本文件
```

## 🔧 核心腳本

```
scripts/
├── wa-assessment.sh          # 主要評估腳本
├── generate-report.sh        # 報告生成腳本
├── analyze-all.sh           # 綜合分析腳本
├── analyze-security.sh      # 安全分析腳本
├── analyze-cost.sh          # 成本分析腳本
└── pillars/                 # 各支柱檢查腳本
    ├── operational-excellence.sh
    ├── security.sh
    ├── reliability.sh
    ├── performance-efficiency.sh
    ├── cost-optimization.sh
    └── sustainability.sh
```

## 🗂️ Legacy 腳本 (可選)

```
scripts/legacy/              # 獨立腳本 (被統一工具整合)
├── analyze-compute-cost.sh
├── analyze-database-cost.sh
├── analyze-network-cost.sh
├── analyze-monitoring-cost.sh
├── analyze-datatransfer-cost.sh
├── set-region.sh
├── quick-region.sh
└── troubleshoot.sh
```

## ⚙️ 配置文件

```
config/
├── aws-config.sh            # AWS 配置檢查
└── readonly-policy.json     # 建議的 IAM 政策
```

## 📊 輸出目錄

```
reports/                     # 評估報告輸出
├── wa-assessment-report_*.html      # HTML 視覺化報告
├── wa-assessment-summary_*.json     # JSON 摘要報告
├── security_detailed_*.jsonl        # 安全詳細結果
├── cost-optimization_detailed_*.jsonl # 成本詳細結果
└── ...
```

## 🎨 模板和文檔

```
templates/
└── report-template.html     # HTML 報告模板

docs/
├── installation.md          # 安裝指南
└── usage.md                # 使用說明
```

## 🛠️ 設定腳本

```
setup-permissions.sh         # 權限設定腳本
cleanup-duplicates.sh        # 清理重複文件腳本
```

## 🚀 推薦使用方式

### 新用戶 (推薦)
```bash
./wa-tool.sh setup all      # 統一工具管理一切
./wa-tool.sh assess run
./wa-tool.sh analyze all
```

### 進階用戶
```bash
# 直接使用核心腳本
./scripts/wa-assessment.sh
./scripts/analyze-all.sh

# 或使用 legacy 獨立腳本
./scripts/legacy/analyze-compute-cost.sh reports/cost-*.jsonl
```

## 📝 文件命名規則

### 報告文件
- 格式: `{type}_{timestamp}.{ext}`
- 範例: `security_detailed_20241016_143022.jsonl`

### 腳本文件
- 評估: `{pillar}.sh`
- 分析: `analyze-{type}.sh`
- 工具: `{function}.sh`

## 🔄 升級路徑

1. **舊版本用戶**: 繼續使用 `scripts/` 下的獨立腳本
2. **新用戶**: 直接使用 `wa-tool.sh` 統一工具
3. **遷移**: 逐步從獨立腳本遷移到統一工具

## 💡 設計理念

- **向後兼容**: 保留所有原有腳本功能
- **統一管理**: 通過單一工具管理所有功能
- **模組化**: 每個功能都可以獨立使用
- **清晰結構**: 明確的目錄分工和命名規則