#!/usr/bin/env bash
set -euo pipefail

# =========================
# 参数与用法
# =========================
usage(){
  cat <<EOF
用法: $0 [--auto|-y]
  --auto, -y    跳过所有交互，用默认（不开启外网访问）直接部署
EOF
  exit 1
}

AUTO_MODE=0
while [[ $# -gt 0 ]]; do
  case $1 in
    -y|--auto) AUTO_MODE=1; shift ;;
    *) usage ;;
  esac
done

# =========================
# 检查 sudo
# =========================
if ! command -v sudo &> /dev/null; then
  echo "需要 sudo 来继续安装" >&2
  exit 1
fi

# =========================
# 检测系统
# =========================
OS=""
OS_LIKE=""
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS=${ID,,}
  OS_LIKE=${ID_LIKE:-$OS}
elif [[ -f /etc/redhat-release ]]; then
  OS="rhel"; OS_LIKE="rhel"
elif [[ -f /etc/arch-release ]]; then
  OS="arch"; OS_LIKE="arch"
elif [[ -f /etc/alpine-release ]]; then
  OS="alpine"; OS_LIKE="alpine"
elif [[ -f /etc/SuSE-release ]]; then
  OS="suse"; OS_LIKE="suse"
else
  echo "无法识别操作系统" >&2; exit 1
fi

echo "检测到系统: $OS  (ID_LIKE=$OS_LIKE)"

# =========================
# 安装 Docker & Compose
# =========================
install_docker(){
  case "$OS" in
    debian|ubuntu|raspbian|linuxmint|pop|elementary)
      sudo apt-get update
      sudo apt-get install -y \
        apt-transport-https ca-certificates curl gnupg lsb-release
      sudo install -d -m0755 /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/${OS}/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS} $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
      ;;
    centos|rhel|rocky|almalinux|ol)
      sudo yum install -y yum-utils
      sudo yum-config-manager \
        --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    fedora)
      sudo dnf install -y dnf-plugins-core
      sudo dnf config-manager \
        --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      ;;
    arch)
      sudo pacman -Sy --noconfirm docker docker-compose
      ;;
    alpine)
      sudo apk update
      sudo apk add docker docker-compose
      ;;
    suse|opensuse*)
      sudo zypper refresh
      sudo zypper install -y docker docker-compose
      ;;
    *)
      echo "不支持的系统: $OS" >&2; exit 1 ;;
  esac

  # 启动 docker
  if [[ "$OS" == "alpine" ]]; then
    sudo rc-update add docker boot
    sudo service docker start
  else
    sudo systemctl enable --now docker
  fi
}

install_compose(){
  if docker compose version &>/dev/null; then
    DCMD="docker compose"
  elif command -v docker-compose &>/dev/null; then
    DCMD="docker-compose"
  else
    # 安装插件
    case "$OS_LIKE" in
      *debian*|*ubuntu*) sudo apt-get install -y docker-compose-plugin ;;
      *rhel*|*centos*|*fedora*)
        if command -v dnf &>/dev/null; then
          sudo dnf install -y docker-compose-plugin
        else
          sudo yum install -y docker-compose-plugin
        fi
        ;;
      *arch*) sudo pacman -Sy --noconfirm docker-compose ;;
      *alpine*) sudo apk add docker-compose ;;
      *suse*) sudo zypper install -y docker-compose ;;
      *) ;;
    esac
    if docker compose version &>/dev/null; then
      DCMD="docker compose"
    else
      DCMD="docker-compose"
    fi
  fi
}

# 安装检测
if ! command -v docker &>/dev/null; then
  install_docker
fi
install_compose

# docker 组
LOGIN_USER=$(logname 2>/dev/null || echo "$SUDO_USER")
if ! id -nG "$LOGIN_USER" | grep -qw docker; then
  echo "将用户 '$LOGIN_USER' 加入 docker 组，需要重新登录生效"
  sudo usermod -aG docker "$LOGIN_USER" || true
fi

# =========================
# 目录与 Compose 文件
# =========================
BASE=/data/docker/sillytavern
sudo mkdir -p $BASE/{plugins,config,data,extensions}

cat <<EOF | sudo tee $BASE/docker-compose.yaml
version: '3.8'
services:
  sillytavern:
    image: ghcr.io/sillytavern/sillytavern:latest
    container_name: sillytavern
    ports:
      - "8000:8000"
    volumes:
      - $BASE/plugins:/home/node/app/plugins:rw
      - $BASE/config:/home/node/app/config:rw
      - $BASE/data:/home/node/app/data:rw
      - $BASE/extensions:/home/node/app/public/scripts/extensions/third-party:rw
    restart: always
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400 --cleanup --label-enable
    restart: always
EOF

# =========================
# 外网访问配置
# =========================
enable_external_access="n"
if [[ $AUTO_MODE -eq 1 ]]; then
  enable_external_access="n"
else
  echo
  echo "请选择是否开启外网访问（Basic Auth）"
  while true; do
    read -p "是否开启外网访问? (y/n): " yn
    case $yn in
      [Yy]*) enable_external_access="y"; break ;;
      [Nn]*) enable_external_access="n"; break ;;
      *) echo "请回答 y 或 n" ;;
    esac
  done
fi

# 生成随机字符串
rand(){
  head -c32 /dev/urandom | base64 | tr -d '/+=' | cut -c1-32
}

if [[ $enable_external_access == "y" ]]; then
  echo
  echo "== 配置用户名/密码 =="
  if [[ $AUTO_MODE -eq 1 ]]; then
    username=$(rand)
    password=$(rand)
  else
    echo "1) 随机生成"
    echo "2) 手动输入"
    while true; do
      read -p "请选择 (1/2): " opt
      case $opt in
        1) username=$(rand); password=$(rand); break ;;
        2)
          while true; do
            read -p "输入用户名(非纯数字): " u
            if [[ ! $u =~ ^[0-9]+$ && -n $u ]]; then
              username=$u; break
            else
              echo "用户名不能为纯数字且不能为空"
            fi
          done
          while true; do
            read -p "输入密码(非纯数字): " p
            if [[ ! $p =~ ^[0-9]+$ && -n $p ]]; then
              password=$p; break
            else
              echo "密码不能为纯数字且不能为空"
            fi
          done
          break
          ;;
        *) echo "请输入 1 或 2" ;;
      esac
    done
  fi

  sudo mkdir -p $BASE/config
  cat <<EOCFG | sudo tee $BASE/config/config.yaml
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
cookieSecret: $(rand)
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
EOCFG

  echo "已开启外网访问：用户名=$username 密码=$password"
fi

# =========================
# 启动服务
# =========================
cd $BASE
if sudo $DCMD ps --filter name=sillytavern | grep -q sillytavern; then
  echo "正在重启容器..."
  sudo $DCMD down
fi

echo "正在启动服务..."
sudo $DCMD up -d

# =========================
# 查看结果
# =========================
echo
if command -v curl &>/dev/null; then
  public_ip=$(curl -sS https://api.ipify.org)
else
  public_ip="(未检测到 curl，无法获取外网IP)"
fi
echo "SillyTavern 已成功部署"
echo "访问地址: http://${public_ip}:8000"
if [[ $enable_external_access == "y" ]]; then
  echo "用户名: $username"
  echo "密码: $password"
fi
