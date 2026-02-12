#!/bin/bash

#=============================================================================
# 認證模組 (auth.sh)
#=============================================================================
# 功能：
#   - 載入環境變數
#   - 測試 SQL Server 連線
#   - 提供 SQL 執行包裝函式
#=============================================================================

#=============================================================================
# 函式：載入環境變數
# 參數：$1 = 環境變數檔案路徑（預設：.env）
#=============================================================================
load_env() {
    local env_file="${1:-.env}"

    if [ ! -f "$env_file" ]; then
        show_error "找不到環境變數檔案: $env_file"
        echo ""
        echo "請先建立 .env 檔案："
        echo "  1. 複製範本：cp sql-permission.env.example .env"
        echo "  2. 編輯設定：nano .env"
        echo "  3. 填入實際的 SQL Server 連線資訊"
        exit 1
    fi

    # 載入環境變數
    set -a
    source "$env_file"
    set +a

    # 驗證必要變數
    local required_vars=("SQL_SERVER" "ADMIN_USER" "ADMIN_PASSWORD")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        show_error "以下環境變數未設定："
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "請檢查 $env_file 檔案"
        exit 1
    fi

    # 設定預設值
    SQL_PORT="${SQL_PORT:-1433}"
    DEFAULT_OUTPUT_FORMAT="${DEFAULT_OUTPUT_FORMAT:-table}"
    ENABLE_AUDIT_LOG="${ENABLE_AUDIT_LOG:-false}"
    AUDIT_LOG_FILE="${AUDIT_LOG_FILE:-./audit.log}"
    QUERY_TIMEOUT="${QUERY_TIMEOUT:-30}"
    VERBOSE="${VERBOSE:-false}"
    DRY_RUN="${DRY_RUN:-false}"

    if [ "$VERBOSE" = "true" ]; then
        echo -e "${CYAN}[DEBUG] 環境變數載入成功${NC}"
        echo -e "${CYAN}[DEBUG] 伺服器: $SQL_SERVER:$SQL_PORT${NC}"
        echo -e "${CYAN}[DEBUG] 使用者: $ADMIN_USER${NC}"
    fi
}

#=============================================================================
# 函式：測試 SQL Server 連線
# 返回：0 = 成功，1 = 失敗
#=============================================================================
test_connection() {
    local test_query="SELECT @@VERSION AS version, GETDATE() AS current_time"

    if [ "$VERBOSE" = "true" ]; then
        echo -e "${CYAN}[DEBUG] 測試連線: $SQL_SERVER:$SQL_PORT${NC}"
    fi

    # 執行測試查詢
    local result
    result=$(sqlcmd -S "$SQL_SERVER,$SQL_PORT" \
                    -U "$ADMIN_USER" \
                    -P "$ADMIN_PASSWORD" \
                    -Q "$test_query" \
                    -h -1 \
                    -W \
                    -s "," \
                    2>&1)

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${CYAN}[DEBUG] 連線成功${NC}"
            echo "$result"
        fi
        return 0
    else
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${RED}[DEBUG] 連線失敗${NC}"
            echo "$result"
        fi
        return 1
    fi
}

#=============================================================================
# 函式：執行 SQL 指令
# 參數：
#   $1 = 資料庫名稱（可選，預設：master）
#   $2 = SQL 指令
#   $3 = 輸出格式（可選：csv, json, table）
# 返回：SQL 執行結果
#=============================================================================
execute_sql() {
    local database="${1:-master}"
    local sql_command="$2"
    local output_format="${3:-table}"

    if [ -z "$sql_command" ]; then
        show_error "execute_sql: SQL 指令不可為空"
        return 1
    fi

    # Dry-run 模式
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] 將執行以下 SQL：${NC}"
        echo "資料庫: $database"
        echo "SQL: $sql_command"
        return 0
    fi

    if [ "$VERBOSE" = "true" ]; then
        echo -e "${CYAN}[DEBUG] 執行 SQL${NC}"
        echo -e "${CYAN}[DEBUG] 資料庫: $database${NC}"
        echo -e "${CYAN}[DEBUG] SQL: $sql_command${NC}"
    fi

    # 根據輸出格式設定 sqlcmd 參數
    local sqlcmd_opts=()
    case "$output_format" in
        csv)
            sqlcmd_opts=(-h -1 -W -s "," -w 8000)
            ;;
        json)
            # JSON 輸出需要 SQL Server 2016+ 的 FOR JSON 語法
            sqlcmd_opts=(-h -1 -w 8000)
            ;;
        table|*)
            sqlcmd_opts=(-W)
            ;;
    esac

    # 執行 SQL
    local result
    result=$(sqlcmd -S "$SQL_SERVER,$SQL_PORT" \
                    -U "$ADMIN_USER" \
                    -P "$ADMIN_PASSWORD" \
                    -d "$database" \
                    -Q "$sql_command" \
                    "${sqlcmd_opts[@]}" \
                    -t "$QUERY_TIMEOUT" \
                    2>&1)

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$result"
        return 0
    else
        show_error "SQL 執行失敗"
        if [ "$VERBOSE" = "true" ]; then
            echo "$result"
        fi
        return 1
    fi
}

#=============================================================================
# 函式：執行 SQL 指令（不輸出結果，僅返回成功/失敗）
# 參數：
#   $1 = 資料庫名稱
#   $2 = SQL 指令
# 返回：0 = 成功，1 = 失敗
#=============================================================================
execute_sql_quiet() {
    local database="${1:-master}"
    local sql_command="$2"

    if [ -z "$sql_command" ]; then
        show_error "execute_sql_quiet: SQL 指令不可為空"
        return 1
    fi

    # Dry-run 模式
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] 將執行以下 SQL：${NC}"
        echo "資料庫: $database"
        echo "SQL: $sql_command"
        return 0
    fi

    if [ "$VERBOSE" = "true" ]; then
        echo -e "${CYAN}[DEBUG] 執行 SQL (quiet)${NC}"
        echo -e "${CYAN}[DEBUG] 資料庫: $database${NC}"
        echo -e "${CYAN}[DEBUG] SQL: $sql_command${NC}"
    fi

    # 執行 SQL
    sqlcmd -S "$SQL_SERVER,$SQL_PORT" \
           -U "$ADMIN_USER" \
           -P "$ADMIN_PASSWORD" \
           -d "$database" \
           -Q "$sql_command" \
           -t "$QUERY_TIMEOUT" \
           > /dev/null 2>&1

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${CYAN}[DEBUG] SQL 執行成功${NC}"
        fi
        return 0
    else
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${RED}[DEBUG] SQL 執行失敗${NC}"
        fi
        return 1
    fi
}

#=============================================================================
# 函式：執行 SQL 指令並返回單一值
# 參數：
#   $1 = 資料庫名稱
#   $2 = SQL 指令
# 返回：查詢結果的第一個值
#=============================================================================
execute_sql_scalar() {
    local database="${1:-master}"
    local sql_command="$2"

    if [ -z "$sql_command" ]; then
        show_error "execute_sql_scalar: SQL 指令不可為空"
        return 1
    fi

    if [ "$VERBOSE" = "true" ]; then
        echo -e "${CYAN}[DEBUG] 執行 SQL (scalar)${NC}"
        echo -e "${CYAN}[DEBUG] SQL: $sql_command${NC}"
    fi

    # 執行 SQL 並取得第一個值
    local result
    result=$(sqlcmd -S "$SQL_SERVER,$SQL_PORT" \
                    -U "$ADMIN_USER" \
                    -P "$ADMIN_PASSWORD" \
                    -d "$database" \
                    -Q "$sql_command" \
                    -h -1 \
                    -W \
                    -t "$QUERY_TIMEOUT" \
                    2>/dev/null | head -n 1 | xargs)

    echo "$result"
}
