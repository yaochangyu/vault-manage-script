# HashiCorp Vault 管理工具

本地開發用的 Vault 管理命令行工具，使用 Shell Script 實作，支援 KV secrets 的完整 CRUD 操作。

## 功能特色

- ✅ **Userpass 認證**：使用帳號密碼登入 Vault
- ✅ **完整 CRUD 操作**：讀取、建立、更新、刪除 KV secrets
- ✅ **列出 secrets**：支援遞迴列出指定路徑下的所有 secrets
- ✅ **雙格式輸出**：支援 JSON 和人類可讀的表格格式
- ✅ **安全設計**：機敏資料透過環境變數管理，不納入版控
- ✅ **錯誤處理**：完整的錯誤處理與清楚的錯誤訊息

## 系統需求

- **Bash**: 4.0+
- **curl**: 用於 API 呼叫
- **jq**: 用於 JSON 處理

### 檢查依賴工具

```bash
# 檢查 bash 版本
bash --version

# 檢查 curl 是否安裝
curl --version

# 檢查 jq 是否安裝
jq --version
```

### 安裝依賴工具

**Ubuntu/Debian**:
```bash
sudo apt-get update
sudo apt-get install -y curl jq
```

**macOS**:
```bash
brew install curl jq
```

**CentOS/RHEL**:
```bash
sudo yum install -y curl jq
```

## 快速開始

### 1. 設定環境變數

複製環境變數範本並填入實際資訊：

```bash
cp .env.example .env
```

編輯 `.env` 檔案，填入你的 Vault 認證資訊：

```bash
VAULT_ADDR=https://vault.web.internal
VAULT_SKIP_VERIFY=true
VAULT_USERNAME=your-username
VAULT_PASSWORD=your-password
```

⚠️ **重要**：`.env` 檔案包含機敏資料，已加入 `.gitignore`，請勿納入版控。

### 2. 載入環境變數

```bash
# 方式一：直接 export
export VAULT_ADDR='https://vault.web.internal'
export VAULT_SKIP_VERIFY=true
export VAULT_USERNAME='your-username'
export VAULT_PASSWORD='your-password'

# 方式二：從 .env 檔案載入
set -a
source .env
set +a
```

### 3. 賦予執行權限

```bash
chmod +x vault-manage.sh
```

### 4. 使用工具

```bash
# 讀取 secret
./vault-manage.sh get secrets teams/job-finder/environments/qa/db-user

# 建立 secret
./vault-manage.sh create secrets teams/test/api-key key1=value1 key2=value2

# 更新 secret
./vault-manage.sh update secrets teams/test/api-key key3=value3

# 列出 secrets
./vault-manage.sh list secrets teams/job-finder

# 刪除 secret
./vault-manage.sh delete secrets teams/test/api-key
```

## 使用說明

### 命令格式

```bash
./vault-manage.sh <command> <mount> <path> [options]
```

### 支援的命令

#### 1. 讀取 secret (get)

```bash
# JSON 格式輸出（預設）
./vault-manage.sh get <mount> <path>

# 表格格式輸出
./vault-manage.sh get <mount> <path> --format table

# 範例
./vault-manage.sh get secrets teams/job-finder/environments/qa/db-user
./vault-manage.sh get secrets teams/job-finder/environments/qa/db-user --format table
```

#### 2. 建立 secret (create)

```bash
./vault-manage.sh create <mount> <path> <key1>=<value1> <key2>=<value2> ...

# 範例
./vault-manage.sh create secrets teams/test/api-key api_key=abc123 api_secret=xyz789
```

#### 3. 更新 secret (update)

```bash
# 部分更新（預設，merge 模式）
./vault-manage.sh update <mount> <path> <key1>=<value1> ...

# 完整覆蓋（replace 模式）
./vault-manage.sh update <mount> <path> <key1>=<value1> ... --replace

# 範例
./vault-manage.sh update secrets teams/test/api-key new_key=new_value
./vault-manage.sh update secrets teams/test/api-key key1=value1 key2=value2 --replace
```

#### 4. 刪除 secret (delete)

```bash
./vault-manage.sh delete <mount> <path>

# 範例（會提示確認）
./vault-manage.sh delete secrets teams/test/api-key
```

#### 5. 列出 secrets (list)

```bash
./vault-manage.sh list <mount> <path>

# 範例
./vault-manage.sh list secrets teams
./vault-manage.sh list secrets teams/job-finder
```

## 輸出格式

### JSON 格式

```json
{
  "username": "dbuser",
  "password": "dbpass123",
  "host": "localhost",
  "port": "5432"
}
```

### 表格格式

```
KEY         VALUE
username    dbuser
password    dbpass123
host        localhost
port        5432
```

## 安全注意事項

1. **絕不將機敏資料寫入程式碼或納入版控**
   - `.env` 檔案已加入 `.gitignore`
   - 僅使用 `.env.example` 作為範本

2. **環境變數管理**
   - 使用環境變數傳遞認證資訊
   - 避免在命令列直接輸入密碼（會留在 shell history）

3. **Token 管理**
   - Token 只存在於記憶體中
   - 不寫入檔案或日誌

4. **TLS 驗證**
   - 開發環境可使用 `VAULT_SKIP_VERIFY=true`
   - 生產環境務必啟用 TLS 驗證並正確配置憑證

5. **權限控制**
   - 確保腳本檔案權限適當（建議 755）
   - 確保 `.env` 檔案權限嚴格（建議 600）

## 疑難排解

### 錯誤：curl: command not found

請安裝 curl：
```bash
# Ubuntu/Debian
sudo apt-get install curl

# macOS
brew install curl
```

### 錯誤：jq: command not found

請安裝 jq：
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq
```

### 錯誤：認證失敗

1. 檢查環境變數是否正確設定：
   ```bash
   echo $VAULT_ADDR
   echo $VAULT_USERNAME
   # 不要 echo $VAULT_PASSWORD（避免洩漏）
   ```

2. 確認帳號密碼正確

3. 確認 Vault 伺服器可連線：
   ```bash
   curl -k $VAULT_ADDR/v1/sys/health
   ```

### 錯誤：無法連線到 Vault

1. 檢查網路連線
2. 檢查 `VAULT_ADDR` 是否正確
3. 檢查防火牆設定

## 更多範例

請參考 [EXAMPLES.md](./EXAMPLES.md) 查看更多使用範例。

## 授權

本專案僅供內部開發使用。

## 聯絡資訊

如有問題或建議，請聯絡開發團隊。
