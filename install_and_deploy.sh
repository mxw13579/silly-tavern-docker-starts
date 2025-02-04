#!/bin/bash

# 更新系统包列表
sudo apt update -y

# 安装必要的包以允许 apt 通过 HTTPS 使用仓库
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# 添加 Docker 的官方 GPG 密钥
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 设置 Docker 的稳定版仓库
echo  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新 apt 包索引
sudo apt update -y

# 安装最新版本的 Docker CE 和 containerd
sudo apt install -y docker-ce docker-ce-cli containerd.io

# 安装 Docker Compose 插件
sudo apt install -y docker-compose-plugin

# 创建所需目录
mkdir -p /data/docker/sillytavem

# 写入 docker-compose.yaml 文件内容
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

# 生成随机的 username 和 password
generate_random_string() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16
}

if [[ $enable_external_access == "y" || $enable_external_access == "Y" ]]; then
    # 生成随机的用户名和密码
    username=$(generate_random_string)
    password=$(generate_random_string)

    # 创建 config 文件
    mkdir -p /data/docker/sillytavem/config
    cat <<EOF | sudo tee /data/docker/sillytavem/config/config.yaml
basicAuthUser:
  username: $username
  password: $password
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

    echo "已开启外网访问，用户名: $username, 密码: $password"
else
    echo "未开启外网访问，将使用默认配置。"
fi

# 改变目录至 /data/docker/sillytavem 并启动服务
cd /data/docker/sillytavem
sudo docker compose up -d

# 获取外网IP
public_ip=$(curl -sS https://api.ipify.org)

echo "SillyTavern 已部署，可以通过 http://${public_ip}:8000 访问。"
echo "用户名: ${username}"
echo "密码: ${password}"
