#!/bin/bash

echo "
一键安卓脚本 - 基于 Podman
"

echo -e "\033[0;31m确保已经正确安装Podman和魔法网络，然后按回车继续~\033[0m\n"
read -p "确认后按回车继续"

# 检查并安装 Podman
if ! command -v podman &>/dev/null; then
    echo "Podman 未安装，正在安装 Podman 和相关依赖..."
    pkg update && pkg upgrade -y
    pkg install -y git podman fuse-overlayfs slirp4netns
    echo "Podman 已安装成功！"
else
    echo "Podman 已安装，跳过此步骤~"
fi

# 确保 Podman 配置初始化
mkdir -p $HOME/.config/containers
if [ ! -f "$HOME/.config/containers/containers.conf" ]; then
    cp /data/data/com.termux/files/usr/share/containers/containers.conf $HOME/.config/containers/
    echo "Podman 配置初始化完成~"
fi

# 确保网络正常
echo "正在检查网络..."
if ! ping -c 1 -W 1 google.com >/dev/null 2>&1; then
    echo -e "\033[0;31m网络连接失败，请检查网络或魔法连接~\033[0m"
    exit 1
fi

# 创建工作目录
workdir=$HOME/podman-sillytavern
mkdir -p "$workdir"
cd "$workdir"

# 拉取 Ubuntu 镜像
echo "正在下载 Ubuntu 镜像~"
if ! podman pull ubuntu:22.04; then
    echo -e "\033[0;31mUbuntu 镜像下载失败，请检查网络或魔法连接~\033[0m"
    exit 1
fi

# 创建容器
echo "正在创建并启动容器~"
container_id=$(podman run -dit ubuntu:22.04)

# 配置容器环境
echo "正在为容器安装必要的软件~"
podman exec "$container_id" apt update
podman exec "$container_id" apt install -y curl git vim tar xz-utils python3 zip

# 安装 Node.js
echo "正在安装 Node.js 和 npm ~"
podman exec "$container_id" curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
podman exec "$container_id" apt install -y nodejs

# 检查 Node.js 和 npm
if ! podman exec "$container_id" node --version >/dev/null 2>&1; then
    echo -e "\033[0;31mNode.js 安装失败，请检查网络或魔法连接~\033[0m"
    exit 1
fi
if ! podman exec "$container_id" npm --version >/dev/null 2>&1; then
    echo -e "\033[0;31mnpm 安装失败，请检查网络或魔法连接~\033[0m"
    exit 1
fi

echo "Node.js 和 npm 安装成功~"

# 克隆 SillyTavern 项目
echo "正在下载 SillyTavern..."
podman exec "$container_id" git clone https://github.com/SillyTavern/SillyTavern /root/SillyTavern

# 克隆 Promot 预设文件
echo "正在下载 Promot 预设文件..."
podman exec "$container_id" git clone https://github.com/hopingmiao/promot.git /root/st_promot

# 导入 Promot 文件
echo "正在导入 Promot 文件..."
podman exec "$container_id" cp -r /root/st_promot/. /root/SillyTavern/public/'OpenAI Settings'/

echo "所有文件已成功导入~"

# 创建启动脚本
echo "创建启动脚本..."
cat >"$workdir/start.sh" <<EOF
#!/bin/bash
podman start -ai "$container_id"
EOF
chmod +x "$workdir/start.sh"

echo -e "\033[0;32m使用以下命令启动容器：\033[0m"
echo "bash $workdir/start.sh"
