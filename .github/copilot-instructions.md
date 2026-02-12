# Vault Management Script - AI Agent Instructions

## 專案概述

這是一套管理 **HashiCorp Vault** 和 **SQL Server** 的 Bash 腳本工具集，主要功能：
- **Vault 管理**：KV secrets 的 CRUD 操作、userpass 認證
- **SQL Server 權限管理**：查詢與授予 Server/Database/Object 層級權限
- **自動化佈建**：產生密碼、建立 SQL 使用者並存入 Vault

## 核心架構

### 主要腳本流程

```
docker-init.sh          # 啟動 SQL Server + Vault 容器
    ↓
vault-init.sh           # 初始化 Vault (啟用 userpass、建立管理員)
    ↓
provision-db-user.sh    # 整合工作流程
    ├─ sql-permission.sh    # 建立 SQL 使用者並授權
    └─ vault-manage.sh      # 將帳密存入 Vault
```

### 模組化設計 (`lib/`)

所有腳本遵循模組化設計，共用函式庫位於 `lib/` 目錄：

- **`auth.sh`**: 環境變數載入、SQL Server 連線測試、SQL 執行包裝
- **`formatter.sh`**: 輸出格式化（JSON/Table/CSV）
- **`parser.sh`**: 批次檔解析（CSV/JSON 格式）
- **`query.sh`**: SQL 查詢建構器（Server/Database/Object 層級權限查詢）
- **`utils.sh`**: 通用工具函式（顏色輸出、檔案驗證、稽核日誌）

**載入模式**：所有主腳本在頂部使用 `source "${SCRIPT_DIR}/lib/<module>.sh"` 載入必要模組。

## 關鍵開發規範

### 1. 環境變數管理

**必須從 `.env` 檔案載入**，使用標準模式：

```bash
set -a
source .env
set +a
```

**必要變數（Vault）**：
- `VAULT_ADDR`, `VAULT_USERNAME`, `VAULT_PASSWORD`, `VAULT_TOKEN`

**必要變數（SQL Server）**：
- `SQL_SERVER`, `SQL_PORT`, `ADMIN_USER`, `ADMIN_PASSWORD`

**範例**：參考 [`.env.example`](.env.example) 的完整配置。

### 2. 錯誤處理與 Bash 最佳實踐

所有腳本必須遵循：

```bash
set -euo pipefail  # 錯誤立即退出 + 未定義變數報錯 + 管道錯誤傳播
```

**顏色輸出標準**：使用 `utils.sh` 提供的 `error()`, `success()`, `info()`, `warning()` 函式，避免直接 `echo -e`。

### 3. SQL 權限層級架構

SQL Server 權限分三層（對應 `sql-permission.sh`）：

1. **Server 層級**：`sysadmin`, `securityadmin` 等 Server Role
2. **Database 層級**：`db_datareader`, `db_datawriter`, `db_owner` 等 Database Role
3. **Object 層級**：`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `EXECUTE` 等物件權限

**查詢邏輯**：參考 `lib/query.sh` 的 `get_user_permissions_full()` 函式，整合所有層級權限為 JSON 結構。

### 4. 批次處理格式

**CSV 格式** (`templates/permissions-template.csv`):
```csv
username,action,level,target,role_or_permission,database
user1,grant,server,,sysadmin,
app_user,grant,database,MyAppDB,db_datareader,MyAppDB
```

**JSON 格式** (`templates/permissions-template.json`):
```json
{
  "permissions": [
    {"username": "user1", "action": "grant", "level": "server", "role": "sysadmin"},
    {"username": "app_user", "action": "grant", "level": "database", "database": "MyAppDB", "roles": ["db_datareader"]}
  ]
}
```

**解析器**：使用 `lib/parser.sh` 的 `parse_csv()` 或 `parse_json()` 函式，輸出統一的管道分隔格式 (`username|action|level|...`)。

### 5. Vault KV Secrets 操作模式

**API 端點規則** (KV v2):
- **寫入/讀取**: `/v1/<mount>/data/<path>`
- **刪除/清單**: `/v1/<mount>/metadata/<path>`

**認證流程** (`vault-manage.sh`):
```bash
# 1. Userpass 登入取得 Token
POST /v1/auth/userpass/login/<username>

# 2. 使用 Token 操作 Secrets
curl -H "X-Vault-Token: $VAULT_TOKEN" ...
```

**範例**：參考 `vault-manage.sh` 的 `vault_write_secret()` 和 `vault_read_secret()` 函式。

## 開發工作流程

### 本地環境啟動

```bash
# 1. 啟動容器並建立資料庫
./docker-init.sh MyAppDB TestDB

# 2. 初始化 Vault
./vault-init.sh

# 3. 驗證環境
./vault-manage.sh get /test/path --format table
./sql-permission.sh get-user sa --format table
```

### 新增功能檢查清單

添加新腳本或模組時：

1. **錯誤處理**：加入 `set -euo pipefail` 和依賴檢查（`check_dependencies()`）
2. **環境變數**：使用 `load_env()` 函式，遵循 `.env.example` 格式
3. **模組化**：可重用邏輯抽到 `lib/` 目錄
4. **文檔**：在腳本頂部加入功能說明、使用範例、需求清單
5. **顏色輸出**：使用 `lib/utils.sh` 的標準函式
6. **測試**：在 Docker 環境中驗證完整流程

### 測試腳本

**不存在專用測試框架**。驗證方式：
1. 使用 `--dry-run` 選項預覽操作（`sql-permission.sh`, `provision-db-user.sh` 支援）
2. 在 Docker 環境中執行完整流程
3. 檢查稽核日誌（若 `ENABLE_AUDIT_LOG=true`）

## 常見陷阱

### 1. sqlcmd PATH 問題

`sqlcmd` 安裝後需手動加入 PATH：

```bash
export PATH="$PATH:/opt/mssql-tools/bin:/opt/mssql-tools18/bin"
```

腳本會自動提示執行 `install-tools.sh` 安裝依賴。

### 2. Vault Token 過期

開發環境使用 Root Token 不會過期，生產環境需處理 Token Renewal：

```bash
# 檢查 Token TTL
curl -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/auth/token/lookup-self | jq .data.ttl
```

### 3. 批次檔格式錯誤

CSV 解析器對格式敏感，**逗號數量必須正確**：

- ✅ `user1,grant,server,,sysadmin,`（Server 層級 target/database 為空）
- ❌ `user1,grant,server,sysadmin`（缺少 target/database 欄位）

## 外部依賴

- **Docker Compose**: 管理 SQL Server + Vault 容器
- **curl**: HTTP API 呼叫
- **jq**: JSON 解析與格式化
- **sqlcmd**: SQL Server 命令列工具（由 `install-tools.sh` 安裝）
- **openssl**: 產生強密碼（`provision-db-user.sh`）

## 相關檔案索引

- 環境配置：[`.env.example`](.env.example)
- Docker 服務：[`docker-compose.yml`](docker-compose.yml)
- Vault 操作：[`vault-manage.sh`](vault-manage.sh), [`vault-init.sh`](vault-init.sh)
- SQL 權限：[`sql-permission.sh`](sql-permission.sh)
- 整合流程：[`provision-db-user.sh`](provision-db-user.sh)
- 批次範本：[`templates/`](templates/)
