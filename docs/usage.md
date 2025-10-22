# 使用指南

## 快速開始

### 1. 基本使用
```bash
# 執行完整評估
./scripts/wa-assessment.sh
```

### 2. 檢查配置
```bash
# 驗證 AWS 配置和權限
./config/aws-config.sh
```

## 詳細使用說明

### 執行單一支柱檢查

如果只想檢查特定支柱，可以單獨執行：

```bash
# 獲取帳戶資訊
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 執行特定支柱
./scripts/pillars/security.sh $ACCOUNT_ID $REGION $TIMESTAMP
./scripts/pillars/cost-optimization.sh $ACCOUNT_ID $REGION $TIMESTAMP
```

### 區域管理

#### 設定評估區域

```bash
# 使用互動式區域設定工具
./scripts/set-region.sh

# 直接設定特定區域
./scripts/set-region.sh us-east-1

# 使用快速區域切換
./scripts/quick-region.sh us1    # 切換到 us-east-1
./scripts/quick-region.sh ap1    # 切換到 ap-southeast-1

# 查看當前區域
./scripts/set-region.sh --current
./scripts/quick-region.sh --current
```

#### 在評估時設定區域

```bash
# 在執行評估前設定區域
./scripts/wa-assessment.sh --set-region

# 或使用配置檢查工具
./config/aws-config.sh --set-region
```

#### 傳統方式設定區域

```bash
# 設定特定區域
export AWS_DEFAULT_REGION=ap-southeast-1
./scripts/wa-assessment.sh

# 或使用 AWS CLI 設定
aws configure set region ap-southeast-1
./scripts/wa-assessment.sh
```

### 批次執行多區域評估

#### 使用新的區域管理工具

```bash
#!/bin/bash
regions=("us1" "us2" "ap1" "eu1")  # 使用快速代碼

for region_code in "${regions[@]}"; do
    echo "評估區域: $region_code"
    ./scripts/quick-region.sh "$region_code"
    ./scripts/wa-assessment.sh
done
```

#### 傳統方式

```bash
#!/bin/bash
regions=("us-east-1" "us-west-2" "ap-southeast-1" "eu-west-1")

for region in "${regions[@]}"; do
    echo "評估區域: $region"
    export AWS_DEFAULT_REGION=$region
    ./scripts/wa-assessment.sh
done
```

## 輸出文件說明

### 報告文件位置
所有報告都會生成在 `reports/` 目錄下：

```
reports/
├── operational-excellence_20241016_143022.json
├── security_20241016_143022.json
├── reliability_20241016_143022.json
├── performance-efficiency_20241016_143022.json
├── cost-optimization_20241016_143022.json
├── sustainability_20241016_143022.json
├── wa-assessment-summary_20241016_143022.json
└── wa-assessment-report_20241016_143022.html
```

### 文件說明

1. **個別支柱 JSON 報告**
   - 包含該支柱的詳細檢查結果
   - 原始 AWS API 回應資料
   - 支柱特定建議

2. **綜合 JSON 報告** (`wa-assessment-summary_*.json`)
   - 所有支柱的摘要資訊
   - 整體評估狀態
   - 綜合建議

3. **HTML 報告** (`wa-assessment-report_*.html`)
   - 視覺化的評估報告
   - 適合分享給利害關係人
   - 包含所有支柱的概覽

## 進階使用

### 自訂檢查項目

可以修改各支柱腳本來添加或移除特定檢查：

```bash
# 編輯安全性支柱檢查
vim scripts/pillars/security.sh

# 添加新的 AWS 服務檢查
# 例如：添加 WAF 檢查
WAF_WEBACLS=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 2>/dev/null || echo '{"WebACLs":[]}')
```

### 設定排程執行

#### 使用 cron 定期執行
```bash
# 編輯 crontab
crontab -e

# 每週一早上 8 點執行評估
0 8 * * 1 /path/to/aws-wa-assessment/scripts/wa-assessment.sh

# 每月 1 號執行評估
0 8 1 * * /path/to/aws-wa-assessment/scripts/wa-assessment.sh
```

#### 使用 AWS EventBridge (CloudWatch Events)
可以在 AWS 中設定定期觸發 Lambda 函數來執行評估。

### 整合 CI/CD

#### GitHub Actions 範例
```yaml
name: AWS Well-Architected Assessment
on:
  schedule:
    - cron: '0 8 * * 1'  # 每週一早上 8 點
  workflow_dispatch:

jobs:
  assessment:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Run Assessment
        run: ./scripts/wa-assessment.sh
      - name: Upload Reports
        uses: actions/upload-artifact@v2
        with:
          name: wa-reports
          path: reports/
```

## 最佳實務

### 1. 定期執行
- 建議每月執行一次完整評估
- 在重大架構變更後執行評估
- 在合規性審查前執行評估

### 2. 報告管理
- 保留歷史報告以追蹤改進進度
- 將報告存檔到 S3 進行長期保存
- 設定報告自動分發給相關團隊

### 3. 權限管理
- 使用最小權限原則
- 定期輪換存取金鑰
- 考慮使用 IAM Role 而非長期憑證

### 4. 多帳戶環境
```bash
# 為多個 AWS 帳戶執行評估
accounts=("123456789012" "234567890123" "345678901234")

for account in "${accounts[@]}"; do
    echo "切換到帳戶: $account"
    aws sts assume-role --role-arn "arn:aws:iam::$account:role/WellArchitectedRole" --role-session-name "wa-assessment"
    ./scripts/wa-assessment.sh
done
```

## 故障排除

### 自動診斷工具

```bash
# 執行完整的系統檢查
./scripts/troubleshoot.sh

# 設定腳本權限
./setup-permissions.sh
```

### 常見錯誤

1. **權限被拒絕錯誤**
   ```bash
   # 錯誤訊息: Permission denied
   # 解決方案: 設定執行權限
   ./setup-permissions.sh
   
   # 或手動設定
   chmod +x scripts/*.sh scripts/pillars/*.sh config/*.sh
   ```

2. **AWS 權限不足錯誤**
   ```bash
   # 檢查具體缺少的權限
   aws iam simulate-principal-policy --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) --action-names ec2:DescribeInstances
   
   # 檢查當前權限
   ./config/aws-config.sh
   ```

3. **區域不支援某些服務**
   ```bash
   # 檢查服務在該區域的可用性
   aws ec2 describe-regions --query 'Regions[?RegionName==`us-east-1`]'
   
   # 切換到支援的區域
   ./scripts/set-region.sh
   ```

4. **API 限流**
   ```bash
   # 在腳本中添加延遲
   sleep 1  # 在 API 調用之間添加延遲
   ```

5. **缺少必要工具**
   ```bash
   # 檢查並安裝 jq
   brew install jq  # macOS
   sudo apt-get install jq  # Ubuntu
   
   # 檢查並安裝 AWS CLI
   brew install awscli  # macOS
   ```

## 效能優化

### 並行執行
可以修改主腳本來並行執行各支柱檢查：

```bash
# 並行執行所有支柱檢查
./scripts/pillars/operational-excellence.sh "$ACCOUNT_ID" "$REGION" "$TIMESTAMP" &
./scripts/pillars/security.sh "$ACCOUNT_ID" "$REGION" "$TIMESTAMP" &
./scripts/pillars/reliability.sh "$ACCOUNT_ID" "$REGION" "$TIMESTAMP" &
./scripts/pillars/performance-efficiency.sh "$ACCOUNT_ID" "$REGION" "$TIMESTAMP" &
./scripts/pillars/cost-optimization.sh "$ACCOUNT_ID" "$REGION" "$TIMESTAMP" &
./scripts/pillars/sustainability.sh "$ACCOUNT_ID" "$REGION" "$TIMESTAMP" &

# 等待所有背景程序完成
wait
```

### 快取結果
對於大型環境，可以實施結果快取來避免重複的 API 調用。