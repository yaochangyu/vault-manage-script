# SQL Server 權限管理工具

完整的 SQL Server 權限管理命令列工具，使用 Shell Script 實作，支援多層級權限管理、批次操作與權限比對功能。

## 功能特色

- ✅ **多層級權限查詢**：Server / Database / 物件層級
- ✅ **權限設定**：授予 / 撤銷權限
- ✅ **批次處理**：支援 CSV 和 JSON 格式
- ✅ **多種輸出格式**：JSON / 表格 / CSV
- ✅ **權限比對**：比較兩個使用者的權限差異
- ✅ **稽核日誌**：記錄所有權限變更操作
- ✅ **安全設計**：機敏資料完全隔離，不納入版控

## 系統需求

- **Bash**: 4.0+
- **sqlcmd**: Microsoft SQL Server 命令列工具
- **jq**: JSON 處理工具（選用，用於 JSON 格式輸出）

### 安裝依賴工具

使用自動安裝腳本一鍵安裝所有依賴工具：

```bash
# 安裝所有工具（sqlcmd + jq）- 預設行為
./install-tools.sh

# 或僅安裝 sqlcmd
./install-tools.sh --sqlcmd-only

# 或僅安裝 jq
./install-tools.sh --jq-only
```

**腳本功能：**
- ✅ 自動偵測 Linux 發行版（Ubuntu/Debian/RHEL/CentOS/Fedora）
- ✅ 自動註冊 Microsoft 套件儲存庫
- ✅ 自動安裝 sqlcmd 和 jq
- ✅ 自動設定 PATH 環境變數
- ✅ 安裝後自動驗證

**支援的系統：**
- Ubuntu / Debian
- RHEL / CentOS / Rocky Linux / AlmaLinux
- Fedora

如需手動安裝，請參考 [SQL-SERVER-README.md](./SQL-SERVER-README.md#安裝-sqlcmd) 的詳細說明。

## 快速開始

### 1. 設定環境變數

```bash
# 複製環境變數範本
cp sql-permission.env.example .env

# 編輯 .env 檔案
nano .env
```

填入實際的連線資訊：
```bash
SQL_SERVER=your-server-address
SQL_PORT=1433
ADMIN_USER=your-admin-username
ADMIN_PASSWORD=your-admin-password
```

設定檔案權限：
```bash
chmod 600 .env
```

### 2. 測試連線

```bash
./sql-permission.sh test-connection
```

### 3. 基本使用

```bash
# 查詢使用者權限
./sql-permission.sh get-user john --format table

# 授予 Server 角色
./sql-permission.sh grant john --server-role sysadmin

# 授予 Database 角色
./sql-permission.sh grant john --database MyDB --db-role db_datareader,db_datawriter

# 列出所有使用者權限
./sql-permission.sh get-all --format csv > all-permissions.csv
```

## 詳細使用說明

### 命令清單

| 命令 | 說明 |
|------|------|
| `get-user <username>` | 查詢特定使用者的權限 |
| `get-all` | 查詢所有使用者的權限 |
| `grant <username>` | 授予權限 |
| `revoke <username>` | 撤銷權限 |
| `grant-batch` | 批次授予權限 |
| `revoke-batch` | 批次撤銷權限 |
| `compare <user1> <user2>` | 比較權限差異 |
| `list-server-roles` | 列出 Server 層級角色 |
| `list-db-roles` | 列出 Database 層級角色 |
| `test-connection` | 測試 SQL Server 連線 |
| `help` | 顯示說明 |

### 1. 查詢權限

#### 查詢特定使用者

```bash
# 表格格式（預設）
./sql-permission.sh get-user john

# JSON 格式
./sql-permission.sh get-user john --format json

# CSV 格式
./sql-permission.sh get-user john --format csv

# 僅查詢特定資料庫
./sql-permission.sh get-user john --database MyDB

# 輸出到檔案
./sql-permission.sh get-user john --format json --output john-permissions.json
```

#### 查詢所有使用者

```bash
# 表格格式
./sql-permission.sh get-all

# CSV 格式（適合匯入 Excel）
./sql-permission.sh get-all --format csv --output all-users.csv
```

### 2. 授予權限

#### Server 層級權限

```bash
# 授予單一角色
./sql-permission.sh grant john --server-role sysadmin

# 授予多個角色
./sql-permission.sh grant john --server-role securityadmin,dbcreator
```

**可用的 Server 角色：**
- `sysadmin` - 系統管理員（完整權限）
- `serveradmin` - 伺服器管理員
- `securityadmin` - 安全性管理員
- `processadmin` - 處理程序管理員
- `setupadmin` - 設定管理員
- `bulkadmin` - 大量作業管理員
- `diskadmin` - 磁碟管理員
- `dbcreator` - 資料庫建立者

#### Database 層級權限

```bash
# 授予單一角色
./sql-permission.sh grant john --database MyDB --db-role db_datareader

# 授予多個角色
./sql-permission.sh grant john --database MyDB --db-role db_datareader,db_datawriter
```

**可用的 Database 角色：**
- `db_owner` - 資料庫擁有者（完整權限）
- `db_datareader` - 資料讀取者
- `db_datawriter` - 資料寫入者
- `db_ddladmin` - DDL 管理員
- `db_securityadmin` - 安全性管理員
- `db_accessadmin` - 存取管理員
- `db_backupoperator` - 備份操作員
- `db_denydatawriter` - 拒絕資料寫入
- `db_denydatareader` - 拒絕資料讀取

#### Object 層級權限

```bash
# 授予單一權限
./sql-permission.sh grant john --database MyDB --object dbo.Users --permission SELECT

# 授予多個權限
./sql-permission.sh grant john --database MyDB --object dbo.Orders --permission SELECT,INSERT,UPDATE
```

**常用的物件權限：**
- `SELECT` - 查詢資料
- `INSERT` - 新增資料
- `UPDATE` - 更新資料
- `DELETE` - 刪除資料
- `EXECUTE` - 執行預存程序
- `ALTER` - 修改物件結構
- `CONTROL` - 完整控制權

### 3. 撤銷權限

撤銷權限的語法與授予權限相同，只需將 `grant` 改為 `revoke`：

```bash
# 撤銷 Server 角色
./sql-permission.sh revoke john --server-role sysadmin

# 撤銷 Database 角色
./sql-permission.sh revoke john --database MyDB --db-role db_owner

# 撤銷物件權限
./sql-permission.sh revoke john --database MyDB --object dbo.Users --permission DELETE
```

### 4. 批次處理

#### 從 CSV 檔案批次處理

1. 準備 CSV 檔案（參考 `templates/permissions-template.csv`）：

```csv
username,action,level,target,role_or_permission,database
user1,grant,server,,sysadmin,
user2,grant,database,MyDB,db_datareader,MyDB
user3,grant,object,dbo.Users,SELECT,MyDB
```

2. 執行批次處理：

```bash
./sql-permission.sh grant-batch --file permissions.csv
```

#### 從 JSON 檔案批次處理

1. 準備 JSON 檔案（參考 `templates/permissions-template.json`）：

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

2. 執行批次處理：

```bash
./sql-permission.sh grant-batch --file permissions.json
```

#### 從命令列參數批次處理

```bash
# 批次授予多個使用者相同的權限
./sql-permission.sh grant-batch \
  --users "user1,user2,user3" \
  --level database \
  --database MyDB \
  --role db_datareader
```

### 5. 權限比對

```bash
# 比較兩個使用者的權限差異
./sql-permission.sh compare john jane

# 輸出差異報告到檔案
./sql-permission.sh compare john jane --output diff-report.txt
```

### 6. 列出角色

```bash
# 列出 Server 層級角色
./sql-permission.sh list-server-roles

# 列出 Database 層級角色
./sql-permission.sh list-db-roles

# 列出特定資料庫的自訂角色
./sql-permission.sh list-db-roles --database MyDB
```

## 進階功能

### Dry-run 模式

預覽變更但不實際執行：

```bash
# 在 .env 中設定
DRY_RUN=true

# 或使用 --dry-run 選項
./sql-permission.sh grant john --server-role sysadmin --dry-run
```

### 詳細輸出模式

顯示詳細的除錯資訊：

```bash
# 在 .env 中設定
VERBOSE=true

# 查看詳細的 SQL 執行過程
./sql-permission.sh get-user john
```

### 稽核日誌

所有權限變更操作都會記錄在稽核日誌中（如果啟用）：

```bash
# 在 .env 中啟用
ENABLE_AUDIT_LOG=true
AUDIT_LOG_FILE=./audit.log

# 查看稽核日誌
cat audit.log
```

日誌格式：
```
2025-01-15 10:30:45 [INFO] User: yao | Action: grant_server_role | Target: user1 | Details: role=sysadmin
```

## 常見使用場景

### 場景 1：新增應用程式使用者

```bash
# 1. 授予 Database 讀寫權限
./sql-permission.sh grant app_user --database MyAppDB --db-role db_datareader,db_datawriter

# 2. 授予執行預存程序的權限
./sql-permission.sh grant app_user --database MyAppDB --object dbo.sp_GetUserData --permission EXECUTE

# 3. 驗證權限
./sql-permission.sh get-user app_user --database MyAppDB
```

### 場景 2：建立唯讀報表使用者

```bash
# 授予唯讀權限
./sql-permission.sh grant report_user --database MyAppDB --db-role db_datareader

# 驗證
./sql-permission.sh get-user report_user --format table
```

### 場景 3：批次設定多個使用者

準備 CSV 檔案 `new-users.csv`：
```csv
username,action,level,target,role_or_permission,database
dev_user1,grant,database,DevDB,db_owner,DevDB
dev_user2,grant,database,DevDB,db_owner,DevDB
test_user1,grant,database,TestDB,db_datareader,TestDB
test_user2,grant,database,TestDB,db_datareader,TestDB
```

執行批次處理：
```bash
./sql-permission.sh grant-batch --file new-users.csv
```

### 場景 4：權限審計

```bash
# 1. 匯出所有使用者權限
./sql-permission.sh get-all --format csv --output audit-$(date +%Y%m%d).csv

# 2. 比較兩個使用者的權限
./sql-permission.sh compare prod_user test_user

# 3. 查看稽核日誌
tail -f audit.log
```

## 安全注意事項

### 1. 環境變數管理

- ✅ `.env` 檔案包含機敏資料，已加入 `.gitignore`
- ✅ 設定檔案權限：`chmod 600 .env`
- ❌ 不要將 `.env` 檔案納入版控
- ❌ 不要在命令列直接輸入密碼（會留在 shell history）

### 2. 最小權限原則

- 僅授予應用程式或使用者所需的最小權限
- 避免濫用 `sysadmin` 或 `db_owner` 角色
- 定期檢視與調整權限

### 3. 稽核日誌

- 啟用稽核日誌記錄所有變更
- 定期檢視稽核日誌
- 保護日誌檔案不被未授權存取

### 4. 密碼管理

- 使用強密碼（至少 8 個字元，包含大小寫、數字、符號）
- 定期更換密碼
- 不要重複使用密碼

## 疑難排解

### 錯誤：sqlcmd: command not found

請安裝 mssql-tools（參考「安裝依賴工具」章節）。

### 錯誤：jq: command not found

```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq
```

JSON 格式的批次處理需要 jq 工具。

### 錯誤：找不到 .env 檔案

```bash
cp sql-permission.env.example .env
nano .env  # 填入實際的連線資訊
```

### 錯誤：認證失敗

1. 檢查 `.env` 檔案中的連線資訊是否正確
2. 確認 SQL Server 允許 SQL 認證模式
3. 測試連線：`./sql-permission.sh test-connection`

### 錯誤：權限不足

確認使用的管理員帳號具有足夠的權限來管理其他使用者的權限。通常需要 `securityadmin` 或 `sysadmin` 角色。

## 檔案結構

```
vault-manage-script/
├── .env                              # 實際的機敏資料（不納入版控）
├── .env.example                      # 環境變數範本
├── sql-permission.env.example        # SQL 權限工具環境變數範本
├── sql-permission.sh                 # 主程式
├── lib/                              # 函式庫目錄
│   ├── auth.sh                       # 認證模組
│   ├── query.sh                      # 查詢與權限設定模組
│   ├── parser.sh                     # 批次處理解析模組
│   ├── formatter.sh                  # 輸出格式化模組
│   └── utils.sh                      # 工具函式模組
├── templates/                        # 範本目錄
│   ├── permissions-template.csv      # CSV 範本
│   └── permissions-template.json     # JSON 範本
├── SQL-PERMISSION-README.md          # 本使用說明
└── sql-permission-manage-plan.md     # 實作計畫文件
```

## 授權

本專案僅供內部開發使用。

## 聯絡資訊

如有問題或建議，請聯絡開發團隊。

---

**版本**: 1.0.0
**最後更新**: 2025-01-15
