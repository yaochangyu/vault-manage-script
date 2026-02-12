# Shell Script 管理工具集

本專案包含三個獨立的 Shell Script 管理工具，用於簡化開發和運維工作。

## 📦 包含工具

1. **vault-manage.sh** - HashiCorp Vault KV secrets 管理工具
2. **sql-permission.sh** - SQL Server 權限管理工具
3. **create-database.sh** - SQL Server 資料庫建立工具

---

# 🔐 Vault 管理工具

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

#### 步驟 1.1：複製環境變數範本

專案提供了 `.env.example` 範本檔案，請先複製為 `.env` 檔案：

```bash
cp .env.example .env
```

#### 步驟 1.2：編輯 .env 檔案

使用你喜歡的編輯器開啟 `.env` 檔案：

```bash
# 使用 vim
vim .env

# 或使用 nano
nano .env

# 或使用 VS Code
code .env
```

#### 步驟 1.3：填入實際的認證資訊

在 `.env` 檔案中，將以下變數替換為實際的 Vault 認證資訊：

```bash
# Vault 伺服器位址（必填）
VAULT_ADDR=https://vault.web.internal

# 跳過 TLS 憑證驗證（開發環境可設為 true，生產環境請設為 false）
VAULT_SKIP_VERIFY=true

# Vault 使用者名稱（必填）
VAULT_USERNAME=your-username

# Vault 密碼（必填）
VAULT_PASSWORD=your-password
```

**各欄位說明：**

| 變數名稱 | 說明 | 範例 | 必填 |
|---------|------|------|------|
| `VAULT_ADDR` | Vault 伺服器的完整 URL | `https://vault.web.internal` | ✅ |
| `VAULT_SKIP_VERIFY` | 是否跳過 TLS 憑證驗證<br>（開發環境可用 `true`，生產環境建議 `false`） | `true` 或 `false` | ✅ |
| `VAULT_USERNAME` | Vault userpass 認證的使用者名稱 | `john.doe` | ✅ |
| `VAULT_PASSWORD` | Vault userpass 認證的密碼 | `your-secure-password` | ✅ |

#### 步驟 1.4：檢查檔案權限

為了安全起見，建議將 `.env` 檔案權限設為僅擁有者可讀寫：

```bash
chmod 600 .env
```

⚠️ **安全警告**：
- `.env` 檔案包含機敏資料，已加入 `.gitignore`，請勿納入版控
- 不要在公開的地方分享 `.env` 檔案內容
- 定期更換密碼，避免長期使用相同認證資訊

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

---

# 🗄️ SQL Server 權限管理工具

功能強大的 SQL Server 使用者與權限管理工具，支援批次處理、多層級權限管理和多種輸出格式。

## 功能特色

- ✅ **使用者管理**：建立使用者或更新現有使用者權限
- ✅ **多層級權限**：Server、Database、Object 三個層級
- ✅ **批次處理**：支援 CSV/JSON 格式批次設定
- ✅ **權限比對**：比較兩個使用者的權限差異
- ✅ **多種輸出格式**：JSON、Table、CSV
- ✅ **稽核日誌**：完整的操作記錄
- ✅ **自動依賴檢查**：自動偵測並安裝 sqlcmd 和 jq

## 系統需求

- **Bash**: 4.0+
- **sqlcmd**: SQL Server 命令列工具
- **jq**: JSON 處理工具（選用）

### 自動安裝依賴

```bash
# 執行安裝腳本（會自動偵測缺少的工具）
./install-tools.sh
```

## 快速開始

### 1. 設定環境變數

```bash
# 複製範本
cp .env.example .env

# 編輯 .env 檔案
nano .env
```

填入 SQL Server 連線資訊：

```bash
# SQL Server 連線資訊
SQL_SERVER=127.0.0.1
SQL_PORT=1433
ADMIN_USER=sa
ADMIN_PASSWORD=YourStrongPassword!

# 權限管理設定
DEFAULT_OUTPUT_FORMAT=table
ENABLE_AUDIT_LOG=true
AUDIT_LOG_FILE=./audit.log
```

### 2. 測試連線

```bash
./sql-permission.sh test-connection
```

## 主要功能

### 🔧 設定使用者與權限

`setup-user` 命令可用於建立新使用者或更新現有使用者的權限。

**命令別名**：`create-user`（向後兼容）

#### 建立新使用者（完整權限）

```bash
./sql-permission.sh setup-user \
  --users app_user \
  --databases MyAppDB \
  --password 'StrongP@ss123!' \
  --grant-read \
  --grant-write \
  --grant-execute
```

#### 為現有使用者授予額外權限

```bash
# 不需要密碼
./sql-permission.sh setup-user \
  --users existing_user \
  --databases MyAppDB \
  --grant-execute
```

#### 批次設定多個使用者

```bash
# 多個使用者 + 多個資料庫
./sql-permission.sh setup-user \
  --users "user1,user2,user3" \
  --databases "DB1,DB2,DB3" \
  --password 'TeamPass123!' \
  --grant-read \
  --grant-write
```

### 📊 查詢權限

```bash
# 查詢特定使用者權限（表格格式）
./sql-permission.sh get-user app_user --format table

# 查詢特定使用者在特定資料庫的權限
./sql-permission.sh get-user app_user --database MyAppDB --format table

# 查詢所有使用者權限
./sql-permission.sh get-all --format table

# 輸出到 CSV 檔案
./sql-permission.sh get-all --format csv --output permissions.csv
```

### ➕ 授予權限

```bash
# Server 層級角色
./sql-permission.sh grant user1 --server-role sysadmin

# Database 層級角色
./sql-permission.sh grant user2 \
  --database MyAppDB \
  --db-role db_datareader,db_datawriter

# 物件層級權限
./sql-permission.sh grant user3 \
  --database MyAppDB \
  --object dbo.Members \
  --permission SELECT,INSERT
```

### ➖ 撤銷權限

```bash
# 撤銷 Database 角色
./sql-permission.sh revoke user1 \
  --database MyAppDB \
  --db-role db_datawriter

# 撤銷物件權限
./sql-permission.sh revoke user2 \
  --database MyAppDB \
  --object dbo.Members \
  --permission INSERT
```

### 📦 批次處理

```bash
# 從 CSV 檔案批次授予權限
./sql-permission.sh grant-batch --file permissions.csv

# 命令列批次處理
./sql-permission.sh grant-batch \
  --users "user1,user2,user3" \
  --database MyAppDB \
  --db-role db_datareader
```

### 🔍 權限比對

```bash
# 比較兩個使用者的權限差異
./sql-permission.sh compare user1 user2

# 輸出到檔案
./sql-permission.sh compare user1 user2 --output diff-report.txt
```

### 📋 列出可用角色

```bash
# 列出 Server 層級角色
./sql-permission.sh list-server-roles

# 列出 Database 層級角色
./sql-permission.sh list-db-roles

# 列出特定資料庫的自訂角色
./sql-permission.sh list-db-roles --database MyAppDB
```

## 權限對照表

| 參數 | SQL Server 角色/權限 | 說明 |
|------|---------------------|------|
| `--grant-read` | `db_datareader` | SELECT 所有資料表和檢視表 |
| `--grant-write` | `db_datawriter` | INSERT、UPDATE、DELETE 所有資料表 |
| `--grant-execute` | `EXECUTE` | 執行所有預存程序和函數 |

## 常見使用場景

### 場景 1：新專案初始化

```bash
# 1. 建立資料庫
./create-database.sh --db MyAppDB

# 2. 設定應用程式使用者（完整權限）
./sql-permission.sh setup-user \
  --users app_user \
  --databases MyAppDB \
  --password 'App#Secure2024!' \
  --grant-read --grant-write --grant-execute

# 3. 設定報表使用者（唯讀）
./sql-permission.sh setup-user \
  --users report_user \
  --databases MyAppDB \
  --password 'Report#Secure2024!' \
  --grant-read

# 4. 驗證權限
./sql-permission.sh get-all --database MyAppDB --format table
```

### 場景 2：現有使用者權限升級

```bash
# 1. 查看現有權限
./sql-permission.sh get-user readonly_user --database MyAppDB

# 2. 授予執行權限（不需要密碼）
./sql-permission.sh setup-user \
  --users readonly_user \
  --databases MyAppDB \
  --grant-execute

# 3. 驗證新權限
./sql-permission.sh get-user readonly_user --database MyAppDB
```

### 場景 3：多環境部署

```bash
# 同一使用者部署到多個環境資料庫
./sql-permission.sh setup-user \
  --users api_service \
  --databases "DevDB,TestDB,ProductionDB" \
  --password 'ApiService#2024!' \
  --grant-read --grant-write
```

## 安全注意事項

1. **密碼強度**
   - 建議使用至少 12 字元，包含大小寫、數字、特殊符號
   - 範例：`Str0ng#Passw0rd!2024`

2. **權限最小化原則**
   - 僅授予必要的權限
   - 唯讀使用者不要授予寫入或執行權限
   - 測試環境和生產環境使用不同的使用者

3. **稽核日誌**
   - 所有權限變更操作都會記錄在 `audit.log`
   - 定期審查日誌，追蹤權限變更歷史

4. **環境變數管理**
   - `.env` 檔案已加入 `.gitignore`，絕不納入版控
   - 設定檔案權限：`chmod 600 .env`

## 疑難排解

### 問題：sqlcmd: command not found

執行安裝腳本：

```bash
./install-tools.sh
```

或手動安裝：

```bash
# Ubuntu/Debian
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18

# 加入 PATH
export PATH="$PATH:/opt/mssql-tools18/bin"
```

### 問題：連線失敗

1. 檢查 SQL Server 是否執行中
2. 確認 `.env` 中的連線資訊正確
3. 測試連線：
   ```bash
   ./sql-permission.sh test-connection
   ```

### 問題：密碼不符合策略

使用更強的密碼：
- 至少 8 個字元
- 包含大小寫字母、數字、特殊符號
- 範例：`StrongP@ssw0rd123!`

### 問題：權限授予失敗

1. 確認執行腳本的帳號有足夠權限（建議使用 `sa` 或有 `sysadmin` 權限的帳號）
2. 使用 `VERBOSE=true` 查看詳細錯誤：
   ```bash
   VERBOSE=true ./sql-permission.sh setup-user --users app_user ...
   ```

## 更多資訊

- 完整文檔：`.claude/CLAUDE.md`
- SQL 權限管理詳細說明：`SQL-PERMISSION-README.md`

---

## 授權

本專案僅供內部開發使用。

## 聯絡資訊

如有問題或建議，請聯絡開發團隊。
