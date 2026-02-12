# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

本專案包含三個獨立的 Shell Script 管理工具：

1. **vault-manage.sh** - HashiCorp Vault KV secrets 管理工具（單體架構）
2. **sql-permission.sh** - SQL Server 權限管理工具（模組化架構）
3. **install-tools.sh** - 依賴工具自動安裝腳本

## 架構設計

### 單體 vs 模組化

**vault-manage.sh（單體架構）**
- 所有功能實作在單一檔案中
- 約 700 行程式碼
- 適合獨立部署和使用

**sql-permission.sh（模組化架構）**
- 主程式 + 5 個函式庫模組
- 使用 `source` 載入模組：auth.sh, query.sh, parser.sh, formatter.sh, utils.sh
- 支援複雜的批次處理、多層級權限管理和多種輸出格式

### 模組化設計（sql-permission.sh）

```
sql-permission.sh (主程式)
├── lib/auth.sh          認證與 SQL 執行
│   ├── load_env()       載入環境變數
│   ├── test_connection() 測試連線
│   └── execute_sql*()   SQL 執行包裝函式（3 種變體）
├── lib/query.sh         查詢與權限管理
│   ├── create_login()   建立 Server 層級 Login
│   ├── create_user()    建立 Database 層級 User
│   ├── get_*_roles()    查詢權限（3 層級）
│   ├── grant_*()        授予權限（3 層級）
│   ├── revoke_*()       撤銷權限（3 層級）
│   └── grant_execute_permission() 授予 EXECUTE 權限
├── lib/parser.sh        批次處理
│   ├── parse_csv()      CSV 解析器
│   ├── parse_json()     JSON 解析器
│   └── process_batch*() 批次引擎
├── lib/formatter.sh     輸出格式化
│   ├── format_*_json()  JSON 輸出
│   ├── format_*_table() 表格輸出
│   └── format_*_csv()   CSV 輸出
└── lib/utils.sh         工具函式
    ├── show_*()         訊息顯示函式
    ├── validate_*()     參數驗證
    └── write_audit_log() 稽核日誌
```

### 依賴檢查機制

兩個主要工具都實作了自動依賴檢查：

```bash
# 在腳本開頭執行
check_and_install_dependencies()
  ├── 檢查 sqlcmd/curl/jq 是否存在
  ├── 偵測到缺少時詢問使用者
  └── 自動執行 ./install-tools.sh
```

## 環境變數管理

### 統一的 .env 結構

所有工具共用 `.env` 檔案，包含三個區塊：

```bash
# Vault 設定（vault-manage.sh 使用）
VAULT_ADDR=...
VAULT_USERNAME=...
VAULT_PASSWORD=...

# SQL Server 連線（兩個 SQL 工具共用）
SQL_SERVER=...
ADMIN_USER=...
ADMIN_PASSWORD=...

# sql-permission.sh 特定設定
DEFAULT_OUTPUT_FORMAT=table
ENABLE_AUDIT_LOG=true
AUDIT_LOG_FILE=./audit.log
```

### 載入方式

所有腳本使用相同的載入模式：
```bash
set -a
source .env
set +a
```

## 常用命令

### 依賴工具安裝

```bash
# 安裝所有工具（預設：sqlcmd + jq）
./install-tools.sh

# 僅安裝特定工具
./install-tools.sh --sqlcmd-only
./install-tools.sh --jq-only
```

### Vault 管理

```bash
# 基本 CRUD
./vault-manage.sh get secrets path/to/secret
./vault-manage.sh create secrets path/to/secret key1=value1 key2=value2
./vault-manage.sh update secrets path/to/secret key3=value3
./vault-manage.sh delete secrets path/to/secret

# 列出 secrets
./vault-manage.sh list secrets path

# 切換輸出格式
./vault-manage.sh get secrets path --format table
```

### SQL Server 權限管理

```bash
# 設定使用者並授予權限（支援建立新使用者或更新現有使用者權限）
./sql-permission.sh setup-user --users app_user --databases MyAppDB \
  --password 'StrongP@ss123!' --grant-read --grant-write --grant-execute

./sql-permission.sh setup-user --users "user1,user2" --databases "DB1,DB2" \
  --password 'StrongP@ss123!' --grant-read --grant-write --grant-execute

# 為現有使用者授予額外權限（不需要密碼）
./sql-permission.sh setup-user --users existing_user --databases MyAppDB \
  --grant-execute

# 查詢權限（支援 3 種格式：json/table/csv）
./sql-permission.sh get-user <username> --format table
./sql-permission.sh get-all --format csv --output all-permissions.csv

# 授予權限（3 個層級）
./sql-permission.sh grant <user> --server-role sysadmin
./sql-permission.sh grant <user> --database MyDB --db-role db_datareader,db_datawriter
./sql-permission.sh grant <user> --database MyDB --object dbo.Table --permission SELECT,INSERT

# 批次處理
./sql-permission.sh grant-batch --file permissions.csv
./sql-permission.sh grant-batch --users "u1,u2,u3" --database MyDB --role db_datareader

# 權限比對
./sql-permission.sh compare user1 user2
```

## 程式碼規範

### Shell Script 最佳實踐

1. **錯誤處理**
   - 使用 `set -e` 和 `set -o pipefail`
   - 所有函式返回適當的退出碼
   - 使用 `show_error()` 統一錯誤訊息格式

2. **參數驗證**
   - 所有使用者輸入必須經過 `validate_*()` 函式驗證
   - 防止 SQL Injection：檢查特殊字元 `[;\'\"\`\$]`

3. **顏色輸出**
   - 統一使用預定義的顏色變數：`RED`, `GREEN`, `YELLOW`, `BLUE`, `CYAN`, `NC`
   - 錯誤訊息使用 `RED`，成功訊息使用 `GREEN`

4. **稽核日誌**
   - 所有權限變更操作必須呼叫 `write_audit_log()`
   - 格式：`timestamp [INFO] User: xxx | Action: xxx | Target: xxx | Details: xxx`

### SQL 執行模式

sql-permission.sh 提供 3 種 SQL 執行函式：

```bash
execute_sql()         # 返回結果，支援格式化
execute_sql_quiet()   # 僅返回成功/失敗
execute_sql_scalar()  # 返回單一值
```

選擇原則：
- 需要處理查詢結果 → `execute_sql()`
- 僅需成功/失敗 → `execute_sql_quiet()`
- 取得單一值（如 COUNT） → `execute_sql_scalar()`

## 批次處理檔案格式

### CSV 格式

```csv
username,action,level,target,role_or_permission,database
user1,grant,server,,sysadmin,
user2,grant,database,MyDB,db_datareader,MyDB
user3,grant,object,dbo.Table,SELECT,MyDB
```

### JSON 格式

```json
{
  "permissions": [
    {
      "username": "user1",
      "action": "grant",
      "level": "server",
      "role": "sysadmin"
    },
    {
      "username": "user2",
      "action": "grant",
      "level": "database",
      "database": "MyDB",
      "roles": ["db_datareader", "db_datawriter"]
    }
  ]
}
```

範本檔案位於 `templates/` 目錄。

## 測試指南

### 連線測試

```bash
# Vault 連線測試
./vault-manage.sh list secrets /  # 列出根目錄

# SQL Server 連線測試
./sql-permission.sh test-connection
```

### 功能測試流程

1. **設定環境**
   ```bash
   cp .env.example .env
   nano .env  # 填入實際連線資訊
   chmod 600 .env
   ```

2. **測試基本功能**
   - Vault: 建立 → 讀取 → 更新 → 刪除
   - SQL: 查詢 → 授予 → 驗證 → 撤銷

3. **測試批次處理**
   - 準備測試 CSV/JSON 檔案
   - 執行 grant-batch
   - 驗證權限正確性

## 使用者管理功能

### setup-user 命令

`setup-user` 命令提供快速設定 SQL Server 使用者並授予權限的功能。可用於建立新使用者或更新現有使用者的權限。

**命令別名**：`create-user`（向後兼容）

#### 主要特性

- ✅ 支援建立新使用者或更新現有使用者權限
- ✅ 支援同時處理多個使用者（逗號分隔）
- ✅ 支援同時在多個資料庫設定使用者（逗號分隔）
- ✅ 自動檢查使用者和資料庫是否存在（避免重複建立）
- ✅ 提供三種權限選項：讀取、寫入、執行預存程序
- ✅ 操作前確認機制（防止誤操作）
- ✅ 完成後自動顯示權限摘要

#### 基本用法

```bash
# 設定單一使用者（完整權限）
./sql-permission.sh setup-user \
  --users app_user \
  --databases MyAppDB \
  --password 'StrongP@ss123!' \
  --grant-read \
  --grant-write \
  --grant-execute

# 設定多個使用者，多個資料庫
./sql-permission.sh setup-user \
  --users "user1,user2,user3" \
  --databases "DB1,DB2,DB3" \
  --password 'StrongP@ss123!' \
  --grant-read \
  --grant-write \
  --grant-execute

# 設定唯讀使用者
./sql-permission.sh setup-user \
  --users readonly_user \
  --databases MyAppDB \
  --password 'ReadOnly123!' \
  --grant-read

# 設定讀寫使用者（無執行權限）
./sql-permission.sh setup-user \
  --users dataentry_user \
  --databases MyAppDB \
  --password 'DataEntry123!' \
  --grant-read \
  --grant-write

# 為現有使用者授予額外權限（不需密碼）
./sql-permission.sh setup-user \
  --users existing_user \
  --databases MyAppDB \
  --grant-execute
```

#### 參數說明

| 參數 | 必要 | 說明 |
|------|------|------|
| `--users` | ✅ | 使用者名稱（可用逗號分隔多個） |
| `--databases` | ✅ | 資料庫名稱（可用逗號分隔多個） |
| `--password` | 條件 | 使用者密碼（建立新使用者時必填，更新現有使用者時可省略） |
| `--grant-read` | ❌ | 授予讀取權限（db_datareader） |
| `--grant-write` | ❌ | 授予寫入權限（db_datawriter） |
| `--grant-execute` | ❌ | 授予執行預存程序權限（EXECUTE） |

#### 權限對照

| 參數 | SQL Server 角色/權限 | 說明 |
|------|---------------------|------|
| `--grant-read` | `db_datareader` | SELECT 所有資料表和檢視表 |
| `--grant-write` | `db_datawriter` | INSERT, UPDATE, DELETE 所有資料表 |
| `--grant-execute` | `EXECUTE` | 執行所有預存程序和函數 |

#### 執行流程

1. **檢查/建立 Login** - 檢查 Server 層級登入帳號是否存在，不存在則建立
2. **檢查/建立 User** - 檢查每個資料庫的使用者是否存在，不存在則建立
3. **授予權限** - 根據選項授予對應的權限（無論使用者是否已存在）
4. **顯示摘要** - 列出每個使用者在每個資料庫的最終權限狀態

#### 使用範例場景

**場景 1：新專案初始化**
```bash
# 設定應用程式使用者
./sql-permission.sh setup-user \
  --users prod_app_user \
  --databases ProductionDB \
  --password 'App#Secure2024!' \
  --grant-read --grant-write --grant-execute

# 設定報表使用者
./sql-permission.sh setup-user \
  --users prod_report_user \
  --databases ProductionDB \
  --password 'Report#Secure2024!' \
  --grant-read
```

**場景 2：多環境部署**
```bash
# 同一使用者部署到多個環境資料庫
./sql-permission.sh setup-user \
  --users api_user \
  --databases "DevDB,StagingDB,ProductionDB" \
  --password 'ApiUser#2024!' \
  --grant-read --grant-write
```

**場景 3：團隊成員帳號**
```bash
# 為團隊成員批次建立開發帳號
./sql-permission.sh setup-user \
  --users "dev1,dev2,dev3,dev4" \
  --databases "DevDB,TestDB" \
  --password 'DevTeam#2024!' \
  --grant-read --grant-write --grant-execute
```

**場景 4：為現有使用者授予額外權限**
```bash
# 為現有的唯讀使用者追加執行權限
./sql-permission.sh setup-user \
  --users readonly_user \
  --databases ProductionDB \
  --grant-execute

# 為現有使用者在新資料庫設定權限
./sql-permission.sh setup-user \
  --users existing_user \
  --databases NewDB \
  --grant-read --grant-write
```

### 常見問題與疑難排解

#### 問題 1：Login 已存在

**情況**：
```
⚠ 警告: Login 'app_user' 已存在，跳過建立
```

**說明**：這是正常訊息，表示 Login 已存在於 Server 層級，腳本會自動跳過建立步驟。

**處理方式**：
- 如果是為現有使用者授予權限，這是預期行為
- 腳本會繼續執行，為使用者授予新的權限
- 如果想要重新建立使用者，需要先手動刪除：
  ```sql
  DROP LOGIN [app_user];
  ```

#### 問題 2：User 已存在

**情況**：
```
⚠ 警告: User 'app_user' 在資料庫 'MyAppDB' 已存在，跳過建立
```

**說明**：這是正常訊息，表示 User 已存在於該資料庫。

**處理方式**：
- 腳本會繼續執行，為現有使用者授予新的權限
- 權限是累加的，不會移除現有權限
- 如果想要重設權限，需要先使用 `revoke` 命令撤銷現有權限

#### 問題 3：資料庫不存在

**錯誤訊息**：
```
✗ 錯誤: 資料庫 'NonExistentDB' 不存在
```

**解決方案**：
- 先建立資料庫：
  ```bash
  ./create-database.sh --db NonExistentDB
  ```
- 或者修改 `--databases` 參數使用已存在的資料庫

#### 問題 4：密碼不符合策略

**錯誤訊息**：
```
Password validation failed. The password does not meet SQL Server password policy requirements...
```

**解決方案**：
- 使用更強的密碼（至少 8 個字元，包含大小寫字母、數字、特殊符號）
- 範例：`StrongP@ssw0rd123!`
- 檢查 SQL Server 的密碼策略設定

#### 問題 5：權限授予失敗

**錯誤訊息**：
```
✗ 錯誤: 授予 Database 角色失敗
```

**可能原因**：
1. 執行腳本的帳號沒有足夠權限
2. 資料庫角色名稱錯誤
3. 使用者不存在於該資料庫

**解決方案**：
1. 確認 `.env` 中的 `ADMIN_USER` 有 `sysadmin` 權限
2. 檢查角色名稱拼寫（使用 `./sql-permission.sh list-db-roles` 查看可用角色）
3. 使用 `VERBOSE=true` 查看詳細錯誤訊息：
   ```bash
   VERBOSE=true ./sql-permission.sh setup-user --users app_user ...
   ```

### 完整工作流程範例

#### 工作流程 1：新專案三種角色設定

```bash
# 1. 確認資料庫已存在
./sql-permission.sh test-connection

# 2. 建立應用程式使用者（完整權限）
./sql-permission.sh setup-user \
  --users prod_app_user \
  --databases ProductionDB \
  --password 'App#Secure2024!' \
  --grant-read \
  --grant-write \
  --grant-execute

# 3. 建立 API 使用者（讀寫權限）
./sql-permission.sh setup-user \
  --users prod_api_user \
  --databases ProductionDB \
  --password 'Api#Secure2024!' \
  --grant-read \
  --grant-write

# 4. 建立報表使用者（唯讀權限）
./sql-permission.sh setup-user \
  --users prod_report_user \
  --databases ProductionDB \
  --password 'Report#Secure2024!' \
  --grant-read

# 5. 驗證所有使用者權限
./sql-permission.sh get-all --database ProductionDB --format table

# 6. 比較使用者權限
./sql-permission.sh compare prod_app_user prod_api_user
./sql-permission.sh compare prod_api_user prod_report_user
```

#### 工作流程 2：現有使用者權限升級

```bash
# 1. 查看現有權限
./sql-permission.sh get-user readonly_user --database MyAppDB --format table

# 2. 為唯讀使用者授予執行權限（不需要密碼）
./sql-permission.sh setup-user \
  --users readonly_user \
  --databases MyAppDB \
  --grant-execute

# 3. 驗證新權限
./sql-permission.sh get-user readonly_user --database MyAppDB --format table
```

#### 工作流程 3：多環境部署

```bash
# 在開發、測試、生產環境同時設定相同使用者
./sql-permission.sh setup-user \
  --users api_service \
  --databases "DevDB,TestDB,ProductionDB" \
  --password 'ApiService#2024!' \
  --grant-read \
  --grant-write \
  --grant-execute

# 分別驗證各環境權限
./sql-permission.sh get-user api_service --database DevDB --format table
./sql-permission.sh get-user api_service --database TestDB --format table
./sql-permission.sh get-user api_service --database ProductionDB --format table
```

### 與其他命令的整合

#### 與 create-database.sh 整合

```bash
# 1. 建立資料庫
./create-database.sh --db MyNewDB --data-size 200 --data-growth 100

# 2. 設定使用者並授予權限
./sql-permission.sh setup-user \
  --users app_user \
  --databases MyNewDB \
  --password 'NewDB#Pass2024!' \
  --grant-read \
  --grant-write \
  --grant-execute

# 3. 驗證
./sql-permission.sh get-user app_user --database MyNewDB --format table
```

#### 批次處理

如果需要設定大量使用者，建議使用批次處理功能：

```bash
# 先設定使用者
./sql-permission.sh setup-user \
  --users "user1,user2,user3,user4,user5" \
  --databases MyAppDB \
  --password 'Batch#Pass2024!' \
  --grant-read \
  --grant-write

# 然後用 grant-batch 授予不同的權限
./sql-permission.sh grant-batch --file custom-permissions.csv
```

### 常用命令速查

#### 標準使用模式

| 使用場景 | 命令 |
|---------|------|
| 應用程式使用者 | `setup-user --users app_user --databases MyDB --password 'Pass!' --grant-read --grant-write --grant-execute` |
| API 使用者 | `setup-user --users api_user --databases MyDB --password 'Pass!' --grant-read --grant-write` |
| 報表使用者 | `setup-user --users report_user --databases MyDB --password 'Pass!' --grant-read` |
| 權限升級 | `setup-user --users existing_user --databases MyDB --grant-execute` |
| 多環境部署 | `setup-user --users app_user --databases "DB1,DB2,DB3" --password 'Pass!' --grant-read --grant-write` |

#### 驗證命令

```bash
# 查看使用者權限
./sql-permission.sh get-user <username> --database <dbname> --format table

# 測試連線
sqlcmd -S 127.0.0.1,1433 -U <username> -P '<password>' -C -Q "SELECT @@VERSION;"

# 查看所有使用者
./sql-permission.sh get-all --format table

# 比較權限
./sql-permission.sh compare user1 user2
```

## 安全考量

### 機敏資料處理

- `.env` 已加入 `.gitignore`，絕不納入版控
- 密碼不出現在命令列參數（避免 shell history）
- 密碼不出現在日誌或錯誤訊息中
- Token 僅存在於記憶體，不寫入檔案

### 檔案權限

```bash
chmod 600 .env          # 環境變數（僅擁有者可讀寫）
chmod 755 *.sh          # 腳本（可執行）
chmod 644 lib/*.sh      # 函式庫（可讀）
```

## 新增功能指南

### 新增 SQL 權限管理命令

1. **在 lib/query.sh 實作核心函式**
   ```bash
   your_new_function() {
       local param1="$1"
       validate_username "$param1"

       local sql="SELECT ..."
       execute_sql "database" "$sql" "csv"
   }
   ```

2. **在 sql-permission.sh 新增命令處理函式**
   ```bash
   cmd_your_command() {
       # 解析參數
       # 呼叫 lib/query.sh 的函式
       # 格式化輸出
   }
   ```

3. **在 main() 新增路由**
   ```bash
   case $command in
       your-command)
           cmd_your_command "$@"
           ;;
   esac
   ```

4. **更新 help 訊息**

### 新增輸出格式

在 `lib/formatter.sh` 實作新的格式化函式：
```bash
format_your_format() {
    # 接收資料
    # 轉換格式
    # 輸出
}
```

## 疑難排解

### 模組載入失敗

確認所有 lib/*.sh 檔案存在且可讀：
```bash
ls -l lib/
```

### SQL 執行失敗

1. 檢查 sqlcmd 是否在 PATH 中
2. 開啟 VERBOSE 模式查看詳細 SQL：
   ```bash
   VERBOSE=true ./sql-permission.sh ...
   ```

### 批次處理失敗

1. 驗證檔案格式（CSV/JSON 結構）
2. 檢查欄位名稱是否正確
3. 使用 `--dry-run` 模式預覽變更
