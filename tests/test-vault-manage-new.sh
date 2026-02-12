#!/bin/bash

#############################################################################
# vault-manage.sh 測試腳本（新格式）
#
# 目的：驗證重構後的新命令格式
# 測試範圍：核心命令的基本功能
#############################################################################

set -euo pipefail

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 測試計數器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 腳本路徑
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_SCRIPT="${SCRIPT_DIR}/vault-manage.sh"

# 測試資料
TEST_MOUNT="secret"
TEST_PATH="test-new-format"

#############################################################################
# 工具函式
#############################################################################

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1" >&2
}

# 執行測試
run_test() {
    local test_name="$1"
    shift
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    info "測試: $test_name"
    
    if "$@" &> /dev/null; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        success "$test_name"
        return 0
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        error "$test_name"
        return 1
    fi
}

# 檢查 Vault 是否可用
check_vault_available() {
    # 載入環境變數
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    else
        error ".env 檔案不存在"
        return 1
    fi
    
    # 檢查 Vault 連線
    if ! curl -s "${VAULT_ADDR}/v1/sys/health" &> /dev/null; then
        error "無法連接到 Vault (${VAULT_ADDR})"
        return 1
    fi
    
    return 0
}

#############################################################################
# 測試函式
#############################################################################

# 1. Secret CRUD (新格式：secret <subcommand>)
test_secret_create() {
    "${VAULT_SCRIPT}" secret create "${TEST_MOUNT}" "${TEST_PATH}/s1" key1=value1 key2=value2
}

test_secret_get() {
    "${VAULT_SCRIPT}" secret get "${TEST_MOUNT}" "${TEST_PATH}/s1" --format json
}

test_secret_update() {
    "${VAULT_SCRIPT}" secret update "${TEST_MOUNT}" "${TEST_PATH}/s1" key3=value3
}

test_secret_list() {
    "${VAULT_SCRIPT}" secret list "${TEST_MOUNT}" "${TEST_PATH}"
}

test_secret_delete() {
    echo "y" | "${VAULT_SCRIPT}" secret delete "${TEST_MOUNT}" "${TEST_PATH}/s1"
}

# 2. User 管理 (新格式：user <subcommand>)
test_user_create() {
    "${VAULT_SCRIPT}" user create "testuser-new" "TestPass123!@#"
}

test_user_list() {
    "${VAULT_SCRIPT}" user list
}

test_user_delete() {
    echo "y" | "${VAULT_SCRIPT}" user delete "testuser-new"
}

# 3. Policy 管理 (新格式：policy <subcommand>)
test_policy_create() {
    "${VAULT_SCRIPT}" policy create "secret/testpath-new"
}

test_policy_list() {
    "${VAULT_SCRIPT}" policy list
}

test_policy_get() {
    "${VAULT_SCRIPT}" policy get "path-secret-testpath-new"
}

#############################################################################
# 清理函式
#############################################################################

cleanup() {
    info "清理測試資料..."
    echo "y" | "${VAULT_SCRIPT}" user delete "testuser-new" &> /dev/null || true
    success "清理完成"
}

#############################################################################
# 主測試流程
#############################################################################

main() {
    echo ""
    echo "======================================"
    echo "  vault-manage.sh 測試（新格式）"
    echo "======================================"
    echo ""
    
    # 檢查環境
    info "檢查測試環境..."
    if ! check_vault_available; then
        error "測試環境檢查失敗"
        exit 1
    fi
    success "測試環境正常"
    echo ""
    
    # Secret 操作測試 (新格式)
    echo "--- Secret 操作測試 (新格式) ---"
    run_test "secret create" test_secret_create
    run_test "secret get" test_secret_get
    run_test "secret update" test_secret_update
    run_test "secret list" test_secret_list
    run_test "secret delete" test_secret_delete
    echo ""
    
    # User 管理測試 (新格式)
    echo "--- User 管理測試 (新格式) ---"
    run_test "user create" test_user_create
    run_test "user list" test_user_list
    run_test "user delete" test_user_delete
    echo ""
    
    # Policy 管理測試 (新格式)
    echo "--- Policy 管理測試 (新格式) ---"
    run_test "policy create" test_policy_create
    run_test "policy list" test_policy_list
    run_test "policy get" test_policy_get
    echo ""
    
    # 測試結果統計
    echo "======================================"
    echo "  測試結果"
    echo "======================================"
    echo "總測試數: $TOTAL_TESTS"
    echo -e "${GREEN}通過: $PASSED_TESTS${NC}"
    echo -e "${RED}失敗: $FAILED_TESTS${NC}"
    echo ""
    
    # 返回狀態碼
    if [[ $FAILED_TESTS -eq 0 ]]; then
        success "所有測試通過！"
        exit 0
    else
        error "有 $FAILED_TESTS 個測試失敗"
        exit 1
    fi
}

# 設定錯誤處理
trap cleanup EXIT

# 執行主程式
main "$@"
