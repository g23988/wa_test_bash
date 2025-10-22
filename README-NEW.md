# AWS Well-Architected Assessment Tool

一個簡潔的 AWS Well-Architected Framework 6 支柱評估工具。

## 🚀 快速開始

```bash
# 1. 重新組織項目結構（首次使用）
chmod +x reorganize.sh
./reorganize.sh

# 2. 初始化
./wa-tool.sh setup

# 3. 執行評估
./wa-tool.sh assess

# 4. 分析結果
./wa-tool.sh analyze
```

## 📁 項目結構

```
.
├── wa-tool.sh              # 統一管理工具
├── core/
│   ├── assessment/         # 評估腳本
│   ├── analysis/           # 分析腳本
│   └── pillars/            # 6 個支柱檢查
├── config/                 # 配置文件
├── templates/              # 報告模板
├── docs/                   # 文檔
└── reports/                # 輸出報告
```

## 📊 6 個支柱

| 支柱 | 檢查重點 |
|------|----------|
| 🔧 Operational Excellence | CloudTrail, CloudWatch, Config |
| 🔒 Security | IAM, MFA, 加密, 網路安全 |
| 🛡️ Reliability | Multi-AZ, 備份, Auto Scaling |
| ⚡ Performance Efficiency | 實例類型, 快取, CDN |
| 💰 Cost Optimization | 未使用資源, 儲存優化 |
| 🌱 Sustainability | 資源效率, 區域選擇 |

## 🛠️ 命令

```bash
./wa-tool.sh setup          # 初始化設定
./wa-tool.sh assess         # 執行評估
./wa-tool.sh analyze        # 分析結果
./wa-tool.sh analyze security  # 安全分析
./wa-tool.sh analyze cost   # 成本分析
./wa-tool.sh region set     # 設定區域
./wa-tool.sh region current # 顯示當前區域
./wa-tool.sh check          # 系統檢查
./wa-tool.sh help           # 顯示說明
```

## 📋 前置需求

- AWS CLI (readonly 權限)
- jq
- Python 3
- Bash 4.0+

## 🔧 故障排除

```bash
./wa-tool.sh check          # 檢查系統狀態
./wa-tool.sh setup          # 重新初始化
```

## 📖 詳細文檔

查看 `docs/` 目錄獲取更多資訊。