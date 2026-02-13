# Vault Management Script

Bash 腳本工具集，整合 HashiCorp Vault (KV v2) 與 SQL Server 權限管理，提供自動化的使用者佈建流程。

## 功能特色

- ✅ **自動產生強密碼**：使用 OpenSSL 產生符合安全標準的隨機密碼
- ✅ **SQL Server 使用者管理**：自動建立 Login/User 並授予資料庫權限
- ✅ **Vault 整合**：將帳號密碼安全地存入 HashiCorp Vault
- ✅ **批次佈建**：支援一次設定多個資料庫和 Vault 路徑
- ✅ **預覽模式**：提供 `--dry-run` 選項，可在不實際執行的情況下預覽操作

## 架構說明

```
main.sh                    # 主要腳本：整合 SQL 使用者建立與 Vault 管理
├── sql-permission.sh      # SQL Server 權限管理
├── vault-manage.sh        # Vault KV v2 操作
└── lib/                   # 共用函式庫
    ├── auth.sh           # 環境變數載入、SQL 連線測試
    ├── utils.sh          # 工具函式（顏色輸出、錯誤處理）
    ├── parser.sh         # CSV/JSON 批次檔解析
    ├── query.sh          # SQL 權限查詢
    └── formatter.sh      # 輸出格式化
```

## 前置需求

### 必要工具

- Bash 4.0+
- OpenSSL（用於產生密碼）
- sqlcmd（SQL Server 命令列工具）
- curl（用於 Vault API 呼叫）

### 安裝工具

```bash
# 執行安裝腳本
./install-tools.sh
```

### 環境需求

- SQL Server 2019+（或使用 Docker）
- HashiCorp Vault（或使用 Docker）

## 快速開始

### 1. 設定環境變數

複製環境變數範本並填入實際值：

```bash
cp .env.example .env
nano .env  # 編輯環境變數
```

環境變數說明：

```bash
# SQL Server 設定
SQL_SERVER=localhost
SQL_PORT=1433
ADMIN_USER=sa
ADMIN_PASSWORD=YourStrong@Passw0rd

# Vault 設定
VAULT_ADDR=http://localhost:8200
VAULT_USERNAME=admin
VAULT_PASSWORD=admin_password
VAULT_SKIP_VERIFY=true  # 開發環境可設為 true
```

### 2. 啟動環境（Docker 方式）

```bash
# 方式 1：分步執行
./docker-init.sh DB1 DB2           # 啟動容器 + 建立資料庫
./docker-init.sh --init-vault      # 初始化 Vault userpass 認證

# 方式 2：一次完成（推薦）
./docker-init.sh --init-vault DB1 DB2
```

### 3. 建立使用者並授予權限

```bash
./main.sh \
  --username app_user \
  --databases "MyAppDB,TestDB" \
  --vault-paths "teams/app/qa/db-user,teams/app/dev/db-user" \
  --grant-read \
  --grant-write
```

## 使用方法

### 基本語法

```bash
./main.sh [選項]
```

### 必要選項

| 選項 | 說明 | 範例 |
|------|------|------|
| `--username` | 使用者帳號（單一帳號） | `--username app_user` |
| `--databases` | 資料庫清單（逗號分隔） | `--databases "DB1,DB2"` |
| `--vault-paths` | Vault Secret 路徑清單（逗號分隔） | `--vault-paths "path1,path2"` |

### 權限選項

| 選項 | 說明 |
|------|------|
| `--grant-read` | 授予讀取權限 (db_datareader) |
| `--grant-write` | 授予寫入權限 (db_datawriter) |
| `--grant-execute` | 授予執行預存程序權限 (EXECUTE) |

### 密碼選項

| 選項 | 說明 | 預設值 |
|------|------|--------|
| `--password` | 手動指定密碼 | 自動產生 |
| `--password-length` | 密碼長度 | 32 |

### 其他選項

| 選項 | 說明 | 預設值 |
|------|------|--------|
| `--vault-mount` | Vault mount point | secrets |
| `--dry-run` | 預覽操作但不實際執行 | - |
| `-h, --help` | 顯示說明 | - |

## 使用範例

### 範例 1：建立讀寫使用者

```bash
./main.sh \
  --username app_user \
  --databases "MyAppDB,TestDB" \
  --vault-paths "teams/job-finder/qa/db-user,teams/job-finder/dev/db-user" \
  --grant-read \
  --grant-write
```

### 範例 2：建立唯讀使用者

```bash
./main.sh \
  --username report_user \
  --databases "MyAppDB" \
  --vault-paths "teams/reports/db-user" \
  --grant-read
```

### 範例 3：使用自訂密碼

```bash
./main.sh \
  --username api_user \
  --databases "MyAppDB" \
  --vault-paths "teams/api/db-user" \
  --password "MyStrongP@ssw0rd!" \
  --grant-read \
  --grant-write \
  --grant-execute
```

### 範例 4：預覽模式

```bash
./main.sh \
  --username test_user \
  --databases "TestDB" \
  --vault-paths "teams/test/db-user" \
  --grant-read \
  --dry-run
```

## 工作流程

當您執行 `main.sh` 時，腳本會依序完成以下步驟：

```
步驟 1/3: 準備密碼
  └─ 產生強密碼（或使用指定密碼）

步驟 2/3: 建立 SQL Server 使用者並授予權限
  └─ 呼叫 sql-permission.sh
     ├─ 建立 SQL Server Login
     ├─ 在指定資料庫建立 User
     └─ 授予指定權限

步驟 3/3: 將帳號密碼存入 Vault
  └─ 呼叫 vault-manage.sh
     ├─ 檢查 Secret 是否存在
     ├─ 存在則更新 (update)
     └─ 不存在則建立 (create)
```

## SQL Server 權限說明

### 三層權限架構

1. **Server 層級**：`sysadmin`, `securityadmin`
2. **Database 層級**：`db_datareader`, `db_datawriter`, `db_owner`
3. **Object 層級**：`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `EXECUTE`

### 權限對應

| 選項 | SQL 權限 | 說明 |
|------|----------|------|
| `--grant-read` | `db_datareader` | 可讀取資料表資料 |
| `--grant-write` | `db_datawriter` | 可寫入資料表資料 |
| `--grant-execute` | `EXECUTE` | 可執行預存程序 |

## Vault 整合

### Vault KV v2 API

- **讀寫路徑**：`/v1/<mount>/data/<path>`
- **刪除/清單路徑**：`/v1/<mount>/metadata/<path>`
- **預設 mount point**：`secrets`

### 存取 Vault Secret

```bash
# 使用 vault-manage.sh 讀取
./vault-manage.sh get secrets teams/app/db-user

# 使用 Vault CLI
vault kv get secrets/teams/app/db-user
```

## 除錯與測試

### 預覽模式

使用 `--dry-run` 選項可以在不實際執行的情況下預覽操作：

```bash
./main.sh \
  --username test_user \
  --databases "TestDB" \
  --vault-paths "teams/test/db-user" \
  --grant-read \
  --dry-run
```

### Docker 完整測試

```bash
# 一次完成：啟動環境 + 建立測試使用者
./docker-init.sh --init-vault TestDB && \
./main.sh \
  --username test \
  --databases TestDB \
  --vault-paths /test \
  --grant-read
```

### 檢查稽核日誌

在 `.env` 中設定 `ENABLE_AUDIT_LOG=true`，然後檢查日誌：

```bash
tail -f audit.log
```

## 常見問題

### Q: sqlcmd 找不到命令

**A:** 需要將 sqlcmd 加入 PATH：

```bash
export PATH="$PATH:/opt/mssql-tools18/bin"

# 或執行安裝腳本
./install-tools.sh
```

### Q: Vault Token 過期

**A:** 開發環境可使用 Root Token（不會過期）：

```bash
# 在 .env 中設定
VAULT_TOKEN=myroot
```

生產環境需要實作 Token renewal 機制。

### Q: CSV 批次檔格式錯誤

**A:** Server 層級權限必須保留空欄位，範例：

```csv
username,action,level,target,role_or_permission,database
user1,grant,server,,sysadmin,
```

注意 `target` 和 `database` 欄位為空，但逗號必須保留。

## 相關文件

- [開發規範](.claude/CLAUDE.md)
- [環境變數範本](.env.example)
- [CSV 批次範本](templates/permissions-template.csv)

## 授權

MIT License

## 作者

DevOps Team
