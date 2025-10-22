# 🚀 快速入門指南

## 第一次使用

### 1. 初始化設定
```bash
# 設定統一工具權限
chmod +x wa-tool.sh

# 完整初始化 (設定權限 + 檢查 AWS 配置)
./wa-tool.sh setup all
```

### 2. 設定評估區域
```bash
# 互動式區域設定
./wa-tool.sh region set

# 或快速切換 (us1=us-east-1, ap1=ap-southeast-1, eu1=eu-west-1)
./wa-tool.sh region quick us1
```

### 3. 執行評估
```bash
# 執行完整的 6 支柱評估
./wa-tool.sh assess run
```

### 4. 查看結果
```bash
# 綜合分析所有結果
./wa-tool.sh analyze all

# 查看 HTML 報告
open reports/wa-assessment-report_*.html
```

## 常用命令

### 🔍 檢查系統狀態
```bash
./wa-tool.sh check system      # 完整系統檢查
./wa-tool.sh check aws         # AWS 配置檢查
```

### 📊 專項分析
```bash
./wa-tool.sh analyze security     # 安全性分析
./wa-tool.sh analyze cost         # 成本優化分析
./wa-tool.sh analyze compute      # 計算資源成本
./wa-tool.sh analyze database     # 資料庫成本
./wa-tool.sh analyze network      # 網路成本
```

### 🌍 區域管理
```bash
./wa-tool.sh region current    # 顯示當前區域
./wa-tool.sh region list       # 列出所有區域
./wa-tool.sh region quick ap1  # 快速切換到亞太區
```

## 故障排除

### 權限問題
```bash
# 如果遇到 "Permission denied" 錯誤
./wa-tool.sh setup permissions
```

### AWS 配置問題
```bash
# 檢查 AWS 憑證和權限
./wa-tool.sh check aws
```

### 完整診斷
```bash
# 自動診斷所有可能問題
./wa-tool.sh check system
```

## 輸出文件說明

評估完成後，在 `reports/` 目錄會生成：

| 文件類型 | 說明 | 用途 |
|----------|------|------|
| `wa-assessment-report_*.html` | 視覺化報告 | 給管理層查看 |
| `wa-assessment-summary_*.json` | 評估摘要 | 程式化處理 |
| `*_detailed_*.jsonl` | 詳細檢查結果 | 深度分析 |

## 快速參考

```bash
# 完整流程 (一次性執行)
./wa-tool.sh setup all && \
./wa-tool.sh region quick us1 && \
./wa-tool.sh assess run && \
./wa-tool.sh analyze all

# 查看幫助
./wa-tool.sh help

# 檢查當前狀態
./wa-tool.sh check system
```

## 需要幫助？

- 查看完整說明: `./wa-tool.sh help`
- 系統診斷: `./wa-tool.sh check system`
- 詳細文檔: 查看 `docs/` 目錄