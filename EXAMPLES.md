# 使用範例

本文件提供 Vault CLI 工具的詳細使用範例。

## 目錄

- [環境設定](#環境設定)
- [基本操作](#基本操作)
- [進階使用](#進階使用)
- [常見場景](#常見場景)
- [疑難排解](#疑難排解)

---

## 環境設定

### 方式 1：直接 export 環境變數

```bash
export VAULT_ADDR='https://vault.web.internal'
export VAULT_SKIP_VERIFY=true
export VAULT_USERNAME='yao'
export VAULT_PASSWORD='your-password'
```

### 方式 2：使用 .env 檔案

1. 建立 `.env` 檔案：

```bash
cp .env.example .env
```

2. 編輯 `.env` 填入實際資訊：

```bash
VAULT_ADDR=https://vault.web.internal
VAULT_SKIP_VERIFY=true
VAULT_USERNAME=yao
VAULT_PASSWORD=your-actual-password
```

3. 載入環境變數：

```bash
set -a
source .env
set +a
```

### 驗證環境變數

```bash
# 檢查環境變數是否設定（不要顯示密碼）
echo "VAULT_ADDR: $VAULT_ADDR"
echo "VAULT_USERNAME: $VAULT_USERNAME"
echo "VAULT_SKIP_VERIFY: $VAULT_SKIP_VERIFY"
```

---

## 基本操作

### 1. 讀取 Secret

#### JSON 格式（預設）

```bash
./vault-manage.sh get secrets teams/job-finder/environments/qa/db-user
```

輸出範例：

```json
{
  "username": "dbuser",
  "password": "dbpass123",
  "host": "localhost",
  "port": "5432",
  "database": "mydb"
}
```

#### 表格格式

```bash
./vault-manage.sh get secrets teams/job-finder/environments/qa/db-user --format table
```

輸出範例：

```
KEY         VALUE
username    dbuser
password    dbpass123
host        localhost
port        5432
database    mydb
```

### 2. 建立 Secret

```bash
# 建立資料庫認證資訊
./vault-manage.sh create secrets teams/job-finder/environments/dev/db-user \
  username=devuser \
  password=devpass123 \
  host=localhost \
  port=5432 \
  database=devdb
```

```bash
# 建立 API 金鑰
./vault-manage.sh create secrets teams/job-finder/api-keys/github \
  api_key=ghp_xxxxxxxxxxxx \
  api_secret=secret_xxxxxxxxxxxx
```

### 3. 更新 Secret

#### 部分更新（預設，merge 模式）

```bash
# 只更新密碼，保留其他欄位
./vault-manage.sh update secrets teams/job-finder/environments/qa/db-user \
  password=new_password_123
```

#### 完整覆蓋（replace 模式）

```bash
# 完整覆蓋，會刪除未指定的欄位
./vault-manage.sh update secrets teams/job-finder/environments/qa/db-user \
  username=newuser \
  password=newpass \
  host=newhost \
  port=3306 \
  --replace
```

### 4. 列出 Secrets

```bash
# 列出根路徑
./vault-manage.sh list secrets teams

# 列出特定路徑
./vault-manage.sh list secrets teams/job-finder

# 列出更深的路徑
./vault-manage.sh list secrets teams/job-finder/environments
```

輸出範例：

```
Secrets in secrets/teams/job-finder:
---
  📁 environments/
  📁 api-keys/
  📄 service-account
```

### 5. 刪除 Secret

```bash
./vault-manage.sh delete secrets teams/test/temp-secret
```

輸出範例：

```
[警告] 即將刪除 secret：secrets/teams/test/temp-secret
確定要刪除嗎？(y/N): y
[資訊] 正在刪除 secret: secrets/teams/test/temp-secret
[成功] 刪除成功：secrets/teams/test/temp-secret
```

---

## 進階使用

### 批次操作

#### 批次讀取多個 Secrets

```bash
#!/bin/bash

# 定義要讀取的 secrets 清單
secrets=(
  "teams/job-finder/environments/qa/db-user"
  "teams/job-finder/environments/qa/api-keys"
  "teams/job-finder/environments/qa/service-account"
)

# 批次讀取
for secret in "${secrets[@]}"; do
  echo "========================================="
  echo "讀取: $secret"
  echo "========================================="
  ./vault-manage.sh get secrets "$secret"
  echo ""
done
```

#### 批次建立環境 Secrets

```bash
#!/bin/bash

# 為不同環境建立相同結構的 secrets
environments=("dev" "qa" "staging" "prod")

for env in "${environments[@]}"; do
  echo "建立 $env 環境的資料庫認證..."
  ./vault-manage.sh create secrets "teams/job-finder/environments/$env/db-user" \
    username="${env}_user" \
    password="${env}_pass_$(date +%s)" \
    host="${env}-db.internal" \
    port=5432 \
    database="${env}_db"
done
```

### 從檔案讀取資料建立 Secret

```bash
#!/bin/bash

# 從 JSON 檔案讀取並建立 secret
config_file="db-config.json"

# 解析 JSON 並轉換為 key=value 格式
jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$config_file" | \
while IFS= read -r pair; do
  kv_args+=("$pair")
done

# 建立 secret
./vault-manage.sh create secrets teams/job-finder/db-config "${kv_args[@]}"
```

### 輸出重導向與處理

```bash
# 將 secret 輸出儲存為檔案（注意安全性！）
./vault-manage.sh get secrets teams/job-finder/api-keys > /tmp/api-keys.json

# 使用 jq 處理 secret
./vault-manage.sh get secrets teams/job-finder/db-user | \
  jq -r '.username'

# 組合成連線字串
db_host=$(./vault-manage.sh get secrets teams/job-finder/db-user | jq -r '.host')
db_port=$(./vault-manage.sh get secrets teams/job-finder/db-user | jq -r '.port')
db_name=$(./vault-manage.sh get secrets teams/job-finder/db-user | jq -r '.database')

echo "postgresql://$db_host:$db_port/$db_name"
```

---

## 常見場景

### 場景 1：初始化專案環境

```bash
#!/bin/bash

echo "初始化專案環境 secrets..."

# 建立資料庫認證
./vault-manage.sh create secrets myproject/dev/database \
  host=localhost \
  port=5432 \
  username=devuser \
  password=devpass123 \
  database=myapp_dev

# 建立 Redis 認證
./vault-manage.sh create secrets myproject/dev/redis \
  host=localhost \
  port=6379 \
  password=redis123

# 建立外部 API 金鑰
./vault-manage.sh create secrets myproject/dev/external-apis \
  github_token=ghp_xxxxxxxxxxxx \
  slack_webhook=https://hooks.slack.com/xxxx \
  sendgrid_api_key=SG.xxxxxxxxxxxx

echo "環境初始化完成！"
```

### 場景 2：密碼輪替

```bash
#!/bin/bash

# 讀取現有的 secret
echo "讀取現有密碼..."
./vault-manage.sh get secrets teams/job-finder/db-user --format table

# 產生新密碼
new_password=$(openssl rand -base64 32)

# 更新密碼（部分更新）
echo "更新密碼..."
./vault-manage.sh update secrets teams/job-finder/db-user \
  password="$new_password"

echo "密碼已更新！"
```

### 場景 3：環境遷移

```bash
#!/bin/bash

# 從 QA 複製 secrets 到 Staging

# 讀取 QA 的 secret
qa_secret=$(./vault-manage.sh get secrets teams/job-finder/environments/qa/db-user)

# 解析並建立 Staging secret
username=$(echo "$qa_secret" | jq -r '.username')
host=$(echo "$qa_secret" | jq -r '.host')
port=$(echo "$qa_secret" | jq -r '.port')
database=$(echo "$qa_secret" | jq -r '.database')

# 產生新密碼給 Staging
staging_password=$(openssl rand -base64 32)

# 建立 Staging secret
./vault-manage.sh create secrets teams/job-finder/environments/staging/db-user \
  username="$username" \
  password="$staging_password" \
  host="staging-$host" \
  port="$port" \
  database="${database/qa/staging}"

echo "環境遷移完成！"
```

### 場景 4：審計與檢查

```bash
#!/bin/bash

echo "========================================="
echo "Vault Secrets 審計報告"
echo "========================================="
echo ""

# 列出所有團隊
echo "所有團隊："
./vault-manage.sh list secrets teams
echo ""

# 列出特定團隊的所有環境
echo "Job Finder 專案環境："
./vault-manage.sh list secrets teams/job-finder/environments
echo ""

# 檢查每個環境的 secrets
for env in dev qa staging prod; do
  echo "檢查 $env 環境..."
  ./vault-manage.sh list secrets "teams/job-finder/environments/$env" || echo "  環境不存在"
  echo ""
done
```

---

## 疑難排解

### 問題 1：認證失敗

**錯誤訊息**：

```
[錯誤] 認證失敗（HTTP 403）
[錯誤] 錯誤詳情：permission denied
```

**解決方法**：

1. 檢查帳號密碼是否正確
2. 檢查使用者是否有權限存取
3. 確認 Vault 伺服器位址正確

```bash
# 重新設定認證資訊
export VAULT_USERNAME='correct-username'
export VAULT_PASSWORD='correct-password'
```

### 問題 2：Secret 不存在

**錯誤訊息**：

```
[錯誤] Secret 不存在：secrets/teams/unknown/path
```

**解決方法**：

1. 使用 list 命令確認路徑：

```bash
./vault-manage.sh list secrets teams
./vault-manage.sh list secrets teams/job-finder
```

2. 檢查路徑拼寫是否正確

### 問題 3：連線逾時

**錯誤訊息**：

```
[錯誤] 讀取失敗（HTTP 000）
```

**解決方法**：

1. 檢查網路連線
2. 檢查 Vault 伺服器是否正常運作

```bash
# 測試連線
curl -k $VAULT_ADDR/v1/sys/health

# 檢查 DNS 解析
nslookup vault.web.internal
```

### 問題 4：權限不足

**錯誤訊息**：

```
[錯誤] 建立失敗（HTTP 403）
[錯誤] 錯誤詳情：permission denied
```

**解決方法**：

1. 確認使用者有寫入權限
2. 聯絡 Vault 管理員調整 policy

### 問題 5：環境變數未設定

**錯誤訊息**：

```
[錯誤] 缺少必要的環境變數：
  - VAULT_ADDR
```

**解決方法**：

```bash
# 確認環境變數
env | grep VAULT

# 重新載入 .env
set -a && source .env && set +a

# 或手動設定
export VAULT_ADDR='https://vault.web.internal'
export VAULT_USERNAME='your-username'
export VAULT_PASSWORD='your-password'
```

---

## 安全最佳實踐

### 1. 不要將密碼寫入 Shell History

```bash
# 錯誤做法（密碼會留在 history）
export VAULT_PASSWORD='my-password'

# 正確做法（使用 read 互動式輸入）
read -s -p "Enter Vault Password: " VAULT_PASSWORD
export VAULT_PASSWORD
echo ""
```

### 2. 使用 .env 檔案並設定正確權限

```bash
# 建立 .env 檔案
cp .env.example .env

# 設定嚴格權限（只有自己可讀寫）
chmod 600 .env

# 確認權限
ls -la .env
```

### 3. 不要將 secrets 輸出到不安全的位置

```bash
# 錯誤做法（寫入可能被其他人讀取的檔案）
./vault-manage.sh get secrets my-secret > /tmp/secret.json

# 正確做法（使用變數，不寫入檔案）
SECRET_VALUE=$(./vault-manage.sh get secrets my-secret | jq -r '.password')
```

### 4. 完成後清除環境變數

```bash
# 使用完畢後清除機敏資訊
unset VAULT_PASSWORD
unset VAULT_TOKEN
```

---

## 參考資料

- [Vault 官方文件](https://www.vaultproject.io/docs)
- [Vault KV Secrets Engine](https://www.vaultproject.io/docs/secrets/kv)
- [專案 README](./README.md)
