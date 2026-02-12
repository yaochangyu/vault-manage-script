#!/bin/bash

#=============================================================================
# SQL Server 工具自動移除腳本
#=============================================================================
# 功能：自動偵測 Linux 發行版並移除 SQL Server 相關工具
#   - sqlcmd (Microsoft SQL Server 命令列工具)
#   - jq (JSON 處理工具，選用)
# 支援：Ubuntu/Debian、RHEL/CentOS、Fedora
#
# 使用方式：
#   ./uninstall-tools.sh              # 移除 sqlcmd 和 jq（預設）
#   ./uninstall-tools.sh --sqlcmd-only    # 僅移除 sqlcmd
#   ./uninstall-tools.sh --jq-only    # 僅移除 jq
#=============================================================================

set -e  # 遇到錯誤立即退出

# 預設選項（預設移除所有工具）
UNINSTALL_SQLCMD=true
UNINSTALL_JQ=true

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 顯示訊息函式
show_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

show_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

show_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 檢查是否為 root 或有 sudo 權限
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo &> /dev/null; then
            show_error "此腳本需要 root 權限或 sudo，但 sudo 未安裝"
            exit 1
        fi
    fi
}

# 偵測 Linux 發行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
        VERSION=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
    else
        show_error "無法偵測 Linux 發行版"
        exit 1
    fi

    show_info "偵測到的系統: $DISTRO $VERSION"
}

# 顯示使用說明
show_usage() {
    cat << EOF
SQL Server 工具自動移除腳本

使用方式:
  $0 [選項]

選項:
  (無選項)          移除所有工具：sqlcmd + jq（預設）
  --sqlcmd-only     僅移除 sqlcmd
  --jq-only         僅移除 jq
  --help, -h        顯示此說明

範例:
  $0                # 移除所有工具（sqlcmd + jq）
  $0 --sqlcmd-only  # 僅移除 sqlcmd
  $0 --jq-only      # 僅移除 jq

支援的系統:
  - Ubuntu / Debian
  - RHEL / CentOS / Rocky Linux / AlmaLinux
  - Fedora
EOF
}

# 移除 sqlcmd (Ubuntu/Debian)
uninstall_ubuntu_debian() {
    if [ "$UNINSTALL_SQLCMD" = true ]; then
        show_info "開始在 Ubuntu/Debian 上移除 sqlcmd..."

        # 移除 mssql-tools18 和 mssql-tools
        show_info "移除 mssql-tools..."
        sudo apt-get purge -y mssql-tools18 mssql-tools unixodbc-dev
        sudo apt-get autoremove -y

        # 移除 Microsoft 儲存庫設定
        show_info "移除 Microsoft 儲存庫設定..."
        sudo rm -f /etc/apt/sources.list.d/mssql-release.list
        sudo rm -f /usr/share/keyrings/microsoft-prod.gpg
        sudo apt-get update -qq

        show_success "sqlcmd 相關套件和儲存庫已移除"
    fi

    # 移除 jq
    if [ "$UNINSTALL_JQ" = true ]; then
        show_info "移除 jq (JSON 處理工具)..."
        sudo apt-get purge -y jq
        sudo apt-get autoremove -y
        show_success "jq 已移除"
    fi
}

# 移除 sqlcmd (RHEL/CentOS/Fedora)
uninstall_rhel_centos() {
    if [ "$UNINSTALL_SQLCMD" = true ]; then
        show_info "開始在 RHEL/CentOS/Fedora 上移除 sqlcmd..."

        # 移除 mssql-tools
        show_info "移除 mssql-tools..."
        sudo yum remove -y mssql-tools unixODBC-devel

        # 移除 Microsoft 儲存庫設定
        show_info "移除 Microsoft 儲存庫設定..."
        sudo rm -f /etc/yum.repos.d/mssql-release.repo
        sudo yum clean all

        show_success "sqlcmd 相關套件和儲存庫已移除"
    fi

    # 移除 jq
    if [ "$UNINSTALL_JQ" = true ]; then
        show_info "移除 jq (JSON 處理工具)..."
        sudo yum remove -y jq
        show_success "jq 已移除"
    fi
}

# 移除 PATH 設定
remove_path() {
    show_info "移除 PATH 環境變數設定..."

    local shell_rc_files=("$HOME/.bashrc" "$HOME/.zshrc")
    local path_removed=false

    for shell_rc in "${shell_rc_files[@]}"; do
        if [ -f "$shell_rc" ]; then
            if grep -q "export PATH=.*mssql-tools" "$shell_rc" 2>/dev/null; then
                show_info "從 $shell_rc 移除 sqlcmd PATH 設定..."
                # 使用 sed 移除包含 mssql-tools 的 PATH 設定行，以及可能相關的註解行
                sed -i '/# Add sqlcmd to PATH/{N;d;};/export PATH=.*mssql-tools/d' "$shell_rc"
                path_removed=true
            fi
        fi
    done

    if [ "$path_removed" = true ]; then
        show_success "已從 shell 設定檔移除 sqlcmd PATH"
        show_info "請重新載入 shell 或執行以下命令以套用 PATH 變更："
        echo "  source ~/.bashrc  (如果使用 bash)"
        echo "  source ~/.zshrc   (如果使用 zsh)"
    else
        show_info "未在 shell 設定檔中找到 sqlcmd PATH 設定，無需移除"
    fi
}

# 主程式
main() {
    # 解析命令列參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sqlcmd-only)
                UNINSTALL_SQLCMD=true
                UNINSTALL_JQ=false
                shift
                ;;
            --jq-only)
                UNINSTALL_SQLCMD=false
                UNINSTALL_JQ=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                show_error "未知的選項: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done

    echo "========================================"
    echo "  SQL Server 工具自動移除腳本"
    echo "========================================"
    echo ""

    if [ "$UNINSTALL_SQLCMD" = true ] && [ "$UNINSTALL_JQ" = true ]; then
        show_info "將移除: sqlcmd + jq"
    elif [ "$UNINSTALL_SQLCMD" = true ]; then
        show_info "將移除: sqlcmd"
    elif [ "$UNINSTALL_JQ" = true ]; then
        show_info "將移除: jq"
    fi

    echo ""

    # 檢查權限
    check_sudo

    # 偵測系統
    detect_distro

    # 根據發行版移除
    case "$DISTRO" in
        ubuntu|debian)
            uninstall_ubuntu_debian
            ;;
        rhel|centos|rocky|almalinux|fedora)
            uninstall_rhel_centos
            ;;
        *)
            show_error "不支援的 Linux 發行版: $DISTRO"
            echo ""
            echo "目前支援的發行版："
            echo "  - Ubuntu / Debian"
            echo "  - RHEL / CentOS / Rocky Linux / AlmaLinux"
            echo "  - Fedora"
            exit 1
            ;;
    esac

    # 移除 PATH
    remove_path

    show_success "移除程序完成！"
    echo ""
}

# 執行主程式
main "$@"
