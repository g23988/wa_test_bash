# AWS Well-Architected Assessment Tool

一個統一的 AWS Well-Architected Framework 6 支柱評估工具，專為 readonly 權限環境設計。

## 🚀 快速開始

```bash
# 1. 完整初始化 (一次性設定)
chmod +x wa-tool.sh
./wa-tool.sh setup all

# 2. 設定評估區域 (可選)
./wa-tool.sh region set

# 3. 執行評估
./wa-tool.sh assess run

# 4. 分析結果
./wa-tool.sh analyze all
```

## 📊 支柱評估

| 支柱 | 說明 | 重點檢查 |
|------|------|----------|
| 🔧 **Operational Excellence** | 營運卓越 | CloudTrail, CloudWatch, Config |
| 🔒 **Security** | 安全性 | IAM, MFA, 加密, 網路安全 |
| 🛡️ **Reliability** | 可靠性 | Multi-AZ, 備份, Auto Scaling |
| ⚡ **Performance Efficiency** | 效能效率 | 實例類型, 快取, CDN |
| 💰 **Cost Optimization** | 成本優化 | 未使用資源, 儲存優化, 定價 |
| 🌱 **Sustainability** | 永續性 | 資源效率, 區域選擇 |

## 🛠️ 統一管理工具

所有功能都通過 `wa-tool.sh` 統一管理：

### 初始設定
```bash
./wa-tool.sh setup all          # 完整初始化
./wa-tool.sh setup permissions  # 只設定權限
./wa-tool.sh setup aws          # 只檢查 AWS 配置
```

### 區域管理
```bash
./wa-tool.sh region set         # 互動式設定區域
./wa-tool.sh region quick us1   # 快速切換到 us-east-1
./wa-tool.sh region current     # 顯示當前區域
./wa-tool.sh region list        # 列出所有區域
```

### 執行評估
```bash
./wa-tool.sh assess run         # 完整評估
./wa-tool.sh assess security    # 只評估安全性
./wa-tool.sh assess cost        # 只評估成本
```

### 結果分析
```bash
./wa-tool.sh analyze all        # 綜合分析
./wa-tool.sh analyze security   # 安全分析
./wa-tool.sh analyze cost       # 成本分析
./wa-tool.sh analyze compute    # 計算資源成本
./wa-tool.sh analyze database   # 資料庫成本
./wa-tool.sh analyze network    # 網路成本
```

### 系統檢查
```bash
./wa-tool.sh check system       # 完整系統檢查
./wa-tool.sh check aws          # AWS 配置檢查
./wa-tool.sh check permissions  # 權限檢查
```

## 📁 輸出報告

評估完成後會在 `reports/` 目錄生成：

- **HTML 報告**: 視覺化的綜合報告
- **JSON 摘要**: 結構化的評估摘要
- **詳細結果**: 每個檢查項目的詳細資料 (JSONL 格式)

## 🔧 故障排除

如果遇到問題：

```bash
./wa-tool.sh check system       # 自動診斷
./wa-tool.sh setup permissions  # 修復權限問題
./wa-tool.sh help               # 查看完整說明
```

## 📋 前置需求

- AWS CLI (已配置 readonly 權限)
- jq (JSON 處理工具)
- Python 3 (用於日期計算)
- Bash 4.0+

## 🎯 設計原則

- **統一入口**: 所有功能通過單一工具管理
- **Readonly 安全**: 只讀取資源資訊，不做任何修改
- **詳細分析**: 提供具體的成本節省建議
- **易於使用**: 互動式設定和清晰的輸出