#!/bin/bash

# 检查是否具有sudo权限
if ! command -v sudo &> /dev/null; then
    echo "需要sudo权限来安装Docker"
    exit 1
fi

# 主安装流程
echo "检测系统类型..."
# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
elif [ -f /etc/redhat-release ]; then
    OS=$(cat /etc/redhat-release | sed 's/\(.*\)release.*/\1/' | tr '[:upper:]' '[:lower:]' | tr -d ' ')
elif [ -f /etc/arch-release ]; then
    OS="arch"
elif [ -f /etc/alpine-release ]; then
    OS="alpine"
elif [ -f /etc/SuSE-release ]; then
    OS="suse"
else
    echo "无法确定操作系统类型"
    exit 1
fi



# 安装Docker的函数 - Debian系统
install_docker_debian() {
    echo "在 Debian 系统上安装 Docker..."

    # 移除旧版本
    sudo apt-get remove docker docker-engine docker.io containerd runc || true

    # 更新并安装依赖
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # 添加Docker官方GPG密钥（Debian专用）
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # 设置Debian仓库
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# 安装Docker的函数 - Ubuntu系统
install_docker_ubuntu() {
    echo "在 Ubuntu 系统上安装 Docker..."

    # 移除旧版本
    sudo apt-get remove docker docker-engine docker.io containerd runc || true

    # 更新并安装依赖
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # 添加Docker官方GPG密钥（Ubuntu专用）
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # 设置Ubuntu仓库
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# 安装Docker的函数 - 基于CentOS/RHEL系统
install_docker_centos() {
    echo "在 CentOS/RHEL 系统上安装 Docker..."

    # 移除旧版本
    sudo yum remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true

    # 安装必要的工具
    sudo yum install -y yum-utils

    # 添加Docker仓库
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # 安装Docker
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

# Arch Linux 安装函数
install_docker_arch() {
    echo "在 Arch Linux 系统上安装 Docker..."
    sudo pacman -Sy
    sudo pacman -S --noconfirm docker docker-compose
}

# Alpine Linux 安装函数
install_docker_alpine() {
    echo "在 Alpine Linux 系统上安装 Docker..."
    sudo apk update
    sudo apk add docker docker-compose
}

# OpenSUSE 安装函数
install_docker_suse() {
    echo "在 OpenSUSE 系统上安装 Docker..."
    sudo zypper refresh
    sudo zypper install -y docker docker-compose
}


# 安装Docker的函数 - 基于Fedora系统
install_docker_fedora() {
    echo "在 Fedora 系统上安装 Docker..."

    # 移除旧版本
    sudo dnf remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true

    # 添加Docker仓库
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

    # 安装Docker
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

# 主安装流程
echo "当前操作系统类型为 $OS"

# 检查是否已安装Docker
if ! command -v docker &> /dev/null; then
    case $OS in
        debian)
            install_docker_debian
            ;;
        ubuntu)
            install_docker_ubuntu
            ;;
        centos|rhel)
            install_docker_centos
            ;;
        fedora)
            install_docker_fedora
            ;;
        arch)
            install_docker_arch
            ;;
        alpine)
            install_docker_alpine
            ;;
        suse|opensuse-leap|opensuse-tumbleweed)
            install_docker_suse
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac


    # 启动Docker服务
    # Alpine 的特殊处理
    if [ "$OS" = "alpine" ]; then
        sudo rc-update add docker boot
        sudo service docker start
    else
        sudo systemctl start docker
        sudo systemctl enable docker
    fi



    # 验证Docker安装
    if ! docker --version > /dev/null 2>&1; then
        echo "Docker安装失败"
        exit 1
    fi

    # 检查Docker Compose
    if ! docker-compose --version > /dev/null 2>&1; then
        echo "警告: Docker Compose 未安装或安装失败"
    fi
else
    echo "Docker已安装，跳过安装步骤"
fi