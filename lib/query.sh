#!/bin/bash

#=============================================================================
# 查詢與權限設定模組 (query.sh)
#=============================================================================
# 功能：
#   - 查詢 Server 層級權限
#   - 查詢 Database 層級權限
#   - 查詢物件層級權限
#   - 授予 / 撤銷權限
#=============================================================================

#=============================================================================
# 查詢函式
#=============================================================================

# 步驟 2.2.1：查詢 Server 層級權限
# 參數：$1 = 使用者名稱
# 返回：使用者的 Server 角色清單（每行一個角色）
get_server_roles() {
    local username="$1"

    if ! validate_username "$username"; then
        return 1
    fi

    show_debug "查詢使用者 '$username' 的 Server 層級角色"

    local sql="
    SELECT r.name AS role_name
    FROM sys.server_principals u
    LEFT JOIN sys.server_role_members srm ON u.principal_id = srm.member_principal_id
    LEFT JOIN sys.server_principals r ON srm.role_principal_id = r.principal_id
    WHERE u.name = '$username'
    AND r.type = 'R'
    ORDER BY r.name
    "

    execute_sql "master" "$sql" "csv" 2>/dev/null | grep -v "^role_name$" | grep -v "^$" || echo ""
}

# 步驟 2.2.2：查詢 Database 層級權限
# 參數：
#   $1 = 使用者名稱
#   $2 = 資料庫名稱
# 返回：使用者在指定資料庫的角色清單
get_database_roles() {
    local username="$1"
    local database="$2"

    if ! validate_username "$username"; then
        return 1
    fi

    if ! validate_database "$database"; then
        return 1
    fi

    show_debug "查詢使用者 '$username' 在資料庫 '$database' 的角色"

    local sql="
    SELECT r.name AS role_name
    FROM sys.database_principals u
    LEFT JOIN sys.database_role_members drm ON u.principal_id = drm.member_principal_id
    LEFT JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
    WHERE u.name = '$username'
    AND r.type = 'R'
    ORDER BY r.name
    "

    execute_sql "$database" "$sql" "csv" 2>/dev/null | grep -v "^role_name$" | grep -v "^$" || echo ""
}

# 步驟 2.2.3：查詢物件層級權限
# 參數：
#   $1 = 使用者名稱
#   $2 = 資料庫名稱
# 返回：使用者對物件的權限清單（格式：object_name,permission_name）
get_object_permissions() {
    local username="$1"
    local database="$2"

    if ! validate_username "$username"; then
        return 1
    fi

    if ! validate_database "$database"; then
        return 1
    fi

    show_debug "查詢使用者 '$username' 在資料庫 '$database' 的物件權限"

    local sql="
    SELECT
        SCHEMA_NAME(o.schema_id) + '.' + OBJECT_NAME(dp.major_id) AS object_name,
        dp.permission_name
    FROM sys.database_permissions dp
    LEFT JOIN sys.objects o ON dp.major_id = o.object_id
    WHERE dp.grantee_principal_id = USER_ID('$username')
    AND dp.class = 1  -- OBJECT_OR_COLUMN
    ORDER BY object_name, dp.permission_name
    "

    execute_sql "$database" "$sql" "csv" 2>/dev/null | grep -v "^object_name,permission_name$" | grep -v "^$" || echo ""
}

# 步驟 2.2.4：查詢所有使用者
# 參數：$1 = 資料庫名稱（可選，如果指定則查詢該資料庫的使用者，否則查詢 Server 層級登入）
# 返回：使用者清單
get_all_users() {
    local database="${1:-}"

    if [ -z "$database" ]; then
        # 查詢 Server 層級登入
        show_debug "查詢所有 Server 層級登入"

        local sql="
        SELECT name
        FROM sys.server_principals
        WHERE type IN ('S', 'U', 'G')  -- S=SQL Login, U=Windows User, G=Windows Group
        AND name NOT LIKE '##%'  -- 排除系統帳號
        AND name NOT LIKE 'NT %'  -- 排除 NT 帳號
        ORDER BY name
        "

        execute_sql "master" "$sql" "csv" 2>/dev/null | grep -v "^name$" | grep -v "^$" || echo ""
    else
        # 查詢資料庫層級使用者
        if ! validate_database "$database"; then
            return 1
        fi

        show_debug "查詢資料庫 '$database' 的所有使用者"

        local sql="
        SELECT name
        FROM sys.database_principals
        WHERE type IN ('S', 'U', 'G')  -- S=SQL User, U=Windows User, G=Windows Group
        AND name NOT LIKE '##%'  -- 排除系統帳號
        AND name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')  -- 排除系統使用者
        ORDER BY name
        "

        execute_sql "$database" "$sql" "csv" 2>/dev/null | grep -v "^name$" | grep -v "^$" || echo ""
    fi
}

# 步驟 2.2.5：列出所有資料庫
# 返回：資料庫清單
get_all_databases() {
    show_debug "列出所有資料庫"

    local sql="
    SELECT name
    FROM sys.databases
    WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb')  -- 排除系統資料庫
    AND state = 0  -- 僅列出 ONLINE 狀態的資料庫
    ORDER BY name
    "

    execute_sql "master" "$sql" "csv" 2>/dev/null | grep -v "^name$" | grep -v "^$" || echo ""
}

# 查詢使用者的完整權限（所有層級）
# 參數：
#   $1 = 使用者名稱
#   $2 = 資料庫名稱（可選，如果指定則僅查詢該資料庫）
# 返回：JSON 格式的完整權限資訊
get_user_permissions_full() {
    local username="$1"
    local target_database="${2:-}"

    if ! validate_username "$username"; then
        return 1
    fi

    # 檢查使用者是否存在（Server 層級）
    if ! user_exists_server "$username"; then
        show_error "使用者 '$username' 不存在於 Server 層級"
        return 1
    fi

    # 查詢 Server 層級角色
    local server_roles=$(get_server_roles "$username")

    # 準備 JSON 結構
    local json_output="{"
    json_output+="\"username\":\"$username\","
    json_output+="\"server_roles\":["

    # 添加 Server 角色
    if [ -n "$server_roles" ]; then
        local first=true
        while IFS= read -r role; do
            if [ -n "$role" ]; then
                if [ "$first" = false ]; then
                    json_output+=","
                fi
                json_output+="\"$role\""
                first=false
            fi
        done <<< "$server_roles"
    fi

    json_output+="],"
    json_output+="\"databases\":{"

    # 查詢資料庫權限
    local databases
    if [ -n "$target_database" ]; then
        databases="$target_database"
    else
        databases=$(get_all_databases)
    fi

    local first_db=true
    while IFS= read -r db; do
        if [ -n "$db" ]; then
            # 檢查使用者是否存在於該資料庫
            if user_exists_database "$username" "$db"; then
                if [ "$first_db" = false ]; then
                    json_output+=","
                fi

                json_output+="\"$db\":{"

                # 查詢 Database 角色
                local db_roles=$(get_database_roles "$username" "$db")
                json_output+="\"database_roles\":["

                if [ -n "$db_roles" ]; then
                    local first_role=true
                    while IFS= read -r role; do
                        if [ -n "$role" ]; then
                            if [ "$first_role" = false ]; then
                                json_output+=","
                            fi
                            json_output+="\"$role\""
                            first_role=false
                        fi
                    done <<< "$db_roles"
                fi

                json_output+="],"

                # 查詢物件權限
                json_output+="\"object_permissions\":["

                local obj_perms=$(get_object_permissions "$username" "$db")
                if [ -n "$obj_perms" ]; then
                    local first_perm=true
                    while IFS=, read -r obj_name perm_name; do
                        if [ -n "$obj_name" ] && [ -n "$perm_name" ]; then
                            if [ "$first_perm" = false ]; then
                                json_output+=","
                            fi
                            json_output+="{\"object\":\"$obj_name\",\"permission\":\"$perm_name\"}"
                            first_perm=false
                        fi
                    done <<< "$obj_perms"
                fi

                json_output+="]"
                json_output+="}"

                first_db=false
            fi
        fi
    done <<< "$databases"

    json_output+="}"
    json_output+="}"

    echo "$json_output"
}

#=============================================================================
# 權限設定函式
#=============================================================================

# 步驟 2.3.1：授予 Server 角色
# 參數：
#   $1 = 使用者名稱
#   $2 = 角色名稱
grant_server_role() {
    local username="$1"
    local role="$2"

    if ! validate_username "$username"; then
        return 1
    fi

    if ! validate_role "$role"; then
        return 1
    fi

    show_debug "授予使用者 '$username' Server 角色 '$role'"

    # 寫入稽核日誌
    write_audit_log "grant_server_role" "$username" "role=$role"

    local sql="
    IF NOT EXISTS (
        SELECT 1 FROM sys.server_principals u
        JOIN sys.server_role_members srm ON u.principal_id = srm.member_principal_id
        JOIN sys.server_principals r ON srm.role_principal_id = r.principal_id
        WHERE u.name = '$username' AND r.name = '$role'
    )
    BEGIN
        ALTER SERVER ROLE [$role] ADD MEMBER [$username];
        PRINT '已授予 Server 角色 [$role]';
    END
    ELSE
    BEGIN
        PRINT '使用者已擁有 Server 角色 [$role]';
    END
    "

    if execute_sql_quiet "master" "$sql"; then
        show_success "已授予 Server 角色 '$role' 給使用者 '$username'"
        return 0
    else
        show_error "授予 Server 角色失敗"
        return 1
    fi
}

# 步驟 2.3.2：授予 Database 角色
# 參數：
#   $1 = 使用者名稱
#   $2 = 資料庫名稱
#   $3 = 角色名稱
grant_database_role() {
    local username="$1"
    local database="$2"
    local role="$3"

    if ! validate_username "$username"; then
        return 1
    fi

    if ! validate_database "$database"; then
        return 1
    fi

    if ! validate_role "$role"; then
        return 1
    fi

    show_debug "授予使用者 '$username' 在資料庫 '$database' 的角色 '$role'"

    # 寫入稽核日誌
    write_audit_log "grant_database_role" "$username" "database=$database, role=$role"

    local sql="
    IF NOT EXISTS (
        SELECT 1 FROM sys.database_principals u
        JOIN sys.database_role_members drm ON u.principal_id = drm.member_principal_id
        JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
        WHERE u.name = '$username' AND r.name = '$role'
    )
    BEGIN
        ALTER ROLE [$role] ADD MEMBER [$username];
        PRINT '已授予 Database 角色 [$role]';
    END
    ELSE
    BEGIN
        PRINT '使用者已擁有 Database 角色 [$role]';
    END
    "

    if execute_sql_quiet "$database" "$sql"; then
        show_success "已授予 Database 角色 '$role' 給使用者 '$username' (資料庫: $database)"
        return 0
    else
        show_error "授予 Database 角色失敗"
        return 1
    fi
}

# 步驟 2.3.3：授予物件權限
# 參數：
#   $1 = 使用者名稱
#   $2 = 資料庫名稱
#   $3 = 物件名稱（如：dbo.Users）
#   $4 = 權限名稱（如：SELECT）
grant_object_permission() {
    local username="$1"
    local database="$2"
    local object="$3"
    local permission="$4"

    if ! validate_username "$username"; then
        return 1
    fi

    if ! validate_database "$database"; then
        return 1
    fi

    show_debug "授予使用者 '$username' 對物件 '$object' 的 '$permission' 權限"

    # 寫入稽核日誌
    write_audit_log "grant_object_permission" "$username" "database=$database, object=$object, permission=$permission"

    local sql="
    GRANT $permission ON $object TO [$username];
    PRINT '已授予物件權限 $permission ON $object';
    "

    if execute_sql_quiet "$database" "$sql"; then
        show_success "已授予 '$permission' 權限給使用者 '$username' (物件: $object)"
        return 0
    else
        show_error "授予物件權限失敗"
        return 1
    fi
}

# 步驟 2.3.4：撤銷 Server 角色
revoke_server_role() {
    local username="$1"
    local role="$2"

    if ! validate_username "$username"; then
        return 1
    fi

    if ! validate_role "$role"; then
        return 1
    fi

    show_debug "撤銷使用者 '$username' 的 Server 角色 '$role'"

    # 寫入稽核日誌
    write_audit_log "revoke_server_role" "$username" "role=$role"

    local sql="
    ALTER SERVER ROLE [$role] DROP MEMBER [$username];
    PRINT '已撤銷 Server 角色 [$role]';
    "

    if execute_sql_quiet "master" "$sql"; then
        show_success "已撤銷使用者 '$username' 的 Server 角色 '$role'"
        return 0
    else
        show_error "撤銷 Server 角色失敗"
        return 1
    fi
}

# 撤銷 Database 角色
revoke_database_role() {
    local username="$1"
    local database="$2"
    local role="$3"

    if ! validate_username "$username"; then
        return 1
    fi

    if ! validate_database "$database"; then
        return 1
    fi

    if ! validate_role "$role"; then
        return 1
    fi

    show_debug "撤銷使用者 '$username' 在資料庫 '$database' 的角色 '$role'"

    # 寫入稽核日誌
    write_audit_log "revoke_database_role" "$username" "database=$database, role=$role"

    local sql="
    ALTER ROLE [$role] DROP MEMBER [$username];
    PRINT '已撤銷 Database 角色 [$role]';
    "

    if execute_sql_quiet "$database" "$sql"; then
        show_success "已撤銷使用者 '$username' 的 Database 角色 '$role' (資料庫: $database)"
        return 0
    else
        show_error "撤銷 Database 角色失敗"
        return 1
    fi
}

# 撤銷物件權限
revoke_object_permission() {
    local username="$1"
    local database="$2"
    local object="$3"
    local permission="$4"

    if ! validate_username "$username"; then
        return 1
    fi

    if ! validate_database "$database"; then
        return 1
    fi

    show_debug "撤銷使用者 '$username' 對物件 '$object' 的 '$permission' 權限"

    # 寫入稽核日誌
    write_audit_log "revoke_object_permission" "$username" "database=$database, object=$object, permission=$permission"

    local sql="
    REVOKE $permission ON $object FROM [$username];
    PRINT '已撤銷物件權限 $permission ON $object';
    "

    if execute_sql_quiet "$database" "$sql"; then
        show_success "已撤銷使用者 '$username' 對物件 '$object' 的 '$permission' 權限"
        return 0
    else
        show_error "撤銷物件權限失敗"
        return 1
    fi
}
