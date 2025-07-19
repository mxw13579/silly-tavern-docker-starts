#!/bin/bash

set -e

# 定义仓库地址 (***请务必修改为您的GitHub用户名和仓库名***)
REPO_URL="https://github.com/mxw13579/silly-tavern-docker-starts/sillytavern-toolkit/sillytavern-toolkit.git"
TOOLKIT_DIR="$HOME/sillytavern-toolkit"


is_cn_server=0
if [ -n "$(command -v curl)" ]; then
    if [ "x$(curl -sm5 ipinfo.io/country 2>/dev/null)" = "xCN" ]; then
        is_cn_server=1
    fi
fi

# 检查是否 apt 非法
if [ -f /etc/apt/sources.list ]; then
    if grep -q 'security.debian.org.*bullseye/updates' /etc/apt/sources.list ; then
        echo "发现 debian bullseye security 官方源格式已变（404），即将自动修正..."
        sudo sed -i 's#security\.debian\.org.*bullseye/updates#security.debian.org/debian-security bullseye-security#g' /etc/apt/sources.list
        sudo apt-get update
    fi
fi

if [ "$is_cn_server" = "1" ]; then
    echo "检测到服务器位于中国大陆，软件源及GitHub可能访问较慢。"
    echo "强烈建议优先切换软件源与后续镜像站。"
    read -p "是否一键切换为阿里云源加速安装？(Y/n): " anw
    anw=${anw,,}
    if [ "$anw" = "" ] || [ "$anw" = "y" ] || [ "$anw" = "yes" ]; then
        bash <(curl -fsSL https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/sillytavern-toolkit/scripts/sources.sh) set aliyun
    fi
fi

if ! command -v git &> /dev/null; then
    echo "==> 检测到 'git' 未安装，将为您自动安装..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y git
    elif command -v yum &> /dev/null; then
        sudo yum install -y git
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y git
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm git
    else
        echo "错误: 无法确定您的包管理器。请手动安装 'git' 后再运行此脚本。"
        exit 1
    fi
    echo "==> 'git' 安装成功！"
fi

echo "==> 欢迎使用 SillyTavern 工具箱安装程序"
echo "    本脚本将从 GitHub 下载工具箱到您的用户主目录。"

# 如果目录已存在，则更新
if [ -d "$TOOLKIT_DIR" ]; then
    echo "==> 检测到已存在的工具箱目录，将尝试从 GitHub 更新..."
    cd "$TOOLKIT_DIR"
    git pull
    echo "==> 更新完成。"
else
    echo "==> 正在从 GitHub 克隆工具箱到: $TOOLKIT_DIR"
    git clone "$REPO_URL" "$TOOLKIT_DIR"
    echo "==> 克隆完成。"
fi

# 进入目录并授权
cd "$TOOLKIT_DIR"
chmod +x st-toolkit.sh scripts/*.sh

echo
echo "✅ 工具箱已成功安装并更新！"
echo
echo "   即将启动主菜单..."
echo "   未来，您可以随时通过以下命令再次启动工具箱："
echo "   cd $TOOLKIT_DIR && ./st-toolkit.sh"
echo
sleep 3

# 启动主工具箱脚本
./st-toolkit.sh

exit 0
