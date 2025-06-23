#!/bin/bash

# 检查是否具有sudo权限
if ! command -v sudo &> /dev/null; then
    echo "需要sudo权限来运行此脚本"
    exit 1
fi

# -----------------------------------------------------------------------------
# 1. 检测服务器地理位置，判断是否在中国
# -----------------------------------------------------------------------------
echo "正在检测服务器位置..."
# 使用curl请求ipinfo.io并用grep和cut解析，避免需要安装jq
COUNTRY_CODE=$(curl -sS ipinfo.io | grep '"country":' | cut -d'"' -f4)

USE_CHINA_MIRROR=false
if [ "$COUNTRY_CODE" = "CN" ]; then
    echo "检测到服务器位于中国 (CN)，将使用国内镜像源进行加速。"
    USE_CHINA_MIRROR=true
else
    echo "服务器不在中国 (Country: ${COUNTRY_CODE:-"Unknown"})，将使用官方源。"
fi


# -----------------------------------------------------------------------------
# 2. 检测操作系统类型
# -----------------------------------------------------------------------------
echo "检测系统类型..."
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
echo "当前操作系统类型为 $OS"


# -----------------------------------------------------------------------------
# 3. 定义安装和配置函数
# -----------------------------------------------------------------------------

# 配置Docker镜像加速器 (适用于中国大陆)
configure_docker_mirror() {
    if [ "$USE_CHINA_MIRROR" = true ]; then
        echo "配置 Docker 国内镜像加速器..."
        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://registry.docker-cn.com",
    "https://hub-mirror.c.163.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://cr.console.aliyun.com"
  ]
}
EOF
        echo "重启Docker服务以应用镜像加速配置..."
        sudo systemctl daemon-reload
        sudo systemctl restart docker
    fi
}

# 检查并设置docker compose命令
setup_docker_compose() {
    if docker compose version &> /dev/null; then
        echo "检测到 docker compose 命令可用"
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    fi

    if command -v docker-compose &> /dev/null; then
        echo "检测到 docker-compose 命令可用"
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    fi

    echo "未检测到 docker compose，将尝试安装 docker-compose..."
    case $OS in
        debian|ubuntu)
            sudo apt-get update
            sudo apt-get install -y docker-compose
            ;;
        centos|rhel|fedora)
            if [ "$USE_CHINA_MIRROR" = true ]; then
                # 使用国内的daocloud下载
                sudo curl -L "https://get.daocloud.io/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            else
                sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            fi
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
            echo "不支持的操作系统: $OS，无法自动安装 docker-compose"
            exit 1
            ;;
    esac

    if command -v docker-compose &> /dev/null; then
        echo "docker-compose 安装成功"
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo "docker-compose 安装失败"
        exit 1
    fi
}

# 安装Docker的函数 - Debian/Ubuntu系统 (合并版本)
install_docker_debian_based() {
    local os_name=$1
    echo "在 $os_name 系统上安装 Docker..."

    # 根据地理位置选择仓库URL
    if [ "$USE_CHINA_MIRROR" = true ]; then
        DOCKER_REPO_URL="https://mirrors.aliyun.com/docker-ce"
        echo "使用阿里云镜像源: $DOCKER_REPO_URL"
    else
        DOCKER_REPO_URL="https://download.docker.com"
        echo "使用Docker官方源: $DOCKER_REPO_URL"
    fi

    sudo apt-get remove docker docker-engine docker.io containerd runc || true
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "${DOCKER_REPO_URL}/linux/${os_name}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_REPO_URL}/linux/${os_name} \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# 安装Docker的函数 - CentOS/RHEL/Fedora系统
install_docker_redhat_based() {
    echo "在 $OS 系统上安装 Docker..."

    if [ "$OS" = "fedora" ]; then
        PKG_MANAGER="dnf"
        sudo $PKG_MANAGER remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
        sudo $PKG_MANAGER -y install dnf-plugins-core
    else # centos, rhel
        PKG_MANAGER="yum"
        sudo $PKG_MANAGER remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
        sudo $PKG_MANAGER install -y yum-utils
    fi

    if [ "$USE_CHINA_MIRROR" = true ]; then
        REPO_URL="http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
        echo "使用阿里云镜像源: $REPO_URL"
    else
        REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"
        if [ "$OS" = "fedora" ]; then
            REPO_URL="https://download.docker.com/linux/fedora/docker-ce.repo"
        fi
        echo "使用Docker官方源: $REPO_URL"
    fi

    sudo ${PKG_MANAGER}-config-manager --add-repo $REPO_URL
    sudo $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

# Arch Linux 安装函数
install_docker_arch() {
    echo "在 Arch Linux 系统上安装 Docker..."
    sudo pacman -Sy --noconfirm
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


# -----------------------------------------------------------------------------
# 4. 主安装流程
# -----------------------------------------------------------------------------
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，开始安装..."
    case $OS in
        debian|ubuntu)
            install_docker_debian_based $OS
            ;;
        centos|rhel|fedora)
            install_docker_redhat_based
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

    # 验证Docker安装
    if ! command -v docker &> /dev/null; then
        echo "Docker安装失败"
        exit 1
    fi
    echo "Docker 安装成功。"

    # 启动并启用Docker服务
    if [ "$OS" = "alpine" ]; then
        sudo rc-update add docker boot
        sudo service docker start
    else
        sudo systemctl start docker
        sudo systemctl enable docker
    fi

    # 配置镜像加速器
    configure_docker_mirror

else
    echo "Docker已安装，跳过安装步骤。"
    # 对已安装的Docker也应用镜像加速配置
    configure_docker_mirror
fi

# 设置 docker compose 命令
setup_docker_compose

# -----------------------------------------------------------------------------
# 5. 部署 SillyTavern 应用
# -----------------------------------------------------------------------------
echo "正在配置 SillyTavern..."

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
echo "--------------------------------------------------"
echo "请选择是否开启外网访问（并设置用户名密码）"
while true; do
    read -p "是否开启外网访问？(y/n): " -r response </dev/tty
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

echo "您选择了: $([ "$enable_external_access" = "y" ] && echo "开启" || echo "不开启")外网访问"

# 生成随机字符串的函数
generate_random_string() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16
}

if [[ $enable_external_access == "y" ]]; then
    echo "请选择用户名密码的生成方式:"
    echo "1. 随机生成"
    echo "2. 手动输入(推荐)"
    while true; do
        read -p "请输入您的选择 (1/2): " -r choice </dev/tty
        case $choice in
            1)
                username=$(generate_random_string)
                password=$(generate_random_string)
                echo "已生成随机用户名: $username"
                echo "已生成随机密码: $password"
                break
                ;;
            2)
                read -p "请输入用户名(不可以使用纯数字): " -r username </dev/tty
                read -p "请输入密码(不可以使用纯数字): " -r password </dev/tty
                break
                ;;
            *)
                echo "无效输入，请输入 1 或 2"
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

    echo "已开启外网访问并配置用户名密码。"
else
    echo "未开启外网访问，将使用默认配置。"
fi

# 启动或重启服务
echo "正在启动 SillyTavern 服务..."
cd /data/docker/sillytavem

# 使用 DOCKER_COMPOSE_CMD 变量来执行命令
sudo $DOCKER_COMPOSE_CMD up -d

# 检查服务是否成功启动
if [ $? -eq 0 ]; then
    echo "--------------------------------------------------"
    echo "✅ SillyTavern 已成功部署！"
    echo "--------------------------------------------------"
    # 获取外网IP
    public_ip=$(curl -sS https://api.ipify.org)
    if [ -z "$public_ip" ]; then
        public_ip="<你的服务器公网IP>"
    fi
    echo "访问地址: http://${public_ip}:8000"
    if [[ $enable_external_access == "y" ]]; then
        echo "用户名: ${username}"
        echo "密码: ${password}"
    fi
    echo "--------------------------------------------------"
else
    echo "❌ 服务启动失败，请检查日志"
    sudo $DOCKER_COMPOSE_CMD logs
fi
