#!/bin/bash

#=============================================================================
# 批次處理解析模組 (parser.sh)
#=============================================================================
# 功能：
#   - 解析 CSV 格式的批次設定檔
#   - 解析 JSON 格式的批次設定檔
#   - 批次處理引擎
#=============================================================================

#=============================================================================
# 步驟 2.4.1：CSV 檔案解析器
#=============================================================================

# 解析 CSV 格式的批次設定檔
# 參數：$1 = CSV 檔案路徑
# CSV 格式：username,action,level,target,role_or_permission,database
# 範例：user1,grant,server,,sysadmin,
parse_csv() {
    local csv_file="$1"

    if ! validate_file_exists "$csv_file"; then
        return 1
    fi

    show_debug "解析 CSV 檔案: $csv_file"

    # 讀取 CSV 檔案（跳過標題行）
    local line_number=0
    while IFS=, read -r username action level target role_or_permission database; do
        line_number=$((line_number + 1))

        # 跳過標題行
        if [ $line_number -eq 1 ]; then
            continue
        fi

        # 跳過空行
        if [ -z "$username" ]; then
            continue
        fi

        # 跳過註解行
        if [[ "$username" =~ ^# ]]; then
            continue
        fi

        # 輸出解析結果（使用特殊分隔符，避免與 CSV 衝突）
        echo "${username}|${action}|${level}|${target}|${role_or_permission}|${database}"
    done < "$csv_file"
}

#=============================================================================
# 步驟 2.4.2：JSON 檔案解析器
#=============================================================================

# 解析 JSON 格式的批次設定檔
# 參數：$1 = JSON 檔案路徑
# JSON 格式範例：
# {
#   "permissions": [
#     {"username": "user1", "action": "grant", "level": "server", "role": "sysadmin"},
#     {"username": "user2", "action": "grant", "level": "database", "database": "MyDB", "roles": ["db_datareader", "db_datawriter"]}
#   ]
# }
parse_json() {
    local json_file="$1"

    if ! validate_file_exists "$json_file"; then
        return 1
    fi

    show_debug "解析 JSON 檔案: $json_file"

    # 檢查 jq 是否安裝
    if ! command -v jq &> /dev/null; then
        show_error "jq 未安裝，無法解析 JSON 檔案"
        echo "請安裝 jq："
        echo "  Ubuntu/Debian: sudo apt-get install jq"
        echo "  macOS: brew install jq"
        return 1
    fi

    # 使用 jq 解析 JSON
    jq -r '.permissions[] |
        if .level == "server" then
            "\(.username)|\(.action)|server||\(.role)|"
        elif .level == "database" then
            if .roles then
                .roles[] as $role |
                "\(.username)|\(.action)|database|\(.database)|\($role)|\(.database)"
            else
                "\(.username)|\(.action)|database|\(.database)|\(.role)|\(.database)"
            end
        elif .level == "object" then
            if .permissions then
                .permissions[] as $perm |
                "\(.username)|\(.action)|object|\(.object)|\($perm)|\(.database)"
            else
                "\(.username)|\(.action)|object|\(.object)|\(.permission)|\(.database)"
            end
        else
            empty
        end' "$json_file"
}

#=============================================================================
# 步驟 2.4.3：批次處理引擎
#=============================================================================

# 批次處理引擎
# 參數：
#   $1 = 輸入資料（來自 parse_csv 或 parse_json 的輸出）
#   $2 = 是否為檔案路徑（true/false）
process_batch() {
    local input_data="$1"
    local is_file="${2:-false}"

    local total_count=0
    local success_count=0
    local fail_count=0

    show_info "開始批次處理..."
    echo ""

    # 處理每一行
    while IFS='|' read -r username action level target role_or_permission database; do
        total_count=$((total_count + 1))

        # 顯示處理進度
        echo -e "${CYAN}[$total_count] 處理: $username - $action $level${NC}"

        # 驗證必要欄位
        if [ -z "$username" ] || [ -z "$action" ] || [ -z "$level" ]; then
            show_error "第 $total_count 行：缺少必要欄位"
            fail_count=$((fail_count + 1))
            continue
        fi

        # 根據操作類型和層級執行對應的函式
        local result=0

        case "$action" in
            grant)
                case "$level" in
                    server)
                        grant_server_role "$username" "$role_or_permission"
                        result=$?
                        ;;
                    database)
                        if [ -z "$database" ]; then
                            show_error "Database 層級操作需要指定資料庫名稱"
                            result=1
                        else
                            grant_database_role "$username" "$database" "$role_or_permission"
                            result=$?
                        fi
                        ;;
                    object)
                        if [ -z "$database" ] || [ -z "$target" ]; then
                            show_error "Object 層級操作需要指定資料庫和物件名稱"
                            result=1
                        else
                            grant_object_permission "$username" "$database" "$target" "$role_or_permission"
                            result=$?
                        fi
                        ;;
                    *)
                        show_error "未知的權限層級: $level"
                        result=1
                        ;;
                esac
                ;;
            revoke)
                case "$level" in
                    server)
                        revoke_server_role "$username" "$role_or_permission"
                        result=$?
                        ;;
                    database)
                        if [ -z "$database" ]; then
                            show_error "Database 層級操作需要指定資料庫名稱"
                            result=1
                        else
                            revoke_database_role "$username" "$database" "$role_or_permission"
                            result=$?
                        fi
                        ;;
                    object)
                        if [ -z "$database" ] || [ -z "$target" ]; then
                            show_error "Object 層級操作需要指定資料庫和物件名稱"
                            result=1
                        else
                            revoke_object_permission "$username" "$database" "$target" "$role_or_permission"
                            result=$?
                        fi
                        ;;
                    *)
                        show_error "未知的權限層級: $level"
                        result=1
                        ;;
                esac
                ;;
            *)
                show_error "未知的操作類型: $action"
                result=1
                ;;
        esac

        # 統計結果
        if [ $result -eq 0 ]; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi

        echo ""
    done <<< "$input_data"

    # 顯示摘要
    echo "========================================"
    echo -e "${GREEN}批次處理完成${NC}"
    echo "========================================"
    echo "總計: $total_count"
    echo -e "${GREEN}成功: $success_count${NC}"
    if [ $fail_count -gt 0 ]; then
        echo -e "${RED}失敗: $fail_count${NC}"
    else
        echo "失敗: $fail_count"
    fi
    echo "========================================"

    # 如果有失敗，返回錯誤碼
    if [ $fail_count -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# 從檔案批次處理
# 參數：$1 = 檔案路徑
process_batch_from_file() {
    local file="$1"

    if ! validate_file_exists "$file"; then
        return 1
    fi

    # 根據檔案副檔名判斷格式
    local file_ext="${file##*.}"
    local parsed_data

    case "$file_ext" in
        csv)
            show_info "檢測到 CSV 格式"
            parsed_data=$(parse_csv "$file")
            ;;
        json)
            show_info "檢測到 JSON 格式"
            parsed_data=$(parse_json "$file")
            ;;
        *)
            show_error "不支援的檔案格式: $file_ext（僅支援 csv 和 json）"
            return 1
            ;;
    esac

    if [ -z "$parsed_data" ]; then
        show_error "檔案解析失敗或檔案為空"
        return 1
    fi

    # 執行批次處理
    process_batch "$parsed_data"
}

#=============================================================================
# setup-user 專用解析函式
#=============================================================================

# 解析 setup-user CSV 格式
# CSV 格式：username,databases,password,grant_read,grant_write,grant_execute
# 範例：app_user,"DB1,DB2",StrongPass123!,true,true,true
parse_setup_user_csv() {
    local csv_file="$1"

    if ! validate_file_exists "$csv_file"; then
        return 1
    fi

    show_debug "解析 setup-user CSV 檔案: $csv_file"

    # 讀取 CSV 檔案（跳過標題行）
    local line_number=0
    while IFS=, read -r username databases password grant_read grant_write grant_execute; do
        line_number=$((line_number + 1))

        # 跳過標題行
        if [ $line_number -eq 1 ]; then
            continue
        fi

        # 跳過空行
        if [ -z "$username" ]; then
            continue
        fi

        # 跳過註解行
        if [[ "$username" =~ ^# ]]; then
            continue
        fi

        # 去除引號（處理 "DB1,DB2" 這類欄位）
        databases=$(echo "$databases" | sed 's/^"//;s/"$//')
        password=$(echo "$password" | sed 's/^"//;s/"$//')

        # 輸出解析結果（使用特殊分隔符）
        echo "${username}|${databases}|${password}|${grant_read}|${grant_write}|${grant_execute}"
    done < "$csv_file"
}

# 解析 setup-user JSON 格式
# JSON 格式範例：
# {
#   "users": [
#     {
#       "username": "app_user",
#       "databases": ["DB1", "DB2"],
#       "password": "StrongPass123!",
#       "grant_read": true,
#       "grant_write": true,
#       "grant_execute": true
#     }
#   ]
# }
parse_setup_user_json() {
    local json_file="$1"

    if ! validate_file_exists "$json_file"; then
        return 1
    fi

    show_debug "解析 setup-user JSON 檔案: $json_file"

    # 檢查 jq 是否安裝
    if ! command -v jq &> /dev/null; then
        show_error "jq 未安裝，無法解析 JSON 檔案"
        echo "請安裝 jq："
        echo "  Ubuntu/Debian: sudo apt-get install jq"
        echo "  macOS: brew install jq"
        return 1
    fi

    # 使用 jq 解析 JSON
    jq -r '.users[] |
        "\(.username)|\(.databases | join(","))|\(.password)|\(.grant_read)|\(.grant_write)|\(.grant_execute)"' "$json_file"
}

# 從檔案處理 setup-user
# 參數：$1 = 檔案路徑
process_setup_user_from_file() {
    local file="$1"

    if ! validate_file_exists "$file"; then
        return 1
    fi

    # 根據檔案副檔名判斷格式
    local file_ext="${file##*.}"
    local parsed_data

    case "$file_ext" in
        csv)
            show_info "檢測到 CSV 格式"
            parsed_data=$(parse_setup_user_csv "$file")
            ;;
        json)
            show_info "檢測到 JSON 格式"
            parsed_data=$(parse_setup_user_json "$file")
            ;;
        *)
            show_error "不支援的檔案格式: $file_ext（僅支援 csv 和 json）"
            return 1
            ;;
    esac

    if [ -z "$parsed_data" ]; then
        show_error "檔案解析失敗或檔案為空"
        return 1
    fi

    echo "$parsed_data"
}

# 從命令列參數批次處理
# 參數：
#   --users <user1,user2,...>
#   --action <grant|revoke>
#   --level <server|database|object>
#   --role <role_name>  (for server/database level)
#   --database <db_name>  (for database/object level)
#   --object <object_name>  (for object level)
#   --permission <permission>  (for object level)
process_batch_from_args() {
    local users=""
    local action=""
    local level=""
    local role=""
    local database=""
    local object=""
    local permission=""

    # 解析參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            --users)
                users="$2"
                shift 2
                ;;
            --action)
                action="$2"
                shift 2
                ;;
            --level)
                level="$2"
                shift 2
                ;;
            --role)
                role="$2"
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
                show_error "未知的參數: $1"
                return 1
                ;;
        esac
    done

    # 驗證必要參數
    if [ -z "$users" ] || [ -z "$action" ] || [ -z "$level" ]; then
        show_error "缺少必要參數: --users, --action, --level"
        return 1
    fi

    # 將逗號分隔的使用者清單轉換為陣列
    IFS=',' read -ra user_array <<< "$users"

    # 產生批次資料
    local batch_data=""
    for user in "${user_array[@]}"; do
        # 去除空白
        user=$(echo "$user" | xargs)

        case "$level" in
            server)
                if [ -z "$role" ]; then
                    show_error "Server 層級操作需要指定 --role"
                    return 1
                fi
                batch_data+="${user}|${action}|server||${role}|"$'\n'
                ;;
            database)
                if [ -z "$role" ] || [ -z "$database" ]; then
                    show_error "Database 層級操作需要指定 --role 和 --database"
                    return 1
                fi
                batch_data+="${user}|${action}|database|${database}|${role}|${database}"$'\n'
                ;;
            object)
                if [ -z "$permission" ] || [ -z "$database" ] || [ -z "$object" ]; then
                    show_error "Object 層級操作需要指定 --permission, --database 和 --object"
                    return 1
                fi
                batch_data+="${user}|${action}|object|${object}|${permission}|${database}"$'\n'
                ;;
            *)
                show_error "未知的權限層級: $level"
                return 1
                ;;
        esac
    done

    # 執行批次處理
    process_batch "$batch_data"
}
