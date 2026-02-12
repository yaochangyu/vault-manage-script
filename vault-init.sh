#!/bin/bash

#############################################################################
# HashiCorp Vault 初始化腳本
#
# 功能：
#   - 使用 Root Token 初始化 Vault
#   - 啟用 userpass 認證方法
#   - 從 .env 檔案讀取並建立管理員帳號
#   - 建立管理員 policy
#
# 需求：
#   - bash 4.0+
#   - curl
#   - jq
#   - .env 檔案（包含 VAULT_USERNAME 和 VAULT_PASSWORD）
#
# 作者：DevOps Team
# 版本：1.0.0
#############################################################################

set -euo pipefail

#############################################################################
# 全域變數
#############################################################################

# Vault 連線資訊
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-false}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# 要建立的管理員帳號資訊（從 .env 讀取）
VAULT_USERNAME="${VAULT_USERNAME:-}"
VAULT_PASSWORD="${VAULT_PASSWORD:-}"

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

    if [[ ! -f "$env_file" ]]; then
        warning ".env 檔案不存在，將使用環境變數或預設值"
        return 0
    fi

    info "偵測到 .env 檔案，正在載入..."

    # 使用 set -a 使所有變數自動 export
    set -a
    source "$env_file"
    set +a

    success ".env 檔案載入成功"
    return 0
}

# 檢查必要的環境變數
check_env_vars() {
    local missing_vars=()

    if [[ -z "$VAULT_ADDR" ]]; then
        missing_vars+=("VAULT_ADDR")
    fi

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
        error "缺少必要的環境變數："
        for var in "${missing_vars[@]}"; do
            echo "  - $var" >&2
        done
        echo "" >&2
        echo "請設定環境變數或建立 .env 檔案：" >&2
        echo "" >&2
        echo "方法 1：直接設定環境變數" >&2
        echo "  export VAULT_ADDR='http://localhost:8200'" >&2
        echo "  export VAULT_TOKEN='myroot'" >&2
        echo "  export VAULT_USERNAME='admin'" >&2
        echo "  export VAULT_PASSWORD='YourSecurePassword'" >&2
        echo "" >&2
        echo "方法 2：建立 .env 檔案" >&2
        echo "  cat > .env << EOF" >&2
        echo "VAULT_ADDR=http://localhost:8200" >&2
        echo "VAULT_TOKEN=myroot" >&2
        echo "VAULT_USERNAME=admin" >&2
        echo "VAULT_PASSWORD=YourSecurePassword" >&2
        echo "EOF" >&2
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

#############################################################################
# 主程式
#############################################################################

main() {
    echo ""
    echo "=============================================="
    echo "  HashiCorp Vault 初始化腳本"
    echo "=============================================="
    echo ""

    # 檢查依賴工具
    if ! check_dependencies; then
        exit 1
    fi

    # 載入 .env 檔案（如果存在）
    load_env_file

    # 檢查環境變數
    if ! check_env_vars; then
        exit 1
    fi

    # 顯示配置資訊
    echo ""
    info "配置資訊："
    echo "  Vault 位址：$VAULT_ADDR"
    echo "  管理員帳號：$VAULT_USERNAME"
    echo ""

    # 執行初始化步驟
    echo "開始初始化..."
    echo ""

    # 1. 檢查 Vault 健康狀態
    if ! check_vault_health; then
        exit 1
    fi

    # 2. 啟用 userpass 認證方法
    if ! enable_userpass; then
        exit 1
    fi

    # 3. 建立管理員 policy
    if ! create_admin_policy; then
        exit 1
    fi

    # 4. 建立管理員使用者
    if ! create_admin_user; then
        exit 1
    fi

    # 5. 測試管理員登入
    if ! test_admin_login; then
        exit 1
    fi

    # 完成
    echo ""
    echo "=============================================="
    success "Vault 初始化完成！"
    echo "=============================================="
    echo ""
    echo "現在可以使用以下方式登入："
    echo "  帳號：$VAULT_USERNAME"
    echo "  密碼：（已設定）"
    echo ""
    echo "或更新 .env 檔案並使用 vault-manage.sh："
    echo "  ./vault-manage.sh user-list"
    echo ""
}

# 執行主程式
main "$@"
