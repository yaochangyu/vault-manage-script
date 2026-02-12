#!/bin/bash

#=============================================================================
# SQL Server 資料庫建立腳本
#=============================================================================
# 功能：
#   - 建立新資料庫
#
# 使用方式：
#   ./create-database.sh [options]
#
# 範例：
#   ./create-database.sh --db MyApp
#   ./create-database.sh --interactive
#   ./create-database.sh --db MyApp --size 500 --growth 100
#=============================================================================

set -e  # 遇到錯誤立即退出
set -o pipefail

# 取得腳本所在目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#=============================================================================
# 函數：顯示訊息
#=============================================================================
show_error() {
    echo -e "${RED}✗ 錯誤: $1${NC}" >&2
}

show_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

show_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

show_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

#=============================================================================
# 函數：載入環境變數
#=============================================================================
load_env() {
    local env_file="${1:-.env}"

    if [ ! -f "$env_file" ]; then
        show_error "找不到環境變數檔案: $env_file"
        echo ""
        echo "請先建立環境變數檔案："
        echo "  cp .env.example .env"
        echo "  nano .env"
        exit 1
    fi

    # 載入環境變數
    set -a
    source "$env_file"
    set +a

    # 驗證必要變數
    if [ -z "$SQL_SERVER" ] || [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASSWORD" ]; then
        show_error "環境變數不完整"
        echo ""
        echo "請確認 $env_file 包含以下變數："
        echo "  SQL_SERVER"
        echo "  ADMIN_USER"
        echo "  ADMIN_PASSWORD"
        exit 1
    fi

    # 設定預設 PORT
    SQL_PORT="${SQL_PORT:-1433}"
}

#=============================================================================
# 函數：產生 SQL 腳本
#=============================================================================
generate_sql_script() {
    local db_name="$1"
    local data_size="${2:-100}"      # MB
    local data_growth="${3:-50}"     # MB
    local log_size="${4:-50}"        # MB
    local log_growth="${5:-25}"      # MB

    cat > "${SCRIPT_DIR}/.create-database-temp.sql" << EOF
-- ============================================================================
-- SQL Server 資料庫建立腳本（自動產生）
-- ============================================================================
-- 資料庫: ${db_name}
-- 產生時間: $(date '+%Y-%m-%d %H:%M:%S')
-- 資料檔初始大小: ${data_size} MB
-- 資料檔成長率: ${data_growth} MB
-- 日誌檔初始大小: ${log_size} MB
-- 日誌檔成長率: ${log_growth} MB
-- ============================================================================

-- 檢查並建立資料庫
IF EXISTS (SELECT name FROM sys.databases WHERE name = '${db_name}')
BEGIN
    PRINT '⚠ 資料庫已存在: ${db_name}';
    PRINT '跳過建立資料庫，繼續建立資料表...';
    PRINT '';
END
ELSE
BEGIN
    PRINT '開始建立資料庫: ${db_name}';
    PRINT '';

    -- 建立資料庫
    CREATE DATABASE [${db_name}]
    ON PRIMARY
    (
        NAME = '${db_name}_Data',
        FILENAME = '/var/opt/mssql/data/${db_name}.mdf',
        SIZE = ${data_size}MB,
        FILEGROWTH = ${data_growth}MB
    )
    LOG ON
    (
        NAME = '${db_name}_Log',
        FILENAME = '/var/opt/mssql/data/${db_name}_log.ldf',
        SIZE = ${log_size}MB,
        FILEGROWTH = ${log_growth}MB
    );

    PRINT '✓ 資料庫建立成功: ${db_name}';
    PRINT '';
END
GO

PRINT '============================================================';
PRINT '資料庫資訊：';
PRINT '============================================================';
GO

-- 顯示資料庫資訊
SELECT
    name AS DatabaseName,
    database_id AS DatabaseID,
    create_date AS CreateDate,
    compatibility_level AS CompatibilityLevel,
    collation_name AS Collation,
    state_desc AS State,
    recovery_model_desc AS RecoveryModel
FROM sys.databases
WHERE name = '${db_name}';

-- 顯示檔案資訊
USE [${db_name}];
GO

SELECT
    name AS FileName,
    type_desc AS FileType,
    CAST(size * 8.0 / 1024 AS DECIMAL(10,2)) AS SizeMB,
    CASE
        WHEN is_percent_growth = 1 THEN CAST(growth AS VARCHAR(20)) + '%'
        ELSE CAST(CAST(growth * 8.0 / 1024 AS DECIMAL(10,2)) AS VARCHAR(20)) + ' MB'
    END AS Growth
FROM sys.database_files;

PRINT '';
PRINT '✓ 資料庫建立完成！';
PRINT '============================================================';
GO

-- ============================================================================
-- 4. 建立會員資料表
-- ============================================================================
USE [${db_name}];
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Members]') AND type = 'U')
BEGIN
    PRINT '';
    PRINT '建立會員資料表...';

    CREATE TABLE [dbo].[Members]
    (
        MemberID INT IDENTITY(1,1) PRIMARY KEY,
        Username NVARCHAR(50) NOT NULL UNIQUE,
        Email NVARCHAR(100) NOT NULL,
        FullName NVARCHAR(100) NOT NULL,
        PhoneNumber NVARCHAR(20),
        CreateDate DATETIME NOT NULL DEFAULT GETDATE(),
        Status NVARCHAR(20) NOT NULL DEFAULT 'Active',
        CONSTRAINT CK_Members_Status CHECK (Status IN ('Active', 'Inactive', 'Suspended'))
    );

    PRINT '✓ 會員資料表建立成功';
END
ELSE
BEGIN
    PRINT '⚠ 會員資料表已存在';
END
GO

-- ============================================================================
-- 5. 插入測試會員資料（5 筆）
-- ============================================================================
IF NOT EXISTS (SELECT * FROM [dbo].[Members])
BEGIN
    PRINT '';
    PRINT '插入測試會員資料...';

    INSERT INTO [dbo].[Members] (Username, Email, FullName, PhoneNumber, Status)
    VALUES
        ('john_doe', 'john.doe@example.com', 'John Doe', '0912-345-678', 'Active'),
        ('jane_smith', 'jane.smith@example.com', 'Jane Smith', '0923-456-789', 'Active'),
        ('bob_wilson', 'bob.wilson@example.com', 'Bob Wilson', '0934-567-890', 'Active'),
        ('alice_brown', 'alice.brown@example.com', 'Alice Brown', '0945-678-901', 'Inactive'),
        ('charlie_davis', 'charlie.davis@example.com', 'Charlie Davis', '0956-789-012', 'Active');

    PRINT '✓ 已插入 5 筆測試會員資料';
END
ELSE
BEGIN
    PRINT '⚠ 會員資料表已有資料，跳過插入';
END
GO

-- ============================================================================
-- 6. 顯示會員資料
-- ============================================================================
PRINT '';
PRINT '============================================================';
PRINT '會員資料列表：';
PRINT '============================================================';

SELECT
    MemberID,
    Username,
    Email,
    FullName,
    PhoneNumber,
    CreateDate,
    Status
FROM [dbo].[Members]
ORDER BY MemberID;

PRINT '';
PRINT '✓ 資料庫、資料表與測試資料建立完成！';
PRINT '============================================================';
GO
EOF
}

#=============================================================================
# 函數：執行 SQL 腳本
#=============================================================================
execute_sql_script() {
    local sql_file="$1"

    show_info "執行 SQL 腳本..."
    echo ""

    # 先將 mssql-tools 加入 PATH
    export PATH="$PATH:/opt/mssql-tools18/bin:/opt/mssql-tools/bin"

    # 檢查 sqlcmd 是否存在
    if ! command -v sqlcmd &> /dev/null; then
        show_error "找不到 sqlcmd 工具"
        echo ""
        echo "請執行以下命令安裝："
        echo "  ./install-tools.sh"
        exit 1
    fi

    # 執行 SQL 腳本
    if sqlcmd -S "${SQL_SERVER},${SQL_PORT}" \
               -U "${ADMIN_USER}" \
               -P "${ADMIN_PASSWORD}" \
               -C \
               -i "$sql_file"; then
        echo ""
        show_success "資料庫建立完成！"
        return 0
    else
        echo ""
        show_error "執行失敗"
        return 1
    fi
}

#=============================================================================
# 函數：互動式模式
#=============================================================================
interactive_mode() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  SQL Server 資料庫建立精靈${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # 1. 資料庫名稱
    read -p "資料庫名稱: " db_name
    if [ -z "$db_name" ]; then
        show_error "資料庫名稱不可為空"
        exit 1
    fi

    # 2. 資料檔初始大小
    read -p "資料檔初始大小 (MB) [100]: " data_size
    data_size="${data_size:-100}"

    # 3. 資料檔成長率
    read -p "資料檔成長率 (MB) [50]: " data_growth
    data_growth="${data_growth:-50}"

    # 4. 日誌檔初始大小
    read -p "日誌檔初始大小 (MB) [50]: " log_size
    log_size="${log_size:-50}"

    # 5. 日誌檔成長率
    read -p "日誌檔成長率 (MB) [25]: " log_growth
    log_growth="${log_growth:-25}"

    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  設定摘要${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo "資料庫名稱: $db_name"
    echo "資料檔: ${data_size} MB (成長 ${data_growth} MB)"
    echo "日誌檔: ${log_size} MB (成長 ${log_growth} MB)"
    echo ""

    read -p "確認執行？(y/n) [y]: " confirm
    confirm="${confirm:-y}"

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        show_warning "已取消"
        exit 0
    fi

    # 產生並執行
    generate_sql_script "$db_name" "$data_size" "$data_growth" "$log_size" "$log_growth"
    execute_sql_script "${SCRIPT_DIR}/.create-database-temp.sql"

    # 清理暫存檔
    rm -f "${SCRIPT_DIR}/.create-database-temp.sql"
}

#=============================================================================
# 函數：顯示說明
#=============================================================================
show_help() {
    cat << EOF
${GREEN}SQL Server 資料庫建立工具${NC}

使用方式:
  $0 [options]

選項:
  ${CYAN}互動模式${NC}
    --interactive, -i           互動式輸入參數

  ${CYAN}命令列模式${NC}
    --db <name>                 資料庫名稱（必要）
    --data-size <MB>            資料檔初始大小（預設: 100 MB）
    --data-growth <MB>          資料檔成長率（預設: 50 MB）
    --log-size <MB>             日誌檔初始大小（預設: 50 MB）
    --log-growth <MB>           日誌檔成長率（預設: 25 MB）

  ${CYAN}通用選項${NC}
    --env-file <file>           環境變數檔案（預設: .env）
    --keep-sql                  保留產生的 SQL 腳本
    --help, -h                  顯示此說明

範例:
  # 互動式模式（會詢問所有參數）
  $0 --interactive

  # 使用預設值建立資料庫
  $0 --db MyAppDB

  # 自訂檔案大小
  $0 --db MyAppDB --data-size 500 --data-growth 100

  # 完整參數範例
  $0 --db MyAppDB \\
    --data-size 500 --data-growth 100 \\
    --log-size 100 --log-growth 50

  # 保留產生的 SQL 腳本
  $0 --db MyAppDB --keep-sql

  # 使用自訂環境變數檔
  $0 --interactive --env-file .env.production

說明:
  - 資料庫檔案預設路徑: /var/opt/mssql/data/
  - 如果資料庫已存在，執行會失敗並提示手動刪除
  - 建立完成後會顯示資料庫和檔案資訊

後續步驟:
  建立資料庫後，您可以使用 sql-permission.sh 管理使用者權限：

  # 建立使用者並授予權限
  ./sql-permission.sh grant <username> \\
    --database MyAppDB \\
    --db-role db_datareader,db_datawriter

EOF
}

#=============================================================================
# 主程式
#=============================================================================
main() {
    local mode="interactive"
    local env_file=".env"
    local db_name=""
    local data_size="100"
    local data_growth="50"
    local log_size="50"
    local log_growth="25"
    local keep_sql=false

    # 解析參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            --interactive|-i)
                mode="interactive"
                shift
                ;;
            --db)
                db_name="$2"
                mode="cli"
                shift 2
                ;;
            --data-size)
                data_size="$2"
                shift 2
                ;;
            --data-growth)
                data_growth="$2"
                shift 2
                ;;
            --log-size)
                log_size="$2"
                shift 2
                ;;
            --log-growth)
                log_growth="$2"
                shift 2
                ;;
            --env-file)
                env_file="$2"
                shift 2
                ;;
            --keep-sql)
                keep_sql=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                show_error "未知的選項: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    # 載入環境變數
    load_env "$env_file"

    # 執行對應模式
    if [ "$mode" = "interactive" ]; then
        interactive_mode
    else
        # 驗證必要參數
        if [ -z "$db_name" ]; then
            show_error "命令列模式需要提供 --db 參數"
            echo ""
            show_help
            exit 1
        fi

        # 產生並執行
        generate_sql_script "$db_name" "$data_size" "$data_growth" "$log_size" "$log_growth"

        if [ "$keep_sql" = true ]; then
            local output_file="${SCRIPT_DIR}/create-${db_name}.sql"
            cp "${SCRIPT_DIR}/.create-database-temp.sql" "$output_file"
            show_info "SQL 腳本已保存: $output_file"
        fi

        execute_sql_script "${SCRIPT_DIR}/.create-database-temp.sql"

        # 清理暫存檔
        if [ "$keep_sql" = false ]; then
            rm -f "${SCRIPT_DIR}/.create-database-temp.sql"
        fi
    fi
}

# 執行主程式
main "$@"
