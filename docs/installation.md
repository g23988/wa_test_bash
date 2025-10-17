# 安裝指南

## 前置需求

### 1. AWS CLI
```bash
# macOS
brew install awscli

# 或使用 pip
pip install awscli

# 驗證安裝
aws --version
```

### 2. jq (JSON 處理工具)
```bash
# macOS
brew install jq

# 驗證安裝
jq --version
```

### 3. AWS 憑證配置

#### 方法一：使用 AWS CLI 配置
```bash
aws configure
```
輸入以下資訊：
- AWS Access Key ID
- AWS Secret Access Key  
- Default region name (例如: us-east-1)
- Default output format (建議: json)

#### 方法二：使用環境變數
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

#### 方法三：使用 IAM Role (推薦用於 EC2)
如果在 EC2 實例上運行，可以使用 IAM Role 而不需要配置憑證。

## 權限需求

此工具需要以下 **readonly** 權限：

### 必要權限
- `ec2:Describe*`
- `iam:List*`, `iam:Get*`
- `s3:List*`, `s3:Get*`
- `rds:Describe*`
- `cloudtrail:Describe*`, `cloudtrail:List*`
- `cloudwatch:Describe*`, `cloudwatch:List*`
- `config:Describe*`, `config:List*`
- `sts:GetCallerIdentity`

### 完整權限清單
參考 `config/readonly-policy.json` 文件中的完整 IAM 政策。

## 安裝步驟

### 1. 下載專案
```bash
git clone <repository-url>
cd aws-wa-assessment
```

### 2. 設定執行權限
```bash
chmod +x scripts/*.sh
chmod +x scripts/pillars/*.sh
chmod +x config/*.sh
```

### 3. 檢查配置
```bash
./config/aws-config.sh
```

### 4. 執行評估
```bash
./scripts/wa-assessment.sh
```

## 驗證安裝

執行以下命令驗證所有組件正常運作：

```bash
# 檢查 AWS CLI
aws sts get-caller-identity

# 檢查 jq
echo '{"test": "value"}' | jq .

# 檢查腳本權限
ls -la scripts/wa-assessment.sh
```

## 故障排除

### 常見問題

1. **AWS CLI 未找到**
   ```bash
   # 檢查 PATH
   echo $PATH
   # 重新安裝 AWS CLI
   ```

2. **權限不足**
   ```bash
   # 檢查當前權限
   aws iam get-user
   # 聯繫管理員添加必要權限
   ```

3. **區域設定問題**
   ```bash
   # 檢查當前區域
   aws configure get region
   # 設定區域
   aws configure set region us-east-1
   ```

4. **jq 未安裝**
   ```bash
   # macOS
   brew install jq
   # 其他系統請參考 jq 官方文檔
   ```

## 支援的作業系統

- macOS
- Linux (Ubuntu, CentOS, Amazon Linux)
- Windows (使用 WSL 或 Git Bash)

## 下一步

安裝完成後，請參考：
- [使用指南](usage.md)
- [配置說明](configuration.md)
- [報告解讀](report-interpretation.md)