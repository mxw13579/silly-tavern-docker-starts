#!/bin/bash
# SillyTavern Toolkit 安装程序

# --- 安全设置 ---
set -e

# --- 脚本常量 ---
# GitHub仓库信息
REPO_USER="mxw13579"
REPO_NAME="silly-tavern-docker-starts"
# 注意：你的路径中有两个 'sillytavern-toolkit'，这里根据你的URL进行了调整
REPO_PATH="sillytavern-toolkit/sillytavern-toolkit"
BRANCH="main"
# 本地安装目录
TOOLKIT_DIR="$HOME/sillytavern-toolkit"

# --- 颜色和消息函数 (从common.sh中提前引入，用于美化输出) ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
msg_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
msg_ok() { echo -e "${C_GREEN}[OK]${C_RESET} $1"; }
msg_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1"; exit 1; }

# --- 安装依赖函数 ---
install_dependency() {
    local pkg=$1
    if command -v $pkg &> /dev/null; then
        return
    fi
    msg_info "检测到 '$pkg' 未安装，将为您自动安装..."
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
     msg_ok "'$pkg' 安装成功！"
}

# --- 主要逻辑开始 ---
msg_info "==> 欢迎使用 SillyTavern 工具箱安装程序 <=="

# 1. 检测所在地址判断是否为cn
msg_info "正在检测服务器位置以优化安装过程..."
# 使用短超时和重试增加稳定性，如果命令失败则COUNTRY_CODE为空
COUNTRY_CODE=$(curl -s -m 10 --retry 2 https://ipinfo.io/country) || COUNTRY_CODE=""
IS_CN=false
if [[ "$COUNTRY_CODE" == "CN" ]]; then
    msg_ok "检测到服务器位于中国 (CN)，将启用国内加速方案。"
    IS_CN=true
else
    msg_info "服务器不在中国 (地区: ${COUNTRY_CODE:-未知})，将使用标准安装方法。"
fi

# 2. 如果为cn则通过curl下载全部文件而不是通过git下载
if [ "$IS_CN" = true ]; then
    # --- 中国区 cURL 下载逻辑 ---

    # 自动切换系统软件源（可选，但强烈推荐）
    echo
    msg_info "检测到您在中国大陆，强烈建议切换系统软件源以加速后续依赖安装。"
    read -p "是否现在自动切换为 [阿里云] 的软件源? (Y/n): " choice
    choice=${choice:-y} # 默认值为y
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        # 临时下载 sources.sh 并执行，执行完即焚
        msg_info "正在执行源切换..."
        bash <(curl -fsSL https://ghproxy.com/https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/${REPO_PATH}/scripts/sources.sh) set aliyun
        msg_ok "软件源切换完成。"
    else
        msg_info "已跳过自动切换软件源。"
    fi

    msg_info "将通过 cURL 和代理下载工具箱文件..."
    install_dependency "curl"

    # 定义文件列表和代理URL
    PROXY_URL="https://ghproxy.com"
    BASE_URL="${PROXY_URL}/https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/${REPO_PATH}"
    FILES=(
        "st-toolkit.sh"
        "scripts/common.sh"
        "scripts/docker.sh"
        "scripts/sillytavern.sh"
        "scripts/sources.sh"
    )

    # 如果目录存在，先备份旧目录
    if [ -d "$TOOLKIT_DIR" ]; then
        msg_info "检测到已存在的工具箱目录，将备份为 ${TOOLKIT_DIR}.bak"
        mv "$TOOLKIT_DIR" "${TOOLKIT_DIR}.bak_$(date +%Y%m%d_%H%M%S)"
    fi

    msg_info "正在创建目录: $TOOLKIT_DIR"
    mkdir -p "$TOOLKIT_DIR/scripts"

    for file in "${FILES[@]}"; do
        msg_info "  -> 正在下载: $file"
        sudo curl -fsSL "${BASE_URL}/${file}" -o "${TOOLKIT_DIR}/${file}"
    done

    msg_ok "所有工具箱文件下载完成。"

else
    # --- 非中国区 Git 下载逻辑 ---
    msg_info "将通过 Git 克隆/更新工具箱..."
    install_dependency "git"

    REPO_GIT_URL="https://github.com/${REPO_USER}/${REPO_NAME}.git"

    if [ -d "$TOOLKIT_DIR" ]; then
        msg_info "检测到已存在的工具箱目录，将尝试从 GitHub 更新..."
        cd "$TOOLKIT_DIR"
        # 直接拉取你的子目录部分，这里git clone更简单
        cd "$HOME" && rm -rf "$TOOLKIT_DIR"
        msg_info "为保证结构正确，已删除旧目录，将重新克隆。"
        # 注意：这里不能用sparse checkout，因为你的仓库结构太深了
        # 最简单的办法是克隆整个仓库，然后把需要的子目录移出来
        temp_dir=$(mktemp -d)
        git clone "$REPO_GIT_URL" "$temp_dir"
        mv "$temp_dir/$REPO_PATH" "$TOOLKIT_DIR"
        rm -rf "$temp_dir"

    else
        msg_info "正在从 GitHub 克隆工具箱到: $TOOLKIT_DIR"
        temp_dir=$(mktemp -d)
        git clone "$REPO_GIT_URL" "$temp_dir"
        mv "$temp_dir/$REPO_PATH" "$TOOLKIT_DIR"
        rm -rf "$temp_dir"
    fi
     msg_ok "工具箱克隆完成。"
fi

# --- 后续处理 ---
cd "$TOOLKIT_DIR"
chmod +x st-toolkit.sh scripts/*.sh

echo
msg_ok "✅ 工具箱已成功安装/更新！"
echo
echo "   即将启动主菜单..."
echo "   未来，您可以随时通过以下命令再次启动工具箱："
echo -e "   ${C_GREEN}cd $TOOLKIT_DIR && ./st-toolkit.sh${C_RESET}"
echo
sleep 3

# 启动主工具箱脚本
./st-toolkit.sh

exit 0
