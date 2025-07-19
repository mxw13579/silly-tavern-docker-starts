#!/bin/bash

set -e

# 定义仓库地址 (***请务必修改为您的GitHub用户名和仓库名***)
REPO_URL="https://github.com/mxw13579/silly-tavern-docker-starts/sillytavern-toolkit/sillytavern-toolkit.git"
TOOLKIT_DIR="$HOME/sillytavern-toolkit"


if [ -n "$(which curl)" ] && [ "$(curl -sm5 ipinfo.io/country)" = "CN" ]; then
    auto_set_source=1
fi


# 3. 如果慢 或 检测到CN
if [ "$auto_set_source" = "1" ]; then
    echo "检测到服务器为中国大陆或官方源过慢，强烈建议切换为国内软件源（如阿里云、腾讯云等）加速安装。"
    echo "自动切换源将大幅提升速度。"
    read -p "现在切换为阿里云源？（推荐）(Y/n): " anw
    anw=${anw,,}
    if [ -z "$anw" ] || [ "$anw" = "y" ] || [ "$anw" = "yes" ]; then
        # 这里假设sources.sh你能curl到
        bash <(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/mxw13579/silly-tavern-docker-starts/main/sillytavern-toolkit/scripts/sources.sh) set aliyun
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
