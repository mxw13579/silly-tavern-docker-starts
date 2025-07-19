#!/bin/bash
# SillyTavern Toolkit 安装程序 (集成软件源切换功能)

# --- 安全设置 ---
set -e

# --- 脚本常量 ---
REPO_USER="mxw13579"
REPO_NAME="silly-tavern-docker-starts"
REPO_PATH="sillytavern-toolkit"
BRANCH="main"
TOOLKIT_DIR="$HOME/sillytavern-toolkit"

# --- 颜色和消息函数 ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
msg_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
msg_ok() { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
msg_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $1"; }
msg_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1"; exit 1; }

# --- 操作系统检测 (集成自 common.sh) ---
detect_os() {
    msg_info "正在检测操作系统..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION_ID=$VERSION_ID
        OS_VERSION_CODENAME=$VERSION_CODENAME
    elif [ -f /etc/redhat-release ]; then
        OS=$(sed 's/ release.*//' /etc/redhat-release | tr '[:upper:]' '[:lower:]' | tr -d ' ')
        OS_VERSION_ID=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    else
        msg_error "无法确定操作系统类型，无法继续。"
    fi
    msg_ok "检测到操作系统: $OS $OS_VERSION_ID"
}

# --- 切换到阿里云源 (集成自 sources.sh) ---
switch_to_aliyun_source() {
    msg_info "准备切换到 [阿里云] 软件源..."

    # 确保有sudo权限
    if ! sudo -v; then msg_error "需要sudo权限来修改软件源。"; return 1; fi

    case $OS in
        debian|ubuntu)
            msg_info "正在备份当前APT源..."
            sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%Y%m%d_%H%M%S)

            local mirror_url="mirrors.aliyun.com"
            local proto="https"

            if [ "$OS" = "debian" ]; then
                sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb ${proto}://${mirror_url}/debian/ ${OS_VERSION_CODENAME} main contrib non-free
deb ${proto}://${mirror_url}/debian/ ${OS_VERSION_CODENAME}-updates main contrib non-free
deb ${proto}://${mirror_url}/debian-security/ ${OS_VERSION_CODENAME}-security main contrib non-free
EOF
            else # ubuntu
                sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb ${proto}://${mirror_url}/ubuntu/ ${OS_VERSION_CODENAME} main restricted universe multiverse
deb ${proto}://${mirror_url}/ubuntu/ ${OS_VERSION_CODENAME}-updates main restricted universe multiverse
deb ${proto}://${mirror_url}/ubuntu/ ${OS_VERSION_CODENAME}-backports main restricted universe multiverse
deb ${proto}://${mirror_url}/ubuntu/ ${OS_VERSION_CODENAME}-security main restricted universe multiverse
EOF
            fi
            msg_info "正在刷新APT缓存..."
            sudo apt-get update
            ;;
        centos|rhel)
            msg_info "正在备份当前YUM源..."
            sudo mkdir -p /etc/yum.repos.d/bak_install
            sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak_install/

            local repo_url="https://mirrors.aliyun.com/repo/Centos-${OS_VERSION_ID}.repo"
            if [ "$OS" = "rhel" ]; then # RHEL源不同
                 repo_url="https://mirrors.aliyun.com/repo/epel-${OS_VERSION_ID}.repo"
                 msg_warn "对于RHEL，仅切换EPEL源为阿里云，系统基础源可能需要您手动订阅。"
            fi

            sudo curl -o /etc/yum.repos.d/aliyun.repo ${repo_url}
            msg_info "正在刷新YUM缓存..."
            sudo yum clean all && sudo yum makecache
            ;;
        *)
            msg_warn "当前操作系统 $OS 的自动切换源功能暂不支持。将跳过此步骤。"
            return
            ;;
    esac
    msg_ok "已成功切换到 [阿里云] 源！"
}

# --- 安装依赖函数 ---
install_dependency() {
    local pkg=$1
    if command -v $pkg &> /dev/null; then
        return
    fi
    msg_info "==> 检测到 '$pkg' 未安装，将为您自动安装..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y $pkg
    elif command -v yum &> /dev/null; then
        sudo yum install -y $pkg
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y $pkg
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm $pkg
    else
        msg_error "无法确定您的包管理器。请手动安装 '$pkg' 后再运行此脚本。"
    fi
     msg_ok "==> '$pkg' 安装成功！"
}

# --- 主要逻辑开始 ---
msg_info "================================================="
msg_info "== 欢迎使用 SillyTavern 工具箱 一体化安装程序 =="
msg_info "================================================="

# 步骤 1: 操作系统检测
detect_os

# 步骤 2: 地理位置检测和软件源切换
msg_info "正在检测服务器位置以优化安装过程..."
COUNTRY_CODE=$(curl -s -m 10 --retry 2 https://ipinfo.io/country) || COUNTRY_CODE=""
IS_CN=false
if [[ "$COUNTRY_CODE" == "CN" ]]; then
    msg_ok "检测到服务器位于中国 (CN)，将启用国内加速方案。"
    IS_CN=true

    echo
    msg_info "为大幅提升后续安装速度，强烈建议您切换系统软件源。"
    read -p "是否现在自动切换为 [阿里云] 的软件源? (推荐) [Y/n]: " choice
    choice=${choice:-y} # 用户直接回车则默认为 'y'
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        switch_to_aliyun_source
    else
        msg_warn "已跳过自动切换软件源。后续安装可能会很慢。"
    fi

else
    msg_info "服务器不在中国 (地区: ${COUNTRY_CODE:-未知})，将使用标准安装方法。"
fi

# 步骤 3: 根据地区选择下载方式 (cURL 或 Git)
if [ "$IS_CN" = true ]; then
    msg_info "==> 将通过 cURL 和国内代理下载工具箱文件..."
    install_dependency "curl"

    PROXY_URL="https://ghfast.top"
    BASE_URL="${PROXY_URL}/https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/${REPO_PATH}"
    FILES=(
        "st-toolkit.sh"
        "scripts/common.sh"
        "scripts/docker.sh"
        "scripts/sillytavern.sh"
        "scripts/sources.sh"
    )

    if [ -d "$TOOLKIT_DIR" ]; then
        msg_info "检测到已存在的工具箱目录，将备份为 ${TOOLKIT_DIR}.bak_$(date +%Y%m%d_%H%M%S)"
        mv "$TOOLKIT_DIR" "${TOOLKIT_DIR}.bak_$(date +%Y%m%d_%H%M%S)"
    fi

    msg_info "正在创建目录: $TOOLKIT_DIR/scripts"
    mkdir -p "$TOOLKIT_DIR/scripts"

    for file in "${FILES[@]}"; do
        msg_info "  -> 正在下载: $file"
        curl -fsSL "${BASE_URL}/${file}" -o "${TOOLKIT_DIR}/${file}"
    done

    msg_ok "==> 所有工具箱文件下载完成。"

else
    msg_info "==> 将通过 Git 克隆/更新工具箱..."
    install_dependency "git"

		# 你的仓库结构比较特殊，不能直接克隆
    REPO_GIT_URL="https://github.com/${REPO_USER}/${REPO_NAME}.git"
		temp_dir=$(mktemp -d)

    if [ -d "$TOOLKIT_DIR" ]; then
        msg_info "检测到旧目录，将完整替换为最新版..."
				rm -rf "$TOOLKIT_DIR"
    fi

    msg_info "正在从 GitHub 克隆仓库 (这可能需要一点时间)..."
    git clone --depth 1 "$REPO_GIT_URL" "$temp_dir"

    msg_info "正在整理文件结构..."
    mv "$temp_dir/$REPO_PATH" "$TOOLKIT_DIR"
    rm -rf "$temp_dir"

    msg_ok "==> 工具箱克隆完成。"
fi

# 步骤 4: 后续处理和启动
cd "$TOOLKIT_DIR"
chmod +x st-toolkit.sh scripts/*.sh

echo
msg_ok "✅ 工具箱已成功安装/更新！"
echo
echo "   即将启动主菜单..."
echo -e "   未来，您可以随时通过以下命令再次启动工具箱："
echo -e "   ${C_GREEN}cd $TOOLKIT_DIR && ./st-toolkit.sh${C_RESET}"
echo
sleep 3

# 启动主工具箱脚本
./st-toolkit.sh

exit 0
