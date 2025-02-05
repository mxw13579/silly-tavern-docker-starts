#!/bin/bash

# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法确定操作系统类型"
    exit 1
fi

# 安装Docker的函数 - 基于Debian/Ubuntu系统
install_docker_debian() {
    echo "在 Debian/Ubuntu 系统上安装 Docker..."

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

    # 添加Docker官方GPG密钥
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # 设置仓库
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
echo "检测系统类型..."

# 检查是否已安装Docker
if ! command -v docker &> /dev/null; then
    case $OS in
        debian|ubuntu)
            install_docker_debian
            ;;
        centos|rhel)
            install_docker_centos
            ;;
        fedora)
            install_docker_fedora
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac

    # 启动Docker服务
    sudo systemctl start docker
    sudo systemctl enable docker

    # 验证Docker安装
    if ! docker --version > /dev/null 2>&1; then
        echo "Docker安装失败"
        exit 1
    fi
else
    echo "Docker已安装，跳过安装步骤"
fi

# 创建所需目录
sudo mkdir -p /data/docker/sillytavem

# 写入docker-compose.yaml文件内容
cat <<EOF | sudo tee /data/docker/sillytavem/docker-compose.yaml
version: '3.8'

services:
  sillytavern:
    image: ghcr.io/sillytavern/sillytavern:1.12.11
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
    # 生成随机的用户名和密码
    username=$(generate_random_string)
    password=$(generate_random_string)

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

# 启动服务
cd /data/docker/sillytavem
sudo docker compose up -d

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
fi

