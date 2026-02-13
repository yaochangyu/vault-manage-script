#!/bin/bash

#############################################################################
# Docker 環境初始化腳本（整合版）
#
# 功能：
#   1. 啟動 SQL Server 和 Vault 容器
#   2. 等待服務就緒
#   3. 建立指定的資料庫
#   4. 初始化 Vault（可選）
#   5. 驗證連線
#
# 使用方式：
#   ./docker-init.sh                          # 僅啟動容器
#   ./docker-init.sh MyAppDB                  # 啟動容器並建立資料庫
#   ./docker-init.sh MyAppDB TestDB           # 啟動容器並建立多個資料庫
#   ./docker-init.sh --init-vault             # 啟動容器並初始化 Vault
#   ./docker-init.sh --init-vault MyAppDB     # 啟動容器、建立資料庫並初始化 Vault
#############################################################################

set -euo pipefail

# 腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 全域變數
INIT_VAULT=false
DATABASES=()

# Vault 連線資訊
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-false}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
VAULT_USERNAME="${VAULT_USERNAME:-}"
VAULT_PASSWORD="${VAULT_PASSWORD:-}"

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 輸出函式
error() {
    echo -e "${RED}[錯誤]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

info() {
    echo -e "${BLUE}[資訊]${NC} $1"
}

#############################################################################
# 工具函式
#############################################################################

# 解析命令列參數
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --init-vault)
                INIT_VAULT=true
                shift
                ;;
            -*)
                error "未知參數: $1"
                echo ""
                echo "使用方式："
                echo "  ./docker-init.sh [--init-vault] [DB1 DB2 ...]"
                exit 1
                ;;
            *)
                DATABASES+=("$1")
                shift
                ;;
        esac
    done
}

# 載入 .env 檔案（如果存在）
load_env_file() {
    local env_file="${SCRIPT_DIR}/.env"

    if [[ ! -f "$env_file" ]]; then
        return 0
    fi

    info "偵測到 .env 檔案，正在載入..."

    # 使用 set -a 使所有變數自動 export
    set -a
    source "$env_file"
    set +a

    # 更新 Vault 環境變數
    VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
    VAULT_TOKEN="${VAULT_TOKEN:-}"
    VAULT_USERNAME="${VAULT_USERNAME:-}"
    VAULT_PASSWORD="${VAULT_PASSWORD:-}"

    success ".env 檔案載入成功"
    return 0
}

# 檢查 Vault 初始化所需的環境變數
check_vault_env_vars() {
    local missing_vars=()

    if [[ -z "$VAULT_TOKEN" ]]; then
        missing_vars+=("VAULT_TOKEN")
    fi

    if [[ -z "$VAULT_USERNAME" ]]; then
        missing_vars+=("VAULT_USERNAME")
    fi

    if [[ -z "$VAULT_PASSWORD" ]]; then
        missing_vars+=("VAULT_PASSWORD")
    fi

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "Vault 初始化需要以下環境變數："
        for var in "${missing_vars[@]}"; do
            echo "  - $var" >&2
        done
        echo "" >&2
        echo "請建立 .env 檔案或設定環境變數：" >&2
        echo "" >&2
        echo "範例 .env 檔案：" >&2
        echo "  VAULT_ADDR=http://localhost:8200" >&2
        echo "  VAULT_TOKEN=myroot" >&2
        echo "  VAULT_USERNAME=admin" >&2
        echo "  VAULT_PASSWORD=YourSecurePassword" >&2
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
        error "Vault 初始化需要以下工具："
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep" >&2
        done
        echo "" >&2
        echo "請安裝缺少的工具" >&2
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

# 檢查 docker compose 是否安裝
check_docker_compose() {
    if ! command -v docker compose &> /dev/null; then
        error "未找到 docker compose 命令"
        echo ""
        echo "請先安裝 docker compose："
        echo "  https://docs.docker.com/compose/install/"
        exit 1
    fi
}

# 啟動容器
start_containers() {
    info "正在啟動 Docker 容器..."
    echo ""

    if docker compose up -d; then
        success "容器啟動命令已執行"
    else
        error "容器啟動失敗"
        exit 1
    fi

    echo ""
}

# 等待 SQL Server 就緒
wait_for_sqlserver() {
    info "等待 SQL Server 啟動..."
    echo ""

    local max_attempts=30
    local attempt=0
    local wait_time=2

    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))

        if docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd \
            -S localhost \
            -U sa \
            -P "YourStrongPassword!" \
            -C \
            -Q "SELECT 1" &> /dev/null; then
            echo ""
            success "SQL Server 已就緒！"
            return 0
        fi

        echo -n "."
        sleep $wait_time
    done

    echo ""
    error "SQL Server 啟動逾時（${max_attempts} 次嘗試）"
    echo ""
    echo "請檢查容器日誌："
    echo "  docker compose logs sqlserver"
    exit 1
}

# 等待 Vault 就緒
wait_for_vault() {
    info "等待 Vault 啟動..."
    echo ""

    local max_attempts=30
    local attempt=0
    local wait_time=2

    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))

        if curl -s http://localhost:8200/v1/sys/health &> /dev/null; then
            echo ""
            success "Vault 已就緒！"
            return 0
        fi

        echo -n "."
        sleep $wait_time
    done

    echo ""
    warning "Vault 啟動逾時（${max_attempts} 次嘗試）"
    echo "這不會影響 SQL Server 的使用"
    return 0
}

# 建立資料庫
create_databases() {
    if [ ${#DATABASES[@]} -eq 0 ]; then
        info "未指定資料庫，跳過資料庫建立步驟"
        return 0
    fi

    echo ""
    info "準備建立資料庫..."
    echo ""

    # 設定環境變數
    export SQL_SERVER=127.0.0.1
    export SQL_PORT=1433
    export ADMIN_USER=sa
    export ADMIN_PASSWORD="YourStrongPassword!"

    for db in "${DATABASES[@]}"; do
        info "正在建立資料庫: $db"

        if "${SCRIPT_DIR}/create-database.sh" "$db"; then
            success "資料庫 '$db' 建立完成"
        else
            error "資料庫 '$db' 建立失敗"
            return 1
        fi

        echo ""
    done
}

#############################################################################
# Vault 初始化函式
#############################################################################

# 檢查 Vault 狀態
check_vault_health() {
    info "正在檢查 Vault 伺服器狀態..."

    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" "${VAULT_ADDR}/v1/sys/health" 2>/dev/null || echo "")

    if [[ -z "$response" ]]; then
        error "無法連線到 Vault 伺服器：$VAULT_ADDR"
        return 1
    fi

    local http_code
    http_code=$(echo "$response" | tail -n 1)

    if [[ "$http_code" != "200" ]]; then
        error "Vault 伺服器狀態異常（HTTP $http_code）"
        return 1
    fi

    success "Vault 伺服器正常運作"
    return 0
}

# 啟用 userpass 認證方法
enable_userpass() {
    info "正在檢查 userpass 認證方法狀態..."

    local curl_opts
    curl_opts=$(get_curl_opts)

    # 檢查 userpass 是否已啟用
    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "${VAULT_ADDR}/v1/sys/auth")

    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    if [[ "$http_code" != "200" ]]; then
        error "無法檢查認證方法狀態（HTTP $http_code）"
        return 1
    fi

    # 檢查 userpass/ 是否存在
    local userpass_enabled
    userpass_enabled=$(echo "$http_body" | jq -r '.data | has("userpass/")')

    if [[ "$userpass_enabled" == "true" ]]; then
        success "userpass 認證方法已啟用"
        return 0
    fi

    # 啟用 userpass
    info "正在啟用 userpass 認證方法..."

    local enable_payload
    enable_payload=$(jq -n '{type: "userpass"}')

    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$enable_payload" \
        "${VAULT_ADDR}/v1/sys/auth/userpass")

    http_code=$(echo "$response" | tail -n 1)

    if [[ "$http_code" != "204" ]]; then
        error "啟用 userpass 失敗（HTTP $http_code）"
        return 1
    fi

    success "userpass 認證方法已成功啟用"
    return 0
}

# 建立管理員 policy
create_admin_policy() {
    local policy_name="admin"

    info "正在建立管理員 policy：$policy_name"

    # 建立 admin policy 內容
    local policy_content
    policy_content=$(cat <<'EOF'
# Admin policy - full access to all paths

# Full access to secrets
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage auth methods
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Manage policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List existing policies
path "sys/policies/acl" {
  capabilities = ["list"]
}

# Manage secret engines
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List existing secret engines
path "sys/mounts" {
  capabilities = ["read", "list"]
}

# Health check
path "sys/health" {
  capabilities = ["read", "sudo"]
}

# Manage leases
path "sys/leases/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Full access to userpass users
path "auth/userpass/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
)

    # 準備 API payload
    local payload
    payload=$(jq -n --arg policy "$policy_content" '{policy: $policy}')

    # 發送請求
    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X PUT \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${VAULT_ADDR}/v1/sys/policies/acl/${policy_name}")

    local http_code
    http_code=$(echo "$response" | tail -n 1)

    if [[ "$http_code" != "204" ]]; then
        error "建立 policy 失敗（HTTP $http_code）"
        return 1
    fi

    success "管理員 policy 建立成功：$policy_name"
    return 0
}

# 建立管理員使用者
create_admin_user() {
    info "正在建立管理員使用者：$VAULT_USERNAME"

    # 建立使用者 payload
    local user_payload
    user_payload=$(jq -n \
        --arg password "$VAULT_PASSWORD" \
        '{password: $password, policies: "admin"}')

    # 發送請求
    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$user_payload" \
        "${VAULT_ADDR}/v1/auth/userpass/users/${VAULT_USERNAME}")

    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    if [[ "$http_code" != "204" ]]; then
        error "建立使用者失敗（HTTP $http_code）"

        local error_msg
        error_msg=$(echo "$http_body" | jq -r '.errors[]?' 2>/dev/null || echo "")

        if [[ -n "$error_msg" ]]; then
            error "錯誤詳情：$error_msg"
        fi

        return 1
    fi

    success "管理員使用者建立成功：$VAULT_USERNAME"
    return 0
}

# 測試管理員登入
test_admin_login() {
    info "正在測試管理員登入..."

    local login_payload
    login_payload=$(jq -n \
        --arg password "$VAULT_PASSWORD" \
        '{password: $password}')

    local curl_opts
    curl_opts=$(get_curl_opts)

    local response
    response=$(curl $curl_opts -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$login_payload" \
        "${VAULT_ADDR}/v1/auth/userpass/login/${VAULT_USERNAME}")

    local http_body
    local http_code
    http_body=$(echo "$response" | sed -e '$d')
    http_code=$(echo "$response" | tail -n 1)

    if [[ "$http_code" != "200" ]]; then
        error "登入測試失敗（HTTP $http_code）"
        return 1
    fi

    local token
    token=$(echo "$http_body" | jq -r '.auth.client_token')

    if [[ -z "$token" || "$token" == "null" ]]; then
        error "無法取得 token"
        return 1
    fi

    success "登入測試成功"
    info "管理員 token：${token:0:20}..."
    return 0
}

# 執行 Vault 完整初始化
init_vault() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           HashiCorp Vault 初始化                               ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 檢查依賴工具
    if ! check_dependencies; then
        error "Vault 初始化失敗：缺少必要工具"
        return 1
    fi

    # 檢查環境變數
    if ! check_vault_env_vars; then
        error "Vault 初始化失敗：缺少必要環境變數"
        return 1
    fi

    # 顯示配置資訊
    info "Vault 配置資訊："
    echo "  Vault 位址：$VAULT_ADDR"
    echo "  管理員帳號：$VAULT_USERNAME"
    echo ""

    # 執行初始化步驟
    info "開始初始化..."
    echo ""

    # 1. 檢查 Vault 健康狀態
    if ! check_vault_health; then
        error "Vault 初始化失敗：健康檢查未通過"
        return 1
    fi

    # 2. 啟用 userpass 認證方法
    if ! enable_userpass; then
        error "Vault 初始化失敗：無法啟用 userpass"
        return 1
    fi

    # 3. 建立管理員 policy
    if ! create_admin_policy; then
        error "Vault 初始化失敗：無法建立 policy"
        return 1
    fi

    # 4. 建立管理員使用者
    if ! create_admin_user; then
        error "Vault 初始化失敗：無法建立使用者"
        return 1
    fi

    # 5. 測試管理員登入
    if ! test_admin_login; then
        error "Vault 初始化失敗：登入測試失敗"
        return 1
    fi

    echo ""
    success "Vault 初始化完成！"
    echo ""
    echo "管理員登入資訊："
    echo "  帳號：$VAULT_USERNAME"
    echo "  密碼：（已設定）"
    echo ""

    return 0
}

# 顯示連線資訊
show_connection_info() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                     連線資訊                                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}SQL Server:${NC}"
    echo "  主機: 127.0.0.1"
    echo "  端口: 1433"
    echo "  帳號: sa"
    echo "  密碼: YourStrongPassword!"
    echo ""
    echo -e "${BLUE}HashiCorp Vault:${NC}"
    echo "  URL:   http://localhost:8200"

    if [[ "$INIT_VAULT" == "true" ]]; then
        echo "  Root Token: myroot"
        if [[ -n "$VAULT_USERNAME" ]]; then
            echo "  管理員帳號: $VAULT_USERNAME"
        fi
    else
        echo "  Token: myroot"
    fi

    echo ""
    echo -e "${BLUE}常用命令:${NC}"

    if [[ "$INIT_VAULT" == "false" ]]; then
        echo "  # 初始化 Vault（啟用 userpass 認證並建立管理員）"
        echo "  ./docker-init.sh --init-vault"
        echo ""
    fi

    echo "  # 測試 SQL Server 連線"
    echo "  ./sql-permission.sh test-connection"
    echo ""
    echo "  # 建立新資料庫"
    echo "  ./create-database.sh NewDB"
    echo ""
    echo "  # 建立使用者並授權"
    echo "  ./main.sh --username app_user --databases MyAppDB --vault-paths teams/app/db-user --grant-read --grant-write"
    echo ""
    echo "  # 查看容器狀態"
    echo "  docker compose ps"
    echo ""
    echo "  # 查看日誌"
    echo "  docker compose logs -f"
    echo ""
    echo "  # 停止容器"
    echo "  docker compose down"
    echo ""
}

#############################################################################
# 主程式
#############################################################################

main() {
    # 解析命令列參數
    parse_arguments "$@"

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           Docker 環境初始化腳本（整合版）                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 如果需要初始化 Vault，先載入 .env 檔案
    if [[ "$INIT_VAULT" == "true" ]]; then
        load_env_file
    fi

    # 檢查 docker compose
    check_docker_compose

    # 啟動容器
    start_containers

    # 等待 SQL Server 就緒
    wait_for_sqlserver

    # 等待 Vault 就緒
    wait_for_vault

    # 建立資料庫（如果有指定）
    create_databases

    # 初始化 Vault（如果有指定）
    if [[ "$INIT_VAULT" == "true" ]]; then
        if ! init_vault; then
            warning "Vault 初始化失敗，但不影響 SQL Server 的使用"
        fi
    fi

    # 顯示連線資訊
    show_connection_info

    success "環境初始化完成！"
    echo ""
}

# 執行主程式
main "$@"
