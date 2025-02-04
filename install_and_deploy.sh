#!/bin/bash

# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法确定操作系统类型"
    exit 1
fi

# 安装Docker的函数
install_docker() {
    echo "开始安装Docker..."

    # 移除旧版本Docker（如果存在）
    sudo apt-get remove docker docker-engine docker.io containerd runc || true

    # 更新包索引
    sudo apt-get update

    # 安装必要的系统工具
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # 添加Docker官方GPG密钥
    curl -fsSL https://download.docker.com/linux/${OS}/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # 设置稳定版仓库
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${OS} \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 更新apt包索引
    sudo apt-get update

    # 安装Docker Engine
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    # 启动Docker服务
    sudo systemctl start docker
    sudo systemctl enable docker

    # 验证Docker安装
    if ! docker --version > /dev/null 2>&1; then
        echo "Docker安装失败"
        exit 1
    fi

    # 安装Docker Compose
    sudo apt-get install -y docker-compose-plugin

    echo "Docker安装完成"
}

# 主安装流程
echo "开始安装流程..."

# 检查是否已安装Docker
if ! command -v docker &> /dev/null; then
    install_docker
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
read -p "是否开启外网访问？(y/n): " enable_external_access

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

