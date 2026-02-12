#!/bin/bash

#############################################################################
# HashiCorp Vault 管理工具
#
# 功能：
#   - 使用 userpass 認證登入 Vault
#   - 支援 KV secrets 的完整 CRUD 操作
#   - 支援 JSON 和表格格式輸出
#
# 需求：
#   - bash 4.0+
#   - curl
#   - jq
#
# 作者：DevOps Team
# 版本：1.0.0
#############################################################################

set -euo pipefail

#############################################################################
# 全域變數
#############################################################################

# Vault 連線資訊（從環境變數讀取）
VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-false}"
VAULT_USERNAME="${VAULT_USERNAME:-}"
VAULT_PASSWORD="${VAULT_PASSWORD:-}"

# Vault Token（認證後取得）
VAULT_TOKEN=""

# 預設值
DEFAULT_MOUNT="secret"
OUTPUT_FORMAT="json"

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#############################################################################
# 工具函式
#############################################################################

# 輸出錯誤訊息
error() {
    echo -e "${RED}[錯誤]${NC} $1" >&2
}

# 輸出成功訊息
success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

# 輸出警告訊息
warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 輸出資訊訊息
info() {
    echo -e "${BLUE}[資訊]${NC} $1"
}

# 載入 .env 檔案（如果存在）
load_env_file() {
    local env_file=".env"

    if [[ -f "$env_file" ]]; then
        info "偵測到 .env 檔案，正在載入環境變數..."

        # 使用 set -a 使所有變數自動 export
        set -a
        source "$env_file"
        set +a

        success ".env 檔案載入成功"
        return 0
    fi

    return 1
}

# 檢查必要的環境變數
check_env_vars() {
    local missing_vars=()

    if [[ -z "$VAULT_ADDR" ]]; then
        missing_vars+=("VAULT_ADDR")
    fi

    if [[ -z "$VAULT_USERNAME" ]]; then
        missing_vars+=("VAULT_USERNAME")
    fi

    if [[ -z "$VAULT_PASSWORD" ]]; then
        missing_vars+=("VAULT_PASSWORD")
    fi

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "缺少必要的環境變數："
        for var in "${missing_vars[@]}"; do
            echo "  - $var" >&2
        done
        echo "" >&2
        echo "請設定環境變數或從 .env 檔案載入：" >&2
        echo "  export VAULT_ADDR='https://vault.web.internal'" >&2
        echo "  export VAULT_SKIP_VERIFY=true" >&2
        echo "  export VAULT_USERNAME='your-username'" >&2
        echo "  export VAULT_PASSWORD='your-password'" >&2
        echo "" >&2
        echo "或從 .env 檔案載入：" >&2
        echo "  set -a && source .env && set +a" >&2
        return 1
    fi

    return 0
}

# 檢查必要的命令工具
check_dependencies() {
    local missing_deps=()

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "缺少必要的命令工具："
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep" >&2
        done
        echo "" >&2
        echo "請安裝缺少的工具：" >&2
        echo "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}" >&2
        echo "  macOS: brew install ${missing_deps[*]}" >&2
        echo "  CentOS/RHEL: sudo yum install ${missing_deps[*]}" >&2
        return 1
    fi

    return 0
}

# 建立 curl 選項
get_curl_opts() {
    local opts="-s"

    if [[ "$VAULT_SKIP_VERIFY" == "true" ]]; then
        opts="$opts -k"
    fi

    echo "$opts"
}

#############################################################################
# Vault 認證函式
#############################################################################

# 使用 userpass 方法登入 Vault
vault_login() {
    info "正在登入 Vault..."

    # 準備認證請求
    local login_payload
    login_payload=$(jq -n \
        --arg username "$VAULT_USERNAME" \
        --arg password "$VAULT_PASSWORD" \
        '{password: $password}')

    # 發送認證請求
    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$login_payload" \
        "${VAULT_ADDR}/v1/auth/userpass/login/${VAULT_USERNAME}")

    # 分離 HTTP body 和 status code
    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    # 檢查 HTTP 狀態碼
    if [[ "$http_code" != "200" ]]; then
        error "認證失敗（HTTP $http_code）"

        # 嘗試解析錯誤訊息
        local error_msg
        error_msg=$(echo "$http_body" | jq -r '.errors[]?' 2>/dev/null || echo "未知錯誤")

        if [[ -n "$error_msg" && "$error_msg" != "未知錯誤" ]]; then
            error "錯誤詳情：$error_msg"
        fi

        return 1
    fi

    # 提取 token
    VAULT_TOKEN=$(echo "$http_body" | jq -r '.auth.client_token')

    if [[ -z "$VAULT_TOKEN" || "$VAULT_TOKEN" == "null" ]]; then
        error "無法取得 Vault token"
        return 1
    fi

    success "登入成功"
    return 0
}

# 確保已登入（如果未登入則自動登入）
ensure_logged_in() {
    if [[ -z "$VAULT_TOKEN" ]]; then
        vault_login || return 1
    fi
    return 0
}

#############################################################################
# Vault KV Secret 操作函式
#############################################################################

# 讀取 secret
vault_get_secret() {
    local mount="$1"
    local path="$2"
    local format="${3:-json}"

    # 確保已登入
    ensure_logged_in || return 1

    info "正在讀取 secret: $mount/$path"

    # 準備 API 路徑（KV v2 使用 /data/ 路徑）
    local api_path="${VAULT_ADDR}/v1/${mount}/data/${path}"

    # 發送請求
    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$api_path")

    # 分離 HTTP body 和 status code
    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    # 檢查 HTTP 狀態碼
    if [[ "$http_code" != "200" ]]; then
        if [[ "$http_code" == "404" ]]; then
            error "Secret 不存在：$mount/$path"
        else
            error "讀取失敗（HTTP $http_code）"

            # 嘗試解析錯誤訊息
            local error_msg
            error_msg=$(echo "$http_body" | jq -r '.errors[]?' 2>/dev/null || echo "")

            if [[ -n "$error_msg" ]]; then
                error "錯誤詳情：$error_msg"
            fi
        fi

        return 1
    fi

    # 提取 secret data
    local secret_data
    secret_data=$(echo "$http_body" | jq -r '.data.data')

    if [[ -z "$secret_data" || "$secret_data" == "null" ]]; then
        error "無法提取 secret 資料"
        return 1
    fi

    # 根據格式輸出
    if [[ "$format" == "table" ]]; then
        # 表格格式
        echo ""
        echo "$secret_data" | jq -r 'to_entries | ["KEY", "VALUE"], ["---", "---"], (.[] | [.key, .value]) | @tsv' | column -t -s $'\t'
        echo ""
    else
        # JSON 格式
        echo "$secret_data" | jq '.'
    fi

    success "讀取成功"
    return 0
}

# 建立 secret
vault_create_secret() {
    local mount="$1"
    local path="$2"
    shift 2
    local -a kv_pairs=("$@")

    # 確保已登入
    ensure_logged_in || return 1

    # 檢查是否提供了 key=value pairs
    if [[ ${#kv_pairs[@]} -eq 0 ]]; then
        error "請提供至少一組 key=value"
        echo "範例：$0 create $mount $path key1=value1 key2=value2" >&2
        return 1
    fi

    info "正在建立 secret: $mount/$path"

    # 建立 JSON payload
    local data_json="{}"
    for pair in "${kv_pairs[@]}"; do
        # 跳過選項參數
        if [[ "$pair" == --* ]]; then
            continue
        fi

        # 分割 key=value
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # 加入 JSON
            data_json=$(echo "$data_json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
        else
            warning "忽略無效的格式：$pair（應為 key=value）"
        fi
    done

    # 檢查是否有有效的資料
    if [[ "$data_json" == "{}" ]]; then
        error "沒有有效的 key=value 資料"
        return 1
    fi

    # 準備 API payload（KV v2 需要包裝在 data 欄位中）
    local payload
    payload=$(jq -n --argjson data "$data_json" '{data: $data}')

    # 準備 API 路徑
    local api_path="${VAULT_ADDR}/v1/${mount}/data/${path}"

    # 發送請求
    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$api_path")

    # 分離 HTTP body 和 status code
    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    # 檢查 HTTP 狀態碼
    if [[ "$http_code" != "200" && "$http_code" != "204" ]]; then
        error "建立失敗（HTTP $http_code）"

        # 嘗試解析錯誤訊息
        local error_msg
        error_msg=$(echo "$http_body" | jq -r '.errors[]?' 2>/dev/null || echo "")

        if [[ -n "$error_msg" ]]; then
            error "錯誤詳情：$error_msg"
        fi

        return 1
    fi

    success "建立成功：$mount/$path"
    return 0
}

# 更新 secret
vault_update_secret() {
    local mount="$1"
    local path="$2"
    shift 2

    # 解析參數
    local -a kv_pairs=()
    local replace_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --replace)
                replace_mode=true
                shift
                ;;
            *)
                kv_pairs+=("$1")
                shift
                ;;
        esac
    done

    # 確保已登入
    ensure_logged_in || return 1

    # 檢查是否提供了 key=value pairs
    if [[ ${#kv_pairs[@]} -eq 0 ]]; then
        error "請提供至少一組 key=value"
        echo "範例：$0 update $mount $path key1=value1 key2=value2" >&2
        return 1
    fi

    if $replace_mode; then
        info "正在更新 secret（完整覆蓋）：$mount/$path"
    else
        info "正在更新 secret（部分更新）：$mount/$path"
    fi

    # 如果是部分更新，先讀取現有資料
    local existing_data="{}"
    if ! $replace_mode; then
        local api_path="${VAULT_ADDR}/v1/${mount}/data/${path}"
        local curl_opts
        curl_opts=$(get_curl_opts)

        local response
        response=$(curl $curl_opts -w "\n%{http_code}" \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            "$api_path")

        local http_body
        local http_code
        http_body=$(echo "$response" | sed -e '$d')
        http_code=$(echo "$response" | tail -n 1)

        if [[ "$http_code" == "200" ]]; then
            existing_data=$(echo "$http_body" | jq -r '.data.data // {}')
        else
            warning "無法讀取現有資料（HTTP $http_code），將建立新的 secret"
        fi
    fi

    # 建立新的資料（從現有資料開始或從空物件開始）
    local data_json="$existing_data"

    for pair in "${kv_pairs[@]}"; do
        # 分割 key=value
        if [[ "$pair" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # 更新 JSON
            data_json=$(echo "$data_json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
        else
            warning "忽略無效的格式：$pair（應為 key=value）"
        fi
    done

    # 檢查是否有有效的資料
    if [[ "$data_json" == "{}" ]]; then
        error "沒有有效的 key=value 資料"
        return 1
    fi

    # 準備 API payload
    local payload
    payload=$(jq -n --argjson data "$data_json" '{data: $data}')

    # 準備 API 路徑
    local api_path="${VAULT_ADDR}/v1/${mount}/data/${path}"

    # 發送請求
    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$api_path")

    # 分離 HTTP body 和 status code
    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    # 檢查 HTTP 狀態碼
    if [[ "$http_code" != "200" && "$http_code" != "204" ]]; then
        error "更新失敗（HTTP $http_code）"

        # 嘗試解析錯誤訊息
        local error_msg
        error_msg=$(echo "$http_body" | jq -r '.errors[]?' 2>/dev/null || echo "")

        if [[ -n "$error_msg" ]]; then
            error "錯誤詳情：$error_msg"
        fi

        return 1
    fi

    success "更新成功：$mount/$path"
    return 0
}

# 刪除 secret
vault_delete_secret() {
    local mount="$1"
    local path="$2"

    # 確保已登入
    ensure_logged_in || return 1

    warning "即將刪除 secret：$mount/$path"

    # 要求確認
    read -p "確定要刪除嗎？(y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "取消刪除操作"
        return 0
    fi

    info "正在刪除 secret: $mount/$path"

    # 準備 API 路徑（KV v2 使用 /metadata/ 路徑來永久刪除）
    local api_path="${VAULT_ADDR}/v1/${mount}/metadata/${path}"

    # 發送請求
    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X DELETE \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$api_path")

    # 分離 HTTP body 和 status code
    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    # 檢查 HTTP 狀態碼
    if [[ "$http_code" != "204" ]]; then
        if [[ "$http_code" == "404" ]]; then
            error "Secret 不存在：$mount/$path"
        else
            error "刪除失敗（HTTP $http_code）"

            # 嘗試解析錯誤訊息
            local error_msg
            error_msg=$(echo "$http_body" | jq -r '.errors[]?' 2>/dev/null || echo "")

            if [[ -n "$error_msg" ]]; then
                error "錯誤詳情：$error_msg"
            fi
        fi

        return 1
    fi

    success "刪除成功：$mount/$path"
    return 0
}

# 列出 secrets
vault_list_secrets() {
    local mount="$1"
    local path="${2:-}"

    # 確保已登入
    ensure_logged_in || return 1

    if [[ -n "$path" ]]; then
        info "正在列出 secrets: $mount/$path"
    else
        info "正在列出 secrets: $mount/"
    fi

    # 準備 API 路徑（KV v2 使用 /metadata/ 路徑來列出）
    local api_path
    if [[ -n "$path" ]]; then
        api_path="${VAULT_ADDR}/v1/${mount}/metadata/${path}"
    else
        api_path="${VAULT_ADDR}/v1/${mount}/metadata"
    fi

    # 發送請求
    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X LIST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$api_path")

    # 分離 HTTP body 和 status code
    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    # 檢查 HTTP 狀態碼
    if [[ "$http_code" != "200" ]]; then
        if [[ "$http_code" == "404" ]]; then
            warning "路徑不存在或沒有 secrets：$mount/$path"
            return 0
        else
            error "列出失敗（HTTP $http_code）"

            # 嘗試解析錯誤訊息
            local error_msg
            error_msg=$(echo "$http_body" | jq -r '.errors[]?' 2>/dev/null || echo "")

            if [[ -n "$error_msg" ]]; then
                error "錯誤詳情：$error_msg"
            fi
        fi

        return 1
    fi

    # 提取 keys
    local keys
    keys=$(echo "$http_body" | jq -r '.data.keys[]?' 2>/dev/null)

    if [[ -z "$keys" ]]; then
        warning "沒有找到任何 secrets"
        return 0
    fi

    # 輸出結果
    echo ""
    if [[ -n "$path" ]]; then
        echo "Secrets in $mount/$path:"
    else
        echo "Secrets in $mount/:"
    fi
    echo "---"
    echo "$keys" | while IFS= read -r key; do
        if [[ "$key" == */ ]]; then
            # 目錄（以 / 結尾）
            echo "  📁 $key"
        else
            # 檔案
            echo "  📄 $key"
        fi
    done
    echo ""

    success "列出成功"
    return 0
}

#############################################################################
# 主程式（待實作）
#############################################################################

# 顯示使用說明
show_usage() {
    cat << EOF
HashiCorp Vault 管理工具

使用方法：
  $0 <command> <mount> <path> [options]

命令：
  get       讀取 secret
  create    建立 secret
  update    更新 secret
  delete    刪除 secret
  list      列出 secrets

選項：
  --format <json|table>    輸出格式（預設：json）
  --replace                更新時完整覆蓋（僅用於 update）
  -h, --help               顯示此說明

範例：
  # 讀取 secret
  $0 get secrets teams/job-finder/environments/qa/db-user

  # 讀取 secret（表格格式）
  $0 get secrets teams/job-finder/environments/qa/db-user --format table

  # 建立 secret
  $0 create secrets teams/test/api-key key1=value1 key2=value2

  # 更新 secret（部分更新）
  $0 update secrets teams/test/api-key key3=value3

  # 更新 secret（完整覆蓋）
  $0 update secrets teams/test/api-key key1=new1 key2=new2 --replace

  # 列出 secrets
  $0 list secrets teams/job-finder

  # 刪除 secret
  $0 delete secrets teams/test/api-key

環境變數：
  VAULT_ADDR          Vault 伺服器位址
  VAULT_SKIP_VERIFY   跳過 TLS 驗證（true/false）
  VAULT_USERNAME      Vault 使用者名稱
  VAULT_PASSWORD      Vault 密碼

EOF
}

# 主程式入口
main() {
    # 檢查是否顯示說明
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi

    # 檢查依賴工具
    if ! check_dependencies; then
        exit 1
    fi

    # 嘗試載入 .env 檔案
    load_env_file

    # 檢查環境變數
    if ! check_env_vars; then
        exit 1
    fi

    # 解析命令
    local command="$1"
    shift

    # 根據命令執行對應的操作
    case "$command" in
        get)
            # 格式：get <mount> <path> [--format <json|table>]
            if [[ $# -lt 2 ]]; then
                error "用法：$0 get <mount> <path> [--format <json|table>]"
                exit 1
            fi

            local mount="$1"
            local path="$2"
            shift 2

            # 解析選項
            local format="json"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --format)
                        if [[ $# -lt 2 ]]; then
                            error "--format 需要指定值（json 或 table）"
                            exit 1
                        fi
                        format="$2"
                        shift 2
                        ;;
                    *)
                        error "未知的選項：$1"
                        exit 1
                        ;;
                esac
            done

            vault_get_secret "$mount" "$path" "$format"
            ;;

        create)
            # 格式：create <mount> <path> <key1>=<value1> ...
            if [[ $# -lt 3 ]]; then
                error "用法：$0 create <mount> <path> <key1>=<value1> [<key2>=<value2> ...]"
                exit 1
            fi

            local mount="$1"
            local path="$2"
            shift 2

            vault_create_secret "$mount" "$path" "$@"
            ;;

        update)
            # 格式：update <mount> <path> <key1>=<value1> ... [--replace]
            if [[ $# -lt 3 ]]; then
                error "用法：$0 update <mount> <path> <key1>=<value1> [<key2>=<value2> ...] [--replace]"
                exit 1
            fi

            local mount="$1"
            local path="$2"
            shift 2

            vault_update_secret "$mount" "$path" "$@"
            ;;

        delete)
            # 格式：delete <mount> <path>
            if [[ $# -lt 2 ]]; then
                error "用法：$0 delete <mount> <path>"
                exit 1
            fi

            local mount="$1"
            local path="$2"

            vault_delete_secret "$mount" "$path"
            ;;

        list)
            # 格式：list <mount> [<path>]
            if [[ $# -lt 1 ]]; then
                error "用法：$0 list <mount> [<path>]"
                exit 1
            fi

            local mount="$1"
            local path="${2:-}"

            vault_list_secrets "$mount" "$path"
            ;;

        *)
            error "未知的命令：$command"
            echo "" >&2
            echo "支援的命令：get, create, update, delete, list" >&2
            echo "使用 $0 --help 查看詳細說明" >&2
            exit 1
            ;;
    esac
}

# 執行主程式
main "$@"
