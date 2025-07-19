#!/bin/bash
# 通用函数和环境变量

# --- 安全设置 ---
set -e

# --- 颜色定义 ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

# --- 消息函数 ---
msg_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
msg_ok() { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
msg_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
msg_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1"; }
pause_to_continue() { read -p "按 [Enter] 键返回..." -r; }

# --- 权限检查 ---
check_sudo() {
    if ! command -v sudo &> /dev/null; then
        msg_error "sudo 命令未找到。请确保已安装sudo。"
        exit 1
    fi
    if [[ $EUID -ne 0 ]]; then
        if ! sudo -v &> /dev/null; then
            msg_error "需要sudo权限。请以root用户运行或确保当前用户有sudo权限。"
            exit 1
        fi
    fi
}

# --- 常量定义 ---
export ST_PATH="/data/docker/sillytavern"
export ST_COMPOSE_FILE="${ST_PATH}/docker-compose.yaml"
export ST_CONFIG_FILE="${ST_PATH}/config/config.yaml"

# --- 自动切换软件源 (新增功能) ---
auto_switch_source() {
    # 仅在中国区且系统支持时执行
    if [ "$USE_CHINA_MIRROR" = true ] && [[ "$OS" =~ ^(debian|ubuntu|centos|rhel)$ ]]; then
        local has_mirror=false
        # 检查是否已配置了国内镜像
        if [ "$PKG_MANAGER" = "apt-get" ] && [ -f /etc/apt/sources.list ]; then
           if grep -qE "aliyun|tencent|huawei|163|tsinghua|ustc" /etc/apt/sources.list; then
             has_mirror=true
           fi
        elif [[ "$PKG_MANAGER" = "yum" || "$PKG_MANAGER" = "dnf" ]] && [ -d /etc/yum.repos.d ]; then
           if grep -qE "aliyun|tencent|huawei|163|tsinghua|ustc" /etc/yum.repos.d/*.repo 2>/dev/null; then
             has_mirror=true
           fi
        fi

        # 如果没有配置国内镜像，则自动切换
        if [ "$has_mirror" = false ]; then
            msg_warn "检测到您在中国但未使用镜像源，将自动为您切换到[阿里云]以提高速度。"
            msg_warn "此操作仅执行一次。原始源文件将备份。"
            # BASH_SOURCE[0] 获取当前脚本(common.sh)的路径，从而准确定位sources.sh
            # 使用 sudo bash -c "..." 确保子脚本也能获取到sudo权限
            sudo bash "$(dirname "${BASH_SOURCE[0]}")/sources.sh" set aliyun
            msg_ok "自动切换软件源完成。"
            echo # 换行以美化输出
        fi
    fi
}


# 5. Docker Compose命令检测
setup_docker_compose_cmd() {
    if docker compose version &> /dev/null; then
        export DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        export DOCKER_COMPOSE_CMD="docker-compose"
    else
        export DOCKER_COMPOSE_CMD="" # 表示未找到
    fi
}


# --- 环境检测 (只在common.sh被直接调用或作为其他脚本源时执行一次) ---
if [[ -z "$ENV_DETECTED" ]]; then
    export ENV_DETECTED=true

    # 1. 地理位置检测
    # msg_info "正在检测服务器位置..."
    COUNTRY_CODE=$(curl -s -m 10 --retry 2 https://ipinfo.io/country) || COUNTRY_CODE=""
    export USE_CHINA_MIRROR=false
    if [ "$COUNTRY_CODE" = "CN" ]; then
        # msg_ok "检测到服务器位于中国 (CN)，将优先使用国内镜像源。"
        export USE_CHINA_MIRROR=true
    # else
        # msg_info "服务器不在中国 (Country: ${COUNTRY_CODE:-"未知"})，将使用官方源。"
    fi

    # 2. 操作系统检测
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        export OS=$ID
        export OS_VERSION_ID=$VERSION_ID
        export OS_VERSION_CODENAME=$VERSION_CODENAME
    elif [ -f /etc/redhat-release ]; then
        export OS=$(sed 's/ release.*//' /etc/redhat-release | tr '[:upper:]' '[:lower:]' | tr -d ' ')
        export OS_VERSION_ID=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    else
        msg_error "无法确定操作系统类型。"
        exit 1
    fi

    # 3. 包管理器检测
    case $OS in
        debian|ubuntu) export PKG_MANAGER="apt-get" ;;
        centos|rhel) export PKG_MANAGER="yum" ;;
        fedora) export PKG_MANAGER="dnf" ;;
        arch) export PKG_MANAGER="pacman" ;;
        alpine) export PKG_MANAGER="apk" ;;
        *) msg_warn "未知的包管理器 for $OS." ;;
    esac

    # 4. 自动切换软件源 (新增调用)
    auto_switch_source

    setup_docker_compose_cmd
fi
