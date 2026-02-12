#!/bin/bash

#=============================================================================
# SQL Server 權限管理工具
#=============================================================================
# 功能：
#   - 查詢使用者權限（Server / Database / 物件層級）
#   - 設定使用者權限（授予 / 撤銷）
#   - 批次處理多帳號權限
#   - 權限比對與差異分析
#
# 使用方式：
#   ./sql-permission.sh <command> [options]
#
# 範例：
#   ./sql-permission.sh get-user john --format table
#   ./sql-permission.sh grant user1 --server-role sysadmin
#   ./sql-permission.sh grant-batch --file permissions.csv
#   ./sql-permission.sh compare user1 user2
#=============================================================================

set -e  # 遇到錯誤立即退出
set -o pipefail  # 管道命令中任一失敗則視為失敗

# 取得腳本所在目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 顏色定義（先定義，供依賴檢查使用）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#=============================================================================
# 函數：檢查並安裝依賴工具
#=============================================================================
check_and_install_dependencies() {
    # 先將 mssql-tools 加入 PATH（如果還沒加入的話）
    export PATH="$PATH:/opt/mssql-tools18/bin:/opt/mssql-tools/bin"

    local missing_tools=()

    # 檢查 sqlcmd（使用 command -v 判斷）
    if ! command -v sqlcmd &> /dev/null; then
        missing_tools+=("sqlcmd")
    fi

    # 檢查 jq（選用）
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq (選用，用於 JSON 格式)")
    fi

    # 如果有缺少的工具
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}偵測到缺少以下依賴工具：${NC}"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""

        # 檢查是否有安裝腳本
        if [ -f "${SCRIPT_DIR}/install-tools.sh" ]; then
            echo -e "${BLUE}是否要自動安裝依賴工具？${NC}"
            read -p "請選擇 (y/n) [預設: y]: " install_confirm

            # 如果為空（直接按 Enter），預設為 y
            install_confirm="${install_confirm:-y}"

            if [[ "$install_confirm" =~ ^[Yy]$ ]]; then
                echo ""
                echo -e "${GREEN}執行自動安裝...${NC}"
                "${SCRIPT_DIR}/install-tools.sh"

                # 立即更新當前 shell 的 PATH（安裝完成後）
                export PATH="$PATH:/opt/mssql-tools/bin:/opt/mssql-tools18/bin"

                # 重新檢查
                if command -v sqlcmd &> /dev/null; then
                    echo ""
                    echo -e "${GREEN}依賴工具安裝完成！${NC}"
                    echo ""
                    return 0
                else
                    echo ""
                    echo -e "${RED}安裝失敗，請手動安裝依賴工具${NC}"
                    echo -e "${YELLOW}提示：請執行以下命令後重試${NC}"
                    echo "  export PATH=\"\$PATH:/opt/mssql-tools/bin:/opt/mssql-tools18/bin\""
                    echo "  或重新載入 shell: source ~/.bashrc"
                    exit 1
                fi
            else
                echo ""
                echo -e "${YELLOW}已取消安裝${NC}"
                echo ""
                echo "請手動安裝依賴工具："
                echo "  ${SCRIPT_DIR}/install-tools.sh"
                echo ""
                exit 1
            fi
        else
            echo -e "${RED}找不到安裝腳本: install-tools.sh${NC}"
            echo ""
            echo "請手動安裝 sqlcmd 和 jq："
            echo "  https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools"
            echo ""
            exit 1
        fi
    fi
}

# 檢查依賴工具
check_and_install_dependencies

# 載入函式庫
source "${SCRIPT_DIR}/lib/auth.sh"
source "${SCRIPT_DIR}/lib/query.sh"
source "${SCRIPT_DIR}/lib/parser.sh"
source "${SCRIPT_DIR}/lib/formatter.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

# 版本資訊
VERSION="1.0.0"

#=============================================================================
# 命令處理函式
#=============================================================================

# 查詢特定使用者權限
cmd_get_user() {
    local username="$1"
    shift

    if [ -z "$username" ]; then
        show_error "請指定使用者名稱"
        echo "使用方式: $0 get-user <username> [--format json|table|csv] [--database <dbname>]"
        exit 1
    fi

    # 解析選項
    local format="${DEFAULT_OUTPUT_FORMAT:-table}"
    local database=""
    local output_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --format)
                format="$2"
                shift 2
                ;;
            --database)
                database="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            *)
                show_error "未知的選項: $1"
                exit 1
                ;;
        esac
    done

    # 根據格式輸出
    case "$format" in
        json)
            if [ -n "$output_file" ]; then
                format_user_permissions_json "$username" "$database" > "$output_file"
                show_success "已輸出到檔案: $output_file"
            else
                format_user_permissions_json "$username" "$database"
            fi
            ;;
        table)
            if [ -n "$output_file" ]; then
                format_user_permissions_table "$username" "$database" > "$output_file"
                show_success "已輸出到檔案: $output_file"
            else
                format_user_permissions_table "$username" "$database"
            fi
            ;;
        csv)
            if [ -n "$output_file" ]; then
                format_user_permissions_csv "$username" "$database" > "$output_file"
                show_success "已輸出到檔案: $output_file"
            else
                format_user_permissions_csv "$username" "$database"
            fi
            ;;
        *)
            show_error "不支援的輸出格式: $format"
            exit 1
            ;;
    esac
}

# 查詢所有使用者權限
cmd_get_all() {
    # 解析選項
    local format="${DEFAULT_OUTPUT_FORMAT:-table}"
    local database=""
    local output_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --format)
                format="$2"
                shift 2
                ;;
            --database)
                database="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            *)
                show_error "未知的選項: $1"
                exit 1
                ;;
        esac
    done

    # 根據格式輸出
    case "$format" in
        json|table)
            # JSON 和表格格式使用表格函式
            if [ -n "$output_file" ]; then
                format_all_users_table "$database" > "$output_file"
                show_success "已輸出到檔案: $output_file"
            else
                format_all_users_table "$database"
            fi
            ;;
        csv)
            if [ -n "$output_file" ]; then
                format_all_users_csv "$database" > "$output_file"
                show_success "已輸出到檔案: $output_file"
            else
                format_all_users_csv "$database"
            fi
            ;;
        *)
            show_error "不支援的輸出格式: $format"
            exit 1
            ;;
    esac
}

# 建立使用者
cmd_create_user() {
    # 解析選項
    local users=""
    local databases=""
    local password=""
    local grant_read=false
    local grant_write=false
    local grant_execute=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --users)
                users="$2"
                shift 2
                ;;
            --databases)
                databases="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --grant-read)
                grant_read=true
                shift
                ;;
            --grant-write)
                grant_write=true
                shift
                ;;
            --grant-execute)
                grant_execute=true
                shift
                ;;
            *)
                show_error "未知的選項: $1"
                exit 1
                ;;
        esac
    done

    # 驗證必要參數
    if [ -z "$users" ]; then
        show_error "請使用 --users 指定使用者名稱（可用逗號分隔多個使用者）"
        exit 1
    fi

    if [ -z "$databases" ]; then
        show_error "請使用 --databases 指定資料庫名稱（可用逗號分隔多個資料庫）"
        exit 1
    fi

    if [ -z "$password" ]; then
        show_error "請使用 --password 指定密碼"
        exit 1
    fi

    # 將逗號分隔的字串轉為陣列
    IFS=',' read -ra user_array <<< "$users"
    IFS=',' read -ra db_array <<< "$databases"

    # 顯示操作摘要
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  建立使用者與授予權限${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "使用者: ${user_array[*]}"
    echo "資料庫: ${db_array[*]}"
    echo "權限:"
    [ "$grant_read" = true ] && echo "  - 讀取 (db_datareader)"
    [ "$grant_write" = true ] && echo "  - 寫入 (db_datawriter)"
    [ "$grant_execute" = true ] && echo "  - 執行預存程序 (EXECUTE)"
    echo ""

    # 確認操作
    if ! confirm_action "確定要建立以上使用者並授予權限嗎？" "no"; then
        show_warning "已取消操作"
        exit 0
    fi

    echo ""
    show_info "開始建立使用者..."
    echo ""

    # 處理每個使用者
    for user in "${user_array[@]}"; do
        user=$(echo "$user" | xargs)  # 去除空白

        if [ -z "$user" ]; then
            continue
        fi

        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}處理使用者: $user${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        # 1. 建立 Login（Server 層級）
        if ! create_login "$user" "$password"; then
            show_error "建立 Login 失敗，跳過此使用者"
            continue
        fi

        # 2. 在每個資料庫建立 User 並授予權限
        for db in "${db_array[@]}"; do
            db=$(echo "$db" | xargs)  # 去除空白

            if [ -z "$db" ]; then
                continue
            fi

            echo ""
            echo -e "${CYAN}資料庫: $db${NC}"

            # 建立 User（Database 層級）
            if ! create_user "$user" "$db"; then
                show_warning "建立 User 失敗，跳過此資料庫"
                continue
            fi

            # 授予讀取權限
            if [ "$grant_read" = true ]; then
                grant_database_role "$user" "$db" "db_datareader"
            fi

            # 授予寫入權限
            if [ "$grant_write" = true ]; then
                grant_database_role "$user" "$db" "db_datawriter"
            fi

            # 授予執行權限
            if [ "$grant_execute" = true ]; then
                grant_execute_permission "$user" "$db"
            fi
        done

        echo ""
    done

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  使用者建立完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    # 顯示建立的使用者權限
    for user in "${user_array[@]}"; do
        user=$(echo "$user" | xargs)
        if [ -n "$user" ]; then
            echo -e "${BLUE}使用者 '$user' 的權限：${NC}"
            for db in "${db_array[@]}"; do
                db=$(echo "$db" | xargs)
                if [ -n "$db" ]; then
                    format_user_permissions_table "$user" "$db"
                    echo ""
                fi
            done
        fi
    done
}

# 授予權限
cmd_grant() {
    local username="$1"
    shift

    if [ -z "$username" ]; then
        show_error "請指定使用者名稱"
        exit 1
    fi

    # 解析選項
    local server_role=""
    local db_role=""
    local database=""
    local object=""
    local permission=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --server-role)
                server_role="$2"
                shift 2
                ;;
            --db-role)
                db_role="$2"
                database="${database:-$4}"  # 預期後面會有 --database
                shift 2
                ;;
            --database)
                database="$2"
                shift 2
                ;;
            --object)
                object="$2"
                shift 2
                ;;
            --permission)
                permission="$2"
                shift 2
                ;;
            *)
                show_error "未知的選項: $1"
                exit 1
                ;;
        esac
    done

    # 根據提供的選項執行對應的操作
    if [ -n "$server_role" ]; then
        # Server 層級
        IFS=',' read -ra roles <<< "$server_role"
        for role in "${roles[@]}"; do
            role=$(echo "$role" | xargs)  # 去除空白
            grant_server_role "$username" "$role"
        done
    fi

    if [ -n "$db_role" ] && [ -n "$database" ]; then
        # Database 層級
        IFS=',' read -ra roles <<< "$db_role"
        for role in "${roles[@]}"; do
            role=$(echo "$role" | xargs)
            grant_database_role "$username" "$database" "$role"
        done
    fi

    if [ -n "$object" ] && [ -n "$permission" ] && [ -n "$database" ]; then
        # Object 層級
        IFS=',' read -ra perms <<< "$permission"
        for perm in "${perms[@]}"; do
            perm=$(echo "$perm" | xargs)
            grant_object_permission "$username" "$database" "$object" "$perm"
        done
    fi
}

# 撤銷權限
cmd_revoke() {
    local username="$1"
    shift

    if [ -z "$username" ]; then
        show_error "請指定使用者名稱"
        exit 1
    fi

    # 解析選項
    local server_role=""
    local db_role=""
    local database=""
    local object=""
    local permission=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --server-role)
                server_role="$2"
                shift 2
                ;;
            --db-role)
                db_role="$2"
                shift 2
                ;;
            --database)
                database="$2"
                shift 2
                ;;
            --object)
                object="$2"
                shift 2
                ;;
            --permission)
                permission="$2"
                shift 2
                ;;
            *)
                show_error "未知的選項: $1"
                exit 1
                ;;
        esac
    done

    # 根據提供的選項執行對應的操作
    if [ -n "$server_role" ]; then
        # Server 層級
        IFS=',' read -ra roles <<< "$server_role"
        for role in "${roles[@]}"; do
            role=$(echo "$role" | xargs)
            revoke_server_role "$username" "$role"
        done
    fi

    if [ -n "$db_role" ] && [ -n "$database" ]; then
        # Database 層級
        IFS=',' read -ra roles <<< "$db_role"
        for role in "${roles[@]}"; do
            role=$(echo "$role" | xargs)
            revoke_database_role "$username" "$database" "$role"
        done
    fi

    if [ -n "$object" ] && [ -n "$permission" ] && [ -n "$database" ]; then
        # Object 層級
        IFS=',' read -ra perms <<< "$permission"
        for perm in "${perms[@]}"; do
            perm=$(echo "$perm" | xargs)
            revoke_object_permission "$username" "$database" "$object" "$perm"
        done
    fi
}

# 批次授予權限
cmd_grant_batch() {
    # 解析選項
    local file=""
    local has_inline_params=false

    # 檢查是否有 --file 參數
    if [[ "$1" == "--file" ]]; then
        file="$2"
        process_batch_from_file "$file"
    else
        # 使用命令列參數批次處理
        process_batch_from_args --action grant "$@"
    fi
}

# 批次撤銷權限
cmd_revoke_batch() {
    # 解析選項
    local file=""

    # 檢查是否有 --file 參數
    if [[ "$1" == "--file" ]]; then
        file="$2"
        # 修改 action 為 revoke 後處理
        # 這裡需要先解析檔案，然後修改 action
        show_warning "批次撤銷功能需要檔案中的 action 欄位設定為 'revoke'"
        process_batch_from_file "$file"
    else
        # 使用命令列參數批次處理
        process_batch_from_args --action revoke "$@"
    fi
}

# 比較權限差異
cmd_compare() {
    local user1="$1"
    local user2="$2"

    if [ -z "$user1" ] || [ -z "$user2" ]; then
        show_error "請指定兩個使用者名稱"
        echo "使用方式: $0 compare <username1> <username2>"
        exit 1
    fi

    shift 2

    # 解析選項
    local output_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --output)
                output_file="$2"
                shift 2
                ;;
            *)
                show_error "未知的選項: $1"
                exit 1
                ;;
        esac
    done

    # 顯示差異報告
    if [ -n "$output_file" ]; then
        format_diff_report "$user1" "$user2" > "$output_file"
        show_success "已輸出到檔案: $output_file"
    else
        format_diff_report "$user1" "$user2"
    fi
}

# 列出 Server 角色
cmd_list_server_roles() {
    echo -e "${BLUE}SQL Server 固定的 Server 層級角色：${NC}"
    echo ""
    echo "  - sysadmin          系統管理員（完整權限）"
    echo "  - serveradmin       伺服器管理員"
    echo "  - securityadmin     安全性管理員"
    echo "  - processadmin      處理程序管理員"
    echo "  - setupadmin        設定管理員"
    echo "  - bulkadmin         大量作業管理員"
    echo "  - diskadmin         磁碟管理員"
    echo "  - dbcreator         資料庫建立者"
    echo "  - public            公用（所有登入預設擁有）"
    echo ""
}

# 列出 Database 角色
cmd_list_db_roles() {
    # 解析選項
    local database=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --database)
                database="$2"
                shift 2
                ;;
            *)
                show_error "未知的選項: $1"
                exit 1
                ;;
        esac
    done

    echo -e "${BLUE}SQL Server 固定的 Database 層級角色：${NC}"
    echo ""
    echo "  - db_owner              資料庫擁有者（完整權限）"
    echo "  - db_securityadmin      安全性管理員"
    echo "  - db_accessadmin        存取管理員"
    echo "  - db_backupoperator     備份操作員"
    echo "  - db_ddladmin           DDL 管理員"
    echo "  - db_datawriter         資料寫入者"
    echo "  - db_datareader         資料讀取者"
    echo "  - db_denydatawriter     拒絕資料寫入"
    echo "  - db_denydatareader     拒絕資料讀取"
    echo ""

    if [ -n "$database" ]; then
        echo -e "${BLUE}資料庫 '$database' 的自訂角色：${NC}"
        echo ""

        local sql="
        SELECT name
        FROM sys.database_principals
        WHERE type = 'R'
        AND is_fixed_role = 0
        ORDER BY name
        "

        local custom_roles=$(execute_sql "$database" "$sql" "csv" 2>/dev/null | grep -v "^name$" | grep -v "^$")

        if [ -n "$custom_roles" ]; then
            while IFS= read -r role; do
                if [ -n "$role" ]; then
                    echo "  - $role"
                fi
            done <<< "$custom_roles"
        else
            echo "  (無自訂角色)"
        fi
        echo ""
    fi
}

# 測試連線
cmd_test_connection() {
    echo -e "${BLUE}測試 SQL Server 連線...${NC}"

    if test_connection; then
        show_success "連線測試成功"
        echo ""
        echo "伺服器: $SQL_SERVER:$SQL_PORT"
        echo "使用者: $ADMIN_USER"
    else
        show_error "連線測試失敗"
        exit 1
    fi
}

# 顯示說明
cmd_help() {
    cat << EOF
${GREEN}SQL Server 權限管理工具 v${VERSION}${NC}

使用方式:
  $0 <command> [options]

命令:
  ${CYAN}使用者管理${NC}
    create-user [options]         建立使用者並授予權限（支援多個使用者和資料庫）

  ${CYAN}查詢權限${NC}
    get-user <username>           查詢特定使用者的權限
    get-all                       查詢所有使用者的權限

  ${CYAN}設定權限${NC}
    grant <username> [options]    授予權限
    revoke <username> [options]   撤銷權限

  ${CYAN}批次處理${NC}
    grant-batch [options]         批次授予權限
    revoke-batch [options]        批次撤銷權限

  ${CYAN}權限比對${NC}
    compare <user1> <user2>       比較兩個使用者的權限差異

  ${CYAN}其他${NC}
    list-server-roles             列出 Server 層級角色
    list-db-roles                 列出 Database 層級角色
    test-connection               測試 SQL Server 連線
    help                          顯示此說明

通用選項:
  --env-file <file>               指定環境變數檔案（預設: .env）
  --format <format>               輸出格式: json, table, csv（預設: table）
  --output <file>                 輸出到檔案（預設: stdout）
  --database <dbname>             指定資料庫
  --dry-run                       預覽變更但不執行
  --verbose                       詳細輸出

建立使用者選項:
  --users <user1,user2,...>       使用者名稱（逗號分隔支援多個）
  --databases <db1,db2,...>       資料庫名稱（逗號分隔支援多個）
  --password <password>           使用者密碼
  --grant-read                    授予讀取權限 (db_datareader)
  --grant-write                   授予寫入權限 (db_datawriter)
  --grant-execute                 授予執行預存程序權限 (EXECUTE)

授予/撤銷權限選項:
  --server-role <role>            Server 層級角色（如: sysadmin）
  --db-role <role>                Database 層級角色（如: db_datareader）
  --object <object>               物件名稱（如: dbo.Users）
  --permission <perm>             物件權限（如: SELECT,INSERT）

批次處理選項:
  --file <file>                   設定檔路徑（CSV 或 JSON）
  --users <user1,user2,...>       使用者清單（逗號分隔）

範例:
  # 建立使用者（單一使用者，單一資料庫）
  $0 create-user --users app_user --databases MyAppDB --password 'StrongP@ss123' \\
    --grant-read --grant-write --grant-execute

  # 建立使用者（單一使用者，多個資料庫）
  $0 create-user --users app_user --databases "DB1,DB2,DB3" --password 'StrongP@ss123' \\
    --grant-read --grant-write --grant-execute

  # 建立使用者（多個使用者，單一資料庫）
  $0 create-user --users "user1,user2,user3" --databases MyAppDB --password 'StrongP@ss123' \\
    --grant-read --grant-write

  # 建立使用者（多個使用者，多個資料庫）
  $0 create-user --users "user1,user2" --databases "DB1,DB2" --password 'StrongP@ss123' \\
    --grant-read --grant-write --grant-execute

  # 查詢使用者權限
  $0 get-user john --format table
  $0 get-user john --database MyDB --format json
  $0 get-all --output all-permissions.csv

  # 授予權限
  $0 grant user1 --server-role sysadmin
  $0 grant user2 --database MyDB --db-role db_datareader,db_datawriter
  $0 grant user3 --database MyDB --object dbo.Users --permission SELECT,INSERT

  # 批次處理
  $0 grant-batch --file permissions.csv
  $0 grant-batch --users "user1,user2,user3" --database MyDB --db-role db_datareader

  # 權限比對
  $0 compare user1 user2
  $0 compare user1 user2 --output diff-report.txt

環境變數設定:
  1. 複製範本: cp sql-permission.env.example .env
  2. 編輯設定: nano .env
  3. 執行指令: $0 test-connection

EOF
}

#=============================================================================
# 主程式
#=============================================================================

main() {
    local command="${1:-help}"
    shift || true

    # 解析通用選項
    local env_file=".env"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --env-file)
                env_file="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    # 載入環境變數（除了 help 命令外）
    if [ "$command" != "help" ] && [ "$command" != "--help" ] && [ "$command" != "-h" ]; then
        load_env "$env_file"
    fi

    # 執行命令
    case $command in
        create-user)
            cmd_create_user "$@"
            ;;
        get-user)
            cmd_get_user "$@"
            ;;
        get-all)
            cmd_get_all "$@"
            ;;
        grant)
            cmd_grant "$@"
            ;;
        revoke)
            cmd_revoke "$@"
            ;;
        grant-batch)
            cmd_grant_batch "$@"
            ;;
        revoke-batch)
            cmd_revoke_batch "$@"
            ;;
        compare)
            cmd_compare "$@"
            ;;
        list-server-roles)
            cmd_list_server_roles "$@"
            ;;
        list-db-roles)
            cmd_list_db_roles "$@"
            ;;
        test-connection)
            cmd_test_connection "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            show_error "未知的命令: $command"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

# 執行主程式
main "$@"
