# Vault Management Script - AI Agent Instructions

Bash 腳本工具集，整合 HashiCorp Vault (KV v2) 與 SQL Server 權限管理。

## 架構

**工作流程**：
```bash
# 方式 1：分步執行
./docker-init.sh DB1 DB2           # 啟動容器 + 建立資料庫
./docker-init.sh --init-vault      # 初始化 Vault userpass 認證（需 .env 檔案）

# 方式 2：一次完成（推薦）
./docker-init.sh --init-vault DB1 DB2  # 啟動容器 + 建立資料庫 + 初始化 Vault

# 使用者佈建
./main.sh --username user1 --databases DB1 --vault-paths /app/db1 --grant-read
```

**模組化** (`lib/`): 所有腳本用 `source "${SCRIPT_DIR}/lib/<module>.sh"` 載入共用函式
- `auth.sh`: 環境變數載入 (`load_env()`)、SQL 連線測試
- `utils.sh`: 顏色輸出 (`error()`, `success()`, `info()`) - **避免直接 `echo -e`**
- `parser.sh`: CSV/JSON 批次檔解析 → 管道分隔格式
- `query.sh`: SQL 三層權限查詢 (`get_user_permissions_full()`)
- `formatter.sh`: JSON/Table/CSV 輸出格式化

## 開發慣例

**每個腳本必須**：
```bash
set -euo pipefail  # 錯誤立即退出、未定義變數報錯、管道錯誤傳播
set -a; source .env; set +a  # 載入環境變數 (參考 .env.example)
```

**SQL 三層權限** (`sql-permission.sh`):
1. Server 層級: `sysadmin`, `securityadmin`
2. Database 層級: `db_datareader`, `db_datawriter`, `db_owner`
3. Object 層級: `SELECT`, `INSERT`, `UPDATE`, `DELETE`

**Vault KV v2 API** (`vault-manage.sh`):
- 讀寫: `/v1/<mount>/data/<path>` (注意 `/data/`)
- 刪除/清單: `/v1/<mount>/metadata/<path>`
- 認證: `POST /v1/auth/userpass/login/<user>` → `VAULT_TOKEN`

**CSV 批次格式** (`templates/permissions-template.csv`):
```csv
username,action,level,target,role_or_permission,database
user1,grant,server,,sysadmin,           # Server 層級: target/database 留空
app_user,grant,database,MyDB,db_datareader,MyDB  # 逗號數量必須正確
```
解析: `lib/parser.sh` 的 `parse_csv()` → 輸出 `user|action|level|...` 管道分隔

## 測試與除錯

```bash
# Dry-run 預覽 (不實際執行)
./sql-permission.sh grant user1 --server-role sysadmin --dry-run

# Docker 完整測試（一次完成）
./docker-init.sh --init-vault TestDB && ./main.sh --username test --databases TestDB --vault-paths /test --grant-read

# 檢查稽核日誌 (ENABLE_AUDIT_LOG=true)
tail -f audit.log
```

## 常見陷阱

- **sqlcmd PATH**: 安裝後需 `export PATH="$PATH:/opt/mssql-tools18/bin"` (執行 `./install-tools.sh`)
- **CSV 格式**: Server 層級必須保留空欄位 (`,sysadmin,`)，否則解析失敗
- **Vault Token**: 開發用 Root Token (`VAULT_TOKEN=myroot`) 不過期；生產需處理 renewal
