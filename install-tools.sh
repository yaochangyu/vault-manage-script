#!/bin/bash

#=============================================================================
# SQL Server 工具自動安裝腳本
#=============================================================================
# 功能：自動偵測 Linux 發行版並安裝 SQL Server 相關工具
#   - sqlcmd (Microsoft SQL Server 命令列工具)
#   - jq (JSON 處理工具，選用)
# 支援：Ubuntu/Debian、RHEL/CentOS、Fedora
#
# 使用方式：
#   ./install-sqlcmd.sh              # 僅安裝 sqlcmd
#   ./install-sqlcmd.sh --with-jq    # 安裝 sqlcmd 和 jq
#   ./install-sqlcmd.sh --jq-only    # 僅安裝 jq
#=============================================================================

set -e  # 遇到錯誤立即退出

# 預設選項（預設安裝所有工具）
INSTALL_SQLCMD=true
INSTALL_JQ=true

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

# 安裝 sqlcmd (Ubuntu/Debian)
install_ubuntu_debian() {
    if [ "$INSTALL_SQLCMD" = true ]; then
        show_info "開始在 Ubuntu/Debian 上安裝 sqlcmd..."

        # 1. 匯入 Microsoft GPG 金鑰
        show_info "匯入 Microsoft GPG 金鑰..."
        curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc > /dev/null

        # 2. 註冊 Microsoft Ubuntu 儲存庫
        show_info "註冊 Microsoft Ubuntu 儲存庫..."

        # 偵測 Ubuntu 版本
        if [ "$DISTRO" = "ubuntu" ]; then
            UBUNTU_VERSION=$(lsb_release -rs)
            curl -sSL https://packages.microsoft.com/config/ubuntu/${UBUNTU_VERSION}/prod.list | \
                sudo tee /etc/apt/sources.list.d/mssql-release.list > /dev/null
        elif [ "$DISTRO" = "debian" ]; then
            # Debian
            DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
            curl -sSL https://packages.microsoft.com/config/debian/${DEBIAN_VERSION}/prod.list | \
                sudo tee /etc/apt/sources.list.d/mssql-release.list > /dev/null
        fi

        # 3. 更新套件清單
        show_info "更新套件清單..."
        sudo apt-get update -qq

        # 4. 安裝 mssql-tools（包含 sqlcmd）
        show_info "安裝 mssql-tools 和 unixodbc-dev..."
        sudo ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev

        show_success "mssql-tools 安裝完成"
    fi

    # 安裝 jq
    if [ "$INSTALL_JQ" = true ]; then
        show_info "安裝 jq (JSON 處理工具)..."
        sudo apt-get install -y jq
        show_success "jq 安裝完成"
    fi
}

# 安裝 sqlcmd (RHEL/CentOS/Fedora)
install_rhel_centos() {
    if [ "$INSTALL_SQLCMD" = true ]; then
        show_info "開始在 RHEL/CentOS/Fedora 上安裝 sqlcmd..."

        # 1. 註冊 Microsoft Red Hat 儲存庫
        show_info "註冊 Microsoft Red Hat 儲存庫..."

        if [ "$DISTRO" = "fedora" ]; then
            sudo curl -sSL -o /etc/yum.repos.d/mssql-release.repo \
                https://packages.microsoft.com/config/rhel/8/prod.repo
        else
            # RHEL/CentOS
            local rhel_version=${VERSION%%.*}  # 取主版本號
            sudo curl -sSL -o /etc/yum.repos.d/mssql-release.repo \
                https://packages.microsoft.com/config/rhel/${rhel_version}/prod.repo
        fi

        # 2. 安裝 mssql-tools
        show_info "安裝 mssql-tools 和 unixODBC-devel..."
        sudo ACCEPT_EULA=Y yum install -y mssql-tools unixODBC-devel

        show_success "mssql-tools 安裝完成"
    fi

    # 安裝 jq
    if [ "$INSTALL_JQ" = true ]; then
        show_info "安裝 jq (JSON 處理工具)..."
        sudo yum install -y jq
        show_success "jq 安裝完成"
    fi
}

# 設定 PATH
setup_path() {
    show_info "設定 PATH 環境變數..."

    local shell_rc=""

    # 偵測使用的 shell
    if [ -n "$BASH_VERSION" ]; then
        shell_rc="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.profile"
    fi

    # 檢查 PATH 是否已經包含 sqlcmd
    if ! grep -q "/opt/mssql-tools/bin" "$shell_rc" 2>/dev/null; then
        echo '' >> "$shell_rc"
        echo '# Add sqlcmd to PATH' >> "$shell_rc"
        echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> "$shell_rc"
        show_success "已將 sqlcmd 加入 PATH（檔案: $shell_rc）"
    else
        show_info "PATH 已包含 sqlcmd"
    fi

    # 立即套用到當前 session
    export PATH="$PATH:/opt/mssql-tools/bin"
}

# 驗證安裝
verify_installation() {
    show_info "驗證安裝..."
    local success=true

    echo ""

    # 驗證 sqlcmd
    if [ "$INSTALL_SQLCMD" = true ]; then
        if command -v sqlcmd &> /dev/null; then
            local version=$(sqlcmd -? 2>&1 | head -n 1)
            show_success "sqlcmd 安裝成功！"
            echo "  版本: $version"
        else
            show_error "sqlcmd 安裝失敗或未正確加入 PATH"
            success=false
        fi
    fi

    # 驗證 jq
    if [ "$INSTALL_JQ" = true ]; then
        if command -v jq &> /dev/null; then
            local jq_version=$(jq --version 2>&1)
            show_success "jq 安裝成功！"
            echo "  版本: $jq_version"
        else
            show_error "jq 安裝失敗"
            success=false
        fi
    fi

    echo ""

    if [ "$success" = true ]; then
        if [ "$INSTALL_SQLCMD" = true ]; then
            echo "使用方式:"
            echo "  sqlcmd -S <server> -U <username> -P <password>"
            echo ""
            show_info "請重新載入 shell 或執行以下命令以套用 PATH 變更："
            echo "  source ~/.bashrc  (如果使用 bash)"
            echo "  source ~/.zshrc   (如果使用 zsh)"
        fi
        return 0
    else
        return 1
    fi
}

# 顯示使用說明
show_usage() {
    cat << EOF
SQL Server 工具自動安裝腳本

使用方式:
  $0 [選項]

選項:
  (無選項)          安裝所有工具：sqlcmd + jq（預設）
  --sqlcmd-only     僅安裝 sqlcmd
  --jq-only         僅安裝 jq
  --help, -h        顯示此說明

範例:
  $0                # 安裝所有工具（sqlcmd + jq）
  $0 --sqlcmd-only  # 僅安裝 sqlcmd
  $0 --jq-only      # 僅安裝 jq

支援的系統:
  - Ubuntu / Debian
  - RHEL / CentOS / Rocky Linux / AlmaLinux
  - Fedora
EOF
}

# 主程式
main() {
    # 解析命令列參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sqlcmd-only)
                INSTALL_SQLCMD=true
                INSTALL_JQ=false
                shift
                ;;
            --jq-only)
                INSTALL_SQLCMD=false
                INSTALL_JQ=true
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
    echo "  SQL Server 工具自動安裝腳本"
    echo "========================================"
    echo ""

    if [ "$INSTALL_SQLCMD" = true ] && [ "$INSTALL_JQ" = true ]; then
        show_info "將安裝: sqlcmd + jq"
    elif [ "$INSTALL_SQLCMD" = true ]; then
        show_info "將安裝: sqlcmd"
    elif [ "$INSTALL_JQ" = true ]; then
        show_info "將安裝: jq"
    fi

    echo ""

    # 檢查權限
    check_sudo

    # 偵測系統
    detect_distro

    # 根據發行版安裝
    case "$DISTRO" in
        ubuntu|debian)
            install_ubuntu_debian
            ;;
        rhel|centos|rocky|almalinux)
            install_rhel_centos
            ;;
        fedora)
            install_rhel_centos
            ;;
        *)
            show_error "不支援的 Linux 發行版: $DISTRO"
            echo ""
            echo "支援的發行版："
            echo "  - Ubuntu / Debian"
            echo "  - RHEL / CentOS / Rocky Linux / AlmaLinux"
            echo "  - Fedora"
            echo ""
            echo "請手動安裝 mssql-tools:"
            echo "https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools"
            exit 1
            ;;
    esac

    # 設定 PATH
    setup_path

    # 驗證安裝
    echo ""
    verify_installation
}

# 執行主程式
main "$@"
