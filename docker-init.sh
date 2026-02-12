#!/bin/bash

#############################################################################
# Docker 環境初始化腳本
#
# 功能：
#   1. 啟動 SQL Server 和 Vault 容器
#   2. 等待服務就緒
#   3. 建立指定的資料庫
#   4. 驗證連線
#
# 使用方式：
#   ./docker-init.sh                    # 僅啟動容器
#   ./docker-init.sh MyAppDB            # 啟動容器並建立資料庫
#   ./docker-init.sh MyAppDB TestDB     # 啟動容器並建立多個資料庫
#############################################################################

set -euo pipefail

# 腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    local databases=("$@")

    if [ ${#databases[@]} -eq 0 ]; then
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

    for db in "${databases[@]}"; do
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
    echo "  Token: myroot"
    echo ""
    echo -e "${BLUE}常用命令:${NC}"
    echo "  # 測試 SQL Server 連線"
    echo "  ./sql-permission.sh test-connection"
    echo ""
    echo "  # 建立新資料庫"
    echo "  ./create-database.sh NewDB"
    echo ""
    echo "  # 建立使用者並授權"
    echo "  ./provision-db-user.sh --username app_user --databases MyAppDB --vault-paths teams/app/db-user --grant-read --grant-write"
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

# 主程式
main() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           Docker 環境初始化腳本                                 ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 檢查 docker compose
    check_docker_compose

    # 啟動容器
    start_containers

    # 等待 SQL Server 就緒
    wait_for_sqlserver

    # 等待 Vault 就緒
    wait_for_vault

    # 建立資料庫（如果有指定）
    if [ $# -gt 0 ]; then
        create_databases "$@"
    fi

    # 顯示連線資訊
    show_connection_info

    success "環境初始化完成！"
    echo ""
}

# 執行主程式
main "$@"
