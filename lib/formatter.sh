#!/bin/bash

#=============================================================================
# 輸出格式化模組 (formatter.sh)
#=============================================================================
# 功能：
#   - JSON 格式輸出
#   - 表格格式輸出
#   - CSV 格式輸出
#   - 差異報告格式化
#=============================================================================

#=============================================================================
# 步驟 2.5.1：JSON 格式化
#=============================================================================

# 格式化 JSON 輸出
# 參數：$1 = JSON 字串
format_json() {
    local json_data="$1"

    # 檢查 jq 是否安裝
    if command -v jq &> /dev/null; then
        # 使用 jq 美化 JSON
        echo "$json_data" | jq .
    else
        # 沒有 jq，直接輸出原始 JSON
        echo "$json_data"
    fi
}

# 格式化使用者權限為 JSON
# 參數：$1 = 使用者名稱, $2 = 資料庫名稱（可選）
format_user_permissions_json() {
    local username="$1"
    local database="${2:-}"

    # 使用 get_user_permissions_full 函式取得完整權限
    local permissions_json=$(get_user_permissions_full "$username" "$database")

    format_json "$permissions_json"
}

#=============================================================================
# 步驟 2.5.2：表格格式化
#=============================================================================

# 格式化表格輸出
# 參數：$1 = 使用者名稱, $2 = 資料庫名稱（可選）
format_user_permissions_table() {
    local username="$1"
    local database="${2:-}"

    echo "========================================"
    echo "使用者: $username"
    echo "========================================"
    echo ""

    # Server 層級角色
    echo -e "${BLUE}[Server 層級角色]${NC}"
    local server_roles=$(get_server_roles "$username")

    if [ -n "$server_roles" ]; then
        while IFS= read -r role; do
            if [ -n "$role" ]; then
                echo "  - $role"
            fi
        done <<< "$server_roles"
    else
        echo "  (無)"
    fi

    echo ""

    # 資料庫權限
    local databases
    if [ -n "$database" ]; then
        databases="$database"
    else
        databases=$(get_all_databases)
    fi

    while IFS= read -r db; do
        if [ -n "$db" ]; then
            # 檢查使用者是否存在於該資料庫
            if user_exists_database "$username" "$db"; then
                echo -e "${BLUE}[Database: $db]${NC}"

                # Database 角色
                echo "  角色:"
                local db_roles=$(get_database_roles "$username" "$db")

                if [ -n "$db_roles" ]; then
                    while IFS= read -r role; do
                        if [ -n "$role" ]; then
                            echo "    - $role"
                        fi
                    done <<< "$db_roles"
                else
                    echo "    (無)"
                fi

                # 物件權限
                echo ""
                echo "  物件權限:"
                local obj_perms=$(get_object_permissions "$username" "$db")

                if [ -n "$obj_perms" ]; then
                    local current_object=""
                    while IFS=, read -r obj_name perm_name; do
                        if [ -n "$obj_name" ] && [ -n "$perm_name" ]; then
                            if [ "$obj_name" != "$current_object" ]; then
                                echo "    物件: $obj_name"
                                current_object="$obj_name"
                            fi
                            echo "      - $perm_name"
                        fi
                    done <<< "$obj_perms"
                else
                    echo "    (無)"
                fi

                echo ""
            fi
        fi
    done <<< "$databases"

    echo "========================================"
}

# 格式化所有使用者權限為表格
# 參數：$1 = 資料庫名稱（可選）
format_all_users_table() {
    local database="${1:-}"

    echo "========================================"
    echo "所有使用者權限摘要"
    echo "========================================"
    echo ""

    # 取得所有使用者
    local users=$(get_all_users)

    if [ -z "$users" ]; then
        echo "(無使用者)"
        return 0
    fi

    # 表格標題
    printf "%-20s %-30s %-30s\n" "使用者" "Server 角色" "Database 角色"
    echo "--------------------------------------------------------------------------------"

    while IFS= read -r user; do
        if [ -n "$user" ]; then
            # 取得 Server 角色
            local server_roles=$(get_server_roles "$user" | tr '\n' ',' | sed 's/,$//')
            if [ -z "$server_roles" ]; then
                server_roles="(無)"
            fi

            # 取得 Database 角色（僅第一個資料庫）
            local db_roles=""
            if [ -n "$database" ]; then
                db_roles=$(get_database_roles "$user" "$database" | tr '\n' ',' | sed 's/,$//')
            else
                local first_db=$(get_all_databases | head -n 1)
                if [ -n "$first_db" ] && user_exists_database "$user" "$first_db"; then
                    db_roles=$(get_database_roles "$user" "$first_db" | tr '\n' ',' | sed 's/,$//')
                fi
            fi

            if [ -z "$db_roles" ]; then
                db_roles="(無)"
            fi

            printf "%-20s %-30s %-30s\n" "$user" "$server_roles" "$db_roles"
        fi
    done <<< "$users"

    echo ""
}

#=============================================================================
# 步驟 2.5.3：CSV 格式化
#=============================================================================

# 格式化使用者權限為 CSV
# 參數：$1 = 使用者名稱, $2 = 資料庫名稱（可選）
format_user_permissions_csv() {
    local username="$1"
    local database="${2:-}"

    # CSV 標題
    echo "username,level,database,object,role_or_permission"

    # Server 層級角色
    local server_roles=$(get_server_roles "$username")
    if [ -n "$server_roles" ]; then
        while IFS= read -r role; do
            if [ -n "$role" ]; then
                echo "$username,server,,,\"$role\""
            fi
        done <<< "$server_roles"
    fi

    # 資料庫權限
    local databases
    if [ -n "$database" ]; then
        databases="$database"
    else
        databases=$(get_all_databases)
    fi

    while IFS= read -r db; do
        if [ -n "$db" ]; then
            if user_exists_database "$username" "$db"; then
                # Database 角色
                local db_roles=$(get_database_roles "$username" "$db")
                if [ -n "$db_roles" ]; then
                    while IFS= read -r role; do
                        if [ -n "$role" ]; then
                            echo "$username,database,\"$db\",,\"$role\""
                        fi
                    done <<< "$db_roles"
                fi

                # 物件權限
                local obj_perms=$(get_object_permissions "$username" "$db")
                if [ -n "$obj_perms" ]; then
                    while IFS=, read -r obj_name perm_name; do
                        if [ -n "$obj_name" ] && [ -n "$perm_name" ]; then
                            echo "$username,object,\"$db\",\"$obj_name\",\"$perm_name\""
                        fi
                    done <<< "$obj_perms"
                fi
            fi
        fi
    done <<< "$databases"
}

# 格式化所有使用者權限為 CSV
# 參數：$1 = 資料庫名稱（可選）
format_all_users_csv() {
    local database="${1:-}"

    # CSV 標題
    echo "username,level,database,object,role_or_permission"

    # 取得所有使用者
    local users=$(get_all_users)

    if [ -z "$users" ]; then
        return 0
    fi

    while IFS= read -r user; do
        if [ -n "$user" ]; then
            # Server 層級角色
            local server_roles=$(get_server_roles "$user")
            if [ -n "$server_roles" ]; then
                while IFS= read -r role; do
                    if [ -n "$role" ]; then
                        echo "$user,server,,,\"$role\""
                    fi
                done <<< "$server_roles"
            fi

            # 資料庫權限
            local databases
            if [ -n "$database" ]; then
                databases="$database"
            else
                databases=$(get_all_databases)
            fi

            while IFS= read -r db; do
                if [ -n "$db" ]; then
                    if user_exists_database "$user" "$db"; then
                        # Database 角色
                        local db_roles=$(get_database_roles "$user" "$db")
                        if [ -n "$db_roles" ]; then
                            while IFS= read -r role; do
                                if [ -n "$role" ]; then
                                    echo "$user,database,\"$db\",,\"$role\""
                                fi
                            done <<< "$db_roles"
                        fi

                        # 物件權限
                        local obj_perms=$(get_object_permissions "$user" "$db")
                        if [ -n "$obj_perms" ]; then
                            while IFS=, read -r obj_name perm_name; do
                                if [ -n "$obj_name" ] && [ -n "$perm_name" ]; then
                                    echo "$user,object,\"$db\",\"$obj_name\",\"$perm_name\""
                                fi
                            done <<< "$obj_perms"
                        fi
                    fi
                fi
            done <<< "$databases"
        fi
    done <<< "$users"
}

#=============================================================================
# 差異報告格式化
#=============================================================================

# 格式化權限比對差異報告
# 參數：$1 = 使用者1, $2 = 使用者2
format_diff_report() {
    local user1="$1"
    local user2="$2"

    echo "========================================"
    echo "權限差異比對報告"
    echo "========================================"
    echo "使用者 1: $user1"
    echo "使用者 2: $user2"
    echo "========================================"
    echo ""

    # 取得兩個使用者的完整權限
    local perm1_json=$(get_user_permissions_full "$user1")
    local perm2_json=$(get_user_permissions_full "$user2")

    # TODO: 實作詳細的差異比對邏輯
    # 目前先顯示兩個使用者的權限

    echo -e "${BLUE}[$user1 的權限]${NC}"
    format_user_permissions_table "$user1"
    echo ""

    echo -e "${BLUE}[$user2 的權限]${NC}"
    format_user_permissions_table "$user2"
    echo ""

    echo "========================================"
    echo "差異分析（待實作詳細比對）"
    echo "========================================"
}
