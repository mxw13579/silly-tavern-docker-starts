#!/bin/bash

echo -e "\033[0;32m一键安卓脚本 - 基于 Podman\033[0m"

# 修复输入问题
read -r -n 1 -p "请确认已安装魔法网络并按任意键继续..."
echo ""

# 检查并安装 Podman
if ! command -v podman &>/dev/null; then
    echo "Podman 未安装，正在安装 Podman 和相关依赖..."

    # 手动安装 Podman
    pkg update && pkg upgrade -y
    echo "正在手动安装 Podman..."
    curl -L https://github.com/containers/podman/releases/download/v4.5.0/podman-4.5.0-linux-arm.tar.gz -o podman.tar.gz
    tar -xzf podman.tar.gz -C $HOME
    mkdir -p $HOME/bin
    mv $HOME/podman-4.5.0-linux-arm/podman $HOME/bin/
    chmod +x $HOME/bin/podman
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    source ~/.bashrc

    # 检查安装结果
    if ! command -v podman &>/dev/null; then
        echo -e "\033[0;31mPodman 安装失败，请手动检查安装步骤。\033[0m"
        exit 1
    else
        echo "Podman 安装成功！"
    fi
else
    echo "Podman 已安装，跳过此步骤~"
fi

# 检查并创建 Podman 配置
echo "正在初始化 Podman 配置..."
mkdir -p $HOME/.config/containers
if [ ! -f "$HOME/.config/containers/containers.conf" ]; then
    echo -e "[containers]\ndefault_runtime = \"runc\"" > $HOME/.config/containers/containers.conf
    echo "Podman 配置已初始化~"
else
    echo "Podman 配置已存在，跳过初始化步骤~"
fi

# 检查网络连接
echo "正在检查网络..."
if ! ping -c 1 -W 1 google.com >/dev/null 2>&1; then
    echo -e "\033[0;31m网络连接失败，请检查网络或魔法连接~\033[0m"
    exit 1
fi

# 创建工作目录
workdir=$HOME/podman-sillytavern
mkdir -p "$workdir"
cd "$workdir"

# 下载镜像
echo "正在下载 Ubuntu 镜像..."
if ! podman pull ubuntu:22.04; then
    echo -e "\033[0;31m镜像下载失败，请检查网络或魔法连接~\033[0m"
    exit 1
fi

# 创建容器
echo "正在创建容器..."
container_id=$(podman run -dit ubuntu:22.04)

# 配置容器环境
echo "正在配置容器环境..."
podman exec "$container_id" apt update
podman exec "$container_id" apt install -y curl git python3 tar vim xz-utils zip

# 安装 Node.js
echo "正在安装 Node.js 和 npm..."
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

# 下载项目
echo "正在克隆 SillyTavern 项目..."
podman exec "$container_id" git clone https://github.com/SillyTavern/SillyTavern /root/SillyTavern

# 创建启动脚本
echo "创建启动脚本..."
cat >"$workdir/start.sh" <<EOF
#!/bin/bash
podman start -ai "$container_id"
EOF
chmod +x "$workdir/start.sh"

echo -e "\033[0;32m部署完成！使用以下命令启动容器：\033[0m"
echo "bash $workdir/start.sh"
