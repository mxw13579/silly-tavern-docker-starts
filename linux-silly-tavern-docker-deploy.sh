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


# 检查并设置docker compose命令
setup_docker_compose() {
    # 首先检查是否有docker compose（新版命令）
    if docker compose version &> /dev/null; then
        echo "检测到 docker compose 命令可用"
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    fi

    # 检查是否有docker-compose（旧版命令）
    if command -v docker-compose &> /dev/null; then
        echo "检测到 docker-compose 命令可用"
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    fi

    # 如果都没有，则需要安装docker-compose
    echo "未检测到 docker compose，将安装 docker-compose..."

    case $OS in
        debian|ubuntu)
            sudo apt-get update
            sudo apt-get install -y docker-compose
            ;;
        centos|rhel|fedora)
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            ;;
        arch)
            sudo pacman -S --noconfirm docker-compose
            ;;
        alpine)
            sudo apk add docker-compose
            ;;
        suse|opensuse-leap|opensuse-tumbleweed)
            sudo zypper install -y docker-compose
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac

    # 验证安装
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose 安装成功"
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    else
        echo "docker-compose 安装失败"
        exit 1
    fi
}

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

# 设置 docker compose 命令
setup_docker_compose

# 创建所需目录
sudo mkdir -p /data/docker/sillytavem

# 写入docker-compose.yaml文件内容
cat <<EOF | sudo tee /data/docker/sillytavem/docker-compose.yaml
version: '3.8'

services:
  sillytavern:
    image: ghcr.io/sillytavern/sillytavern:latest
    container_name: sillytavern
    networks:
      - DockerNet
    ports:
      - "8000:8000"
    volumes:
      - ./plugins:/home/node/app/plugins:rw
      - ./config:/home/node/app/config:rw
      - ./data:/home/node/app/data:rw
      - ./extensions:/home/node/app/public/scripts/extensions/third-party:rw
    restart: always
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  # 添加watchtower服务自动更新容器
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400 --cleanup --label-enable # 每天检查一次更新
    restart: always
    networks:
      - DockerNet

networks:
  DockerNet:
    name: DockerNet
EOF


# 提示用户确认是否开启外网访问
echo "请选择是否开启外网访问"
while true; do
    echo -n "是否开启外网访问？(y/n): "
    read -r response </dev/tty
    case $response in
        [Yy]* )
            enable_external_access="y"
            break
            ;;
        [Nn]* )
            enable_external_access="n"
            break
            ;;
        * )
            echo "请输入 y 或 n"
            ;;
    esac
done

# 确保显示用户的选择
echo "您选择了: $([ "$enable_external_access" = "y" ] && echo "开启" || echo "不开启")外网访问"

# 生成随机字符串的函数
generate_random_string() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16
}

if [[ $enable_external_access == "y" || $enable_external_access == "Y" ]]; then
    # 让用户选择用户名密码的生成方式
    echo "请选择用户名密码的生成方式:"
    echo "1. 随机生成"
    echo "2. 手动输入(推荐)"
    while true; do
        read -r choice </dev/tty
        case $choice in
            1)
                username=$(generate_random_string)
                password=$(generate_random_string)
                echo "已生成随机用户名: $username"
                echo "已生成随机密码: $password"
                break
                ;;
            2)
                echo -n "请输入用户名(不可以使用纯数字): "
                read -r username </dev/tty
                echo -n "请输入密码(不可以使用纯数字): "
                read -r password </dev/tty
                break
                ;;
            *)
                echo "请输入 1 或 2"
                ;;
        esac
    done

    # 创建config目录和配置文件
    sudo mkdir -p /data/docker/sillytavem/config
    cat <<EOF | sudo tee /data/docker/sillytavem/config/config.yaml
dataRoot: ./data
cardsCacheCapacity: 100
listen: true
protocol:
  ipv4: true
  ipv6: false
dnsPreferIPv6: false
autorunHostname: auto
port: 8000
autorunPortOverride: -1
whitelistMode: false
enableForwardedWhitelist: true
whitelist:
  - ::1
  - 127.0.0.1
  - 0.0.0.0
basicAuthMode: true
basicAuthUser:
  username: $username
  password: $password
enableCorsProxy: false
requestProxy:
  enabled: false
  url: socks5://username:password@example.com:1080
  bypass:
    - localhost
    - 127.0.0.1
enableUserAccounts: false
enableDiscreetLogin: false
autheliaAuth: false
perUserBasicAuth: false
sessionTimeout: 86400
cookieSecret: 6XgkD9H+Foh+h9jVCbx7bEumyZuYtc5RVzKMEc+ORjDGOAvfWVjfPGyRmbFSVPjdy8ofG3faMe8jDf+miei0yQ==
disableCsrfProtection: false
securityOverride: false
autorun: true
avoidLocalhost: false
backups:
  common:
    numberOfBackups: 50
  chat:
    enabled: true
    maxTotalBackups: -1
    throttleInterval: 10000
thumbnails:
  enabled: true
  format: jpg
  quality: 95
  dimensions:
    bg:
      - 160
      - 90
    avatar:
      - 96
      - 144
allowKeysExposure: false
skipContentCheck: false
whitelistImportDomains:
  - localhost
  - cdn.discordapp.com
  - files.catbox.moe
  - raw.githubusercontent.com
requestOverrides: []
enableExtensions: true
enableExtensionsAutoUpdate: true
enableDownloadableTokenizers: true
extras:
  disableAutoDownload: false
  classificationModel: Cohee/distilbert-base-uncased-go-emotions-onnx
  captioningModel: Xenova/vit-gpt2-image-captioning
  embeddingModel: Cohee/jina-embeddings-v2-base-en
  speechToTextModel: Xenova/whisper-small
  textToSpeechModel: Xenova/speecht5_tts
promptPlaceholder: "[Start a new chat]"
openai:
  randomizeUserId: false
  captionSystemPrompt: ""
deepl:
  formality: default
mistral:
  enablePrefix: false
ollama:
  keepAlive: -1
claude:
  enableSystemPromptCache: false
  cachingAtDepth: -1
enableServerPlugins: false
EOF

    echo "已开启外网访问"
    echo "用户名: $username"
    echo "密码: $password"
else
    echo "未开启外网访问，将使用默认配置。"
fi

# 检查服务是否已运行并重启
cd /data/docker/sillytavem

if sudo $DOCKER_COMPOSE_CMD ps | grep -q "Up"; then
    echo "检测到服务正在运行，正在重启..."
    sudo docker compose stop
    sudo docker compose up -d
    sudo $DOCKER_COMPOSE_CMD stop
    sudo $DOCKER_COMPOSE_CMD up -d
else
    echo "服务未运行，正在启动..."
    sudo docker compose up -d
    sudo $DOCKER_COMPOSE_CMD up -d
fi

# 检查服务是否成功启动
if [ $? -eq 0 ]; then
    # 获取外网IP
    public_ip=$(curl -sS https://api.ipify.org)
    echo "SillyTavern 已成功部署"
    echo "访问地址: http://${public_ip}:8000"
    if [[ $enable_external_access == "y" || $enable_external_access == "Y" ]]; then
        echo "用户名: ${username}"
        echo "密码: ${password}"
    fi
else
    echo "服务启动失败，请检查日志"
    sudo docker compose logs
    sudo $DOCKER_COMPOSE_CMD logs
fi


