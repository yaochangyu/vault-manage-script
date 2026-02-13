#!/bin/bash

#############################################################################
# SQL Server 使用者自動化佈建工具
#
# 功能：
#   - 自動產生強密碼
#   - 使用 sql-permission.sh 建立 SQL Server 使用者並授予權限
#   - 使用 vault-manage.sh 將帳號密碼存入 Vault 指定路徑
#
# 需求：
#   - bash 4.0+
#   - openssl (用於產生密碼)
#   - sql-permission.sh
#   - vault-manage.sh
#
# 作者：DevOps Team
# 版本：1.0.0
#############################################################################

set -euo pipefail

#############################################################################
# 全域變數
#############################################################################

# 腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 相依腳本路徑
SQL_PERMISSION_SCRIPT="${SCRIPT_DIR}/sql-permission.sh"
VAULT_MANAGE_SCRIPT="${SCRIPT_DIR}/vault-manage.sh"

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# 顯示使用說明
show_usage() {
    cat << EOF
SQL Server 使用者自動化佈建工具

使用方法：
  $0 [選項]

必要選項：
  --username <username>           使用者帳號（單一帳號）
  --databases <db1,db2,...>       資料庫清單（逗號分隔）
  --vault-paths <path1,path2,...> Vault Secret 路徑清單（逗號分隔）

權限選項：
  --grant-read                    授予讀取權限 (db_datareader)
  --grant-write                   授予寫入權限 (db_datawriter)
  --grant-execute                 授予執行預存程序權限 (EXECUTE)

密碼選項：
  --password <password>           手動指定密碼（若不指定則自動產生）
  --password-length <length>      密碼長度（預設：32）

其他選項：
  --vault-mount <mount>           Vault mount point（預設：secrets）
  --dry-run                       預覽操作但不實際執行
  -h, --help                      顯示此說明

範例：

  # 基本使用：建立使用者並授予讀寫權限
  $0 \\
    --username app_user \\
    --databases "MyAppDB,TestDB" \\
    --vault-paths "teams/job-finder/qa/db-user,teams/job-finder/dev/db-user" \\
    --grant-read \\
    --grant-write

  # 建立唯讀使用者
  $0 \\
    --username report_user \\
    --databases "MyAppDB" \\
    --vault-paths "teams/reports/db-user" \\
    --grant-read

  # 使用自訂密碼
  $0 \\
    --username api_user \\
    --databases "MyAppDB" \\
    --vault-paths "teams/api/db-user" \\
    --password "MyStrongP@ssw0rd!" \\
    --grant-read \\
    --grant-write \\
    --grant-execute

  # 預覽模式（不實際執行）
  $0 \\
    --username test_user \\
    --databases "TestDB" \\
    --vault-paths "teams/test/db-user" \\
    --grant-read \\
    --dry-run

工作流程：
  1. 產生強密碼（或使用指定密碼）
  2. 呼叫 sql-permission.sh 建立 SQL Server Login/User 並授予權限
  3. 呼叫 vault-manage.sh 將帳號密碼寫入所有指定的 Vault 路徑

環境變數：
  SQL Server 連線資訊：
    SQL_SERVER, SQL_PORT, ADMIN_USER, ADMIN_PASSWORD

  Vault 連線資訊：
    VAULT_ADDR, VAULT_USERNAME, VAULT_PASSWORD, VAULT_SKIP_VERIFY

EOF
}

# 檢查必要的腳本檔案
check_dependencies() {
    local missing_deps=()

    # 檢查必要命令
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
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
        return 1
    fi

    # 檢查腳本檔案
    if [[ ! -x "$SQL_PERMISSION_SCRIPT" ]]; then
        error "找不到或無法執行 sql-permission.sh: $SQL_PERMISSION_SCRIPT"
        return 1
    fi

    if [[ ! -x "$VAULT_MANAGE_SCRIPT" ]]; then
        error "找不到或無法執行 vault-manage.sh: $VAULT_MANAGE_SCRIPT"
        return 1
    fi

    return 0
}

# 產生強密碼
generate_password() {
    local length="${1:-32}"

    # 使用 openssl 產生隨機密碼
    # 包含大小寫字母、數字、特殊符號
    local password
    password=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-"$length")

    # 確保包含至少一個大寫、一個小寫、一個數字、一個特殊符號
    # 如果不符合，重新產生
    if [[ ! "$password" =~ [A-Z] ]] || [[ ! "$password" =~ [a-z] ]] || [[ ! "$password" =~ [0-9] ]]; then
        # 重新產生
        password=$(generate_password "$length")
    fi

    echo "$password"
}

#############################################################################
# 主程式
#############################################################################

main() {
    # 檢查是否顯示說明
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi

    # 檢查依賴
    if ! check_dependencies; then
        exit 1
    fi

    # 解析參數
    local username=""
    local databases=""
    local vault_paths=""
    local password=""
    local password_length=32
    local grant_read=false
    local grant_write=false
    local grant_execute=false
    local vault_mount="secrets"
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --username)
                username="$2"
                shift 2
                ;;
            --databases)
                databases="$2"
                shift 2
                ;;
            --vault-paths)
                vault_paths="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --password-length)
                password_length="$2"
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
            --vault-mount)
                vault_mount="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "未知的選項: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done

    # 驗證必要參數
    local validation_failed=false

    if [[ -z "$username" ]]; then
        error "請使用 --username 指定使用者帳號"
        validation_failed=true
    fi

    if [[ -z "$databases" ]]; then
        error "請使用 --databases 指定資料庫清單"
        validation_failed=true
    fi

    if [[ -z "$vault_paths" ]]; then
        error "請使用 --vault-paths 指定 Vault Secret 路徑清單"
        validation_failed=true
    fi

    if $validation_failed; then
        echo ""
        echo "使用 $0 --help 查看詳細說明" >&2
        exit 1
    fi

    # 轉換資料庫和路徑為陣列
    IFS=',' read -ra db_array <<< "$databases"
    IFS=',' read -ra path_array <<< "$vault_paths"

    # 步驟 0: 顯示操作摘要
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       SQL Server 使用者自動化佈建                              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}使用者帳號：${NC}$username"
    echo -e "${BLUE}資料庫清單：${NC}${db_array[*]}"
    echo -e "${BLUE}Vault 路徑：${NC}"
    for path in "${path_array[@]}"; do
        echo "  - $vault_mount/$path"
    done
    echo -e "${BLUE}權限設定：${NC}"
    [[ "$grant_read" == true ]] && echo "  ✓ 讀取 (db_datareader)"
    [[ "$grant_write" == true ]] && echo "  ✓ 寫入 (db_datawriter)"
    [[ "$grant_execute" == true ]] && echo "  ✓ 執行 (EXECUTE)"
    [[ "$grant_read" == false && "$grant_write" == false && "$grant_execute" == false ]] && echo "  - 無額外權限"

    if $dry_run; then
        echo -e "${YELLOW}模式：預覽模式（不實際執行）${NC}"
    fi
    echo ""

    # 步驟 1: 產生或使用指定的密碼
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}步驟 1/3: 準備密碼${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ -z "$password" ]]; then
        info "正在產生隨機密碼（長度：$password_length）..."
        password=$(generate_password "$password_length")
        success "密碼產生完成"

        if $dry_run; then
            echo "  產生的密碼: $password"
        else
            echo "  產生的密碼: ********（已隱藏）"
        fi
    else
        info "使用指定的密碼"
        echo "  密碼: ********（已隱藏）"
    fi
    echo ""

    # 步驟 2: 使用 sql-permission.sh 建立使用者並授予權限
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}步驟 2/3: 建立 SQL Server 使用者並授予權限${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # 建立命令參數
    local sql_cmd_args=(
        "setup-user"
        "--users" "$username"
        "--databases" "$databases"
        "--password" "$password"
    )

    [[ "$grant_read" == true ]] && sql_cmd_args+=("--grant-read")
    [[ "$grant_write" == true ]] && sql_cmd_args+=("--grant-write")
    [[ "$grant_execute" == true ]] && sql_cmd_args+=("--grant-execute")

    if $dry_run; then
        info "預覽模式：將執行以下命令"
        echo "  $SQL_PERMISSION_SCRIPT ${sql_cmd_args[*]}"
        echo ""
    else
        info "正在執行 sql-permission.sh..."

        if "$SQL_PERMISSION_SCRIPT" "${sql_cmd_args[@]}"; then
            success "SQL Server 使用者建立完成"
        else
            error "SQL Server 使用者建立失敗"
            exit 1
        fi
        echo ""
    fi

    # 步驟 3: 使用 vault-manage.sh 將帳號密碼存入 Vault
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}步驟 3/3: 將帳號密碼存入 Vault${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local vault_success_count=0
    local vault_fail_count=0

    for path in "${path_array[@]}"; do
        path=$(echo "$path" | xargs)  # 去除空白

        if [[ -z "$path" ]]; then
            continue
        fi

        info "正在寫入 Vault: $vault_mount/$path"

        if $dry_run; then
            echo "  預覽模式：將執行以下命令"
            echo "  $VAULT_MANAGE_SCRIPT create $vault_mount $path username=$username password=********"
            ((vault_success_count++))
        else
            # 先檢查 secret 是否存在
            if "$VAULT_MANAGE_SCRIPT" get "$vault_mount" "$path" &>/dev/null; then
                # Secret 存在，使用 update
                if "$VAULT_MANAGE_SCRIPT" update "$vault_mount" "$path" "username=$username" "password=$password"; then
                    success "已更新 Vault Secret: $vault_mount/$path"
                    ((vault_success_count++))
                else
                    error "更新 Vault Secret 失敗: $vault_mount/$path"
                    ((vault_fail_count++))
                fi
            else
                # Secret 不存在，使用 create
                if "$VAULT_MANAGE_SCRIPT" create "$vault_mount" "$path" "username=$username" "password=$password"; then
                    success "已建立 Vault Secret: $vault_mount/$path"
                    ((vault_success_count++))
                else
                    error "建立 Vault Secret 失敗: $vault_mount/$path"
                    ((vault_fail_count++))
                fi
            fi
        fi
        echo ""
    done

    # 最終摘要
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                       執行摘要                                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}使用者帳號：${NC}$username"
    echo -e "${BLUE}資料庫數量：${NC}${#db_array[@]}"
    echo -e "${BLUE}Vault Secrets 成功：${NC}$vault_success_count"

    if [[ $vault_fail_count -gt 0 ]]; then
        echo -e "${BLUE}Vault Secrets 失敗：${NC}${RED}$vault_fail_count${NC}"
    fi

    echo ""

    if $dry_run; then
        warning "這是預覽模式，未實際執行任何操作"
    else
        if [[ $vault_fail_count -eq 0 ]]; then
            success "所有操作成功完成！"
        else
            warning "部分操作失敗，請檢查上述錯誤訊息"
            exit 1
        fi
    fi

    echo ""
}

# 執行主程式
main "$@"
