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
│   ├── get_*_roles()    查詢權限（3 層級）
│   ├── grant_*()        授予權限（3 層級）
│   └── revoke_*()       撤銷權限（3 層級）
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
