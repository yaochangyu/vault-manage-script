#!/bin/bash

#=============================================================================
# 工具函式模組 (utils.sh)
#=============================================================================
# 功能：
#   - 訊息顯示（成功、錯誤、警告）
#   - 參數驗證
#   - 稽核日誌記錄
#   - 其他工具函式
#=============================================================================

#=============================================================================
# 顏色定義（如果尚未定義）
#=============================================================================
RED=${RED:-'\033[0;31m'}
GREEN=${GREEN:-'\033[0;32m'}
YELLOW=${YELLOW:-'\033[1;33m'}
BLUE=${BLUE:-'\033[0;34m'}
CYAN=${CYAN:-'\033[0;36m'}
NC=${NC:-'\033[0m'}

#=============================================================================
# 訊息顯示函式
#=============================================================================

# 顯示成功訊息
show_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 顯示錯誤訊息
show_error() {
    echo -e "${RED}✗ 錯誤: $1${NC}" >&2
}

# 顯示警告訊息
show_warning() {
    echo -e "${YELLOW}⚠ 警告: $1${NC}"
}

# 顯示資訊訊息
show_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# 顯示除錯訊息
show_debug() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${CYAN}[DEBUG] $1${NC}"
    fi
}

#=============================================================================
# 參數驗證函式
#=============================================================================

# 驗證使用者名稱
validate_username() {
    local username="$1"

    if [ -z "$username" ]; then
        show_error "使用者名稱不可為空"
        return 1
    fi

    # 檢查是否包含非法字元（基本檢查）
    if [[ "$username" =~ [\;\'\"\`\$] ]]; then
        show_error "使用者名稱包含非法字元"
        return 1
    fi

    return 0
}

# 驗證資料庫名稱
validate_database() {
    local database="$1"

    if [ -z "$database" ]; then
        show_error "資料庫名稱不可為空"
        return 1
    fi

    # 檢查是否包含非法字元
    if [[ "$database" =~ [\;\'\"\`\$] ]]; then
        show_error "資料庫名稱包含非法字元"
        return 1
    fi

    return 0
}

# 驗證角色名稱
validate_role() {
    local role="$1"

    if [ -z "$role" ]; then
        show_error "角色名稱不可為空"
        return 1
    fi

    # 檢查是否包含非法字元
    if [[ "$role" =~ [\;\'\"\`\$] ]]; then
        show_error "角色名稱包含非法字元"
        return 1
    fi

    return 0
}

# 驗證檔案是否存在
validate_file_exists() {
    local file="$1"

    if [ ! -f "$file" ]; then
        show_error "檔案不存在: $file"
        return 1
    fi

    return 0
}

#=============================================================================
# 稽核日誌函式
#=============================================================================

# 寫入稽核日誌
# 參數：
#   $1 = 操作類型（grant, revoke, query, etc.）
#   $2 = 目標使用者
#   $3 = 詳細資訊
write_audit_log() {
    if [ "$ENABLE_AUDIT_LOG" != "true" ]; then
        return 0
    fi

    local action="$1"
    local target_user="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 建立日誌訊息（不包含密碼）
    local log_message="$timestamp [INFO] User: $ADMIN_USER | Action: $action | Target: $target_user | Details: $details"

    # 寫入日誌檔案
    echo "$log_message" >> "$AUDIT_LOG_FILE"

    if [ "$VERBOSE" = "true" ]; then
        show_debug "稽核日誌已記錄: $action -> $target_user"
    fi
}

#=============================================================================
# 其他工具函式
#=============================================================================

# 將逗號分隔的字串轉換為陣列
csv_to_array() {
    local csv_string="$1"
    local -n result_array=$2  # 使用 nameref

    IFS=',' read -ra result_array <<< "$csv_string"
}

# 檢查使用者是否存在（Server 層級）
user_exists_server() {
    local username="$1"

    local sql="SELECT COUNT(*) FROM sys.server_principals WHERE name = '$username'"
    local count=$(execute_sql_scalar "master" "$sql")

    if [ "$count" -gt 0 ]; then
        return 0  # 使用者存在
    else
        return 1  # 使用者不存在
    fi
}

# 檢查使用者是否存在（Database 層級）
user_exists_database() {
    local username="$1"
    local database="$2"

    local sql="SELECT COUNT(*) FROM sys.database_principals WHERE name = '$username'"
    local count=$(execute_sql_scalar "$database" "$sql")

    if [ "$count" -gt 0 ]; then
        return 0  # 使用者存在
    else
        return 1  # 使用者不存在
    fi
}

# 檢查資料庫是否存在
database_exists() {
    local database="$1"

    local sql="SELECT COUNT(*) FROM sys.databases WHERE name = '$database'"
    local count=$(execute_sql_scalar "master" "$sql")

    if [ "$count" -gt 0 ]; then
        return 0  # 資料庫存在
    else
        return 1  # 資料庫不存在
    fi
}

# 確認操作（互動式）
confirm_action() {
    local message="$1"
    local default="${2:-no}"  # 預設為 no

    echo -e "${YELLOW}$message${NC}"
    if [ "$default" = "yes" ]; then
        read -p "確定要繼續嗎？(Y/n): " confirm
        confirm=${confirm:-Y}
    else
        read -p "確定要繼續嗎？(y/N): " confirm
        confirm=${confirm:-N}
    fi

    case "$confirm" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 正規化權限資料結構（用於權限比對）
normalize_permissions() {
    local permissions_json="$1"

    # TODO: 實作權限資料正規化
    echo "$permissions_json"
}

# 比較兩組權限的差異
compare_permissions() {
    local perm1_json="$1"
    local perm2_json="$2"

    # TODO: 實作權限差異比對
    echo "TODO: compare_permissions"
}

# 產生同步建議
generate_sync_suggestions() {
    local diff_json="$1"

    # TODO: 實作同步建議產生器
    echo "TODO: generate_sync_suggestions"
}
