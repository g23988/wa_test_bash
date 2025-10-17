# AWS Well-Architected 6 Pillars Assessment Tool

這是一個用於執行 AWS Well-Architected Framework 6 個支柱評估的工具，專為具有 readonly 權限的客戶環境設計。

## 6 個支柱 (Six Pillars)

1. **Operational Excellence (營運卓越)**
2. **Security (安全性)**
3. **Reliability (可靠性)**
4. **Performance Efficiency (效能效率)**
5. **Cost Optimization (成本優化)**
6. **Sustainability (永續性)**

## 項目結構

```
├── scripts/                 # 主要檢查腳本
├── config/                  # 配置文件
├── reports/                 # 報告輸出目錄
├── templates/               # 報告模板
└── docs/                    # 文檔

```

## 使用方式

1. 配置 AWS 憑證 (readonly 權限)
2. 執行主要檢查腳本
3. 查看生成的報告

## 前置需求

- AWS CLI
- jq (JSON 處理工具)
- 具有 readonly 權限的 AWS 憑證