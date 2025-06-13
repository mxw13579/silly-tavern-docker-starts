#!/usr/bin/env bash
set -euo pipefail

# 判断是否 root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    IS_ROOT=1
    REAL_USER="${SUDO_USER:-root}"
else
    SUDO="sudo"
    IS_ROOT=0
    REAL_USER="${USER}"
fi

# 确保有交互式终端
if ! [ -t 0 ]; then
    echo "本脚本需要交互式终端，请用 ssh 或本地终端运行。"
    exit 1
fi

# 普通用户时检查 sudo
if [ "$IS_ROOT" -eq 0 ] && ! command -v sudo &>/dev/null; then
    echo "需要 sudo 权限，请先安装 sudo 并赋予当前用户 sudo 权限。"
    exit 1
fi

# 以 root 执行命令的函数
run_as_root() {
    if [ "$IS_ROOT" -eq 1 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# 检测系统类型
echo "检测系统类型..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS="${ID,,}"
    OS_LIKE="${ID_LIKE:-$OS}"
    OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
elif [ -f /etc/redhat-release ]; then
    OS="rhel"; OS_LIKE="rhel"
elif [ -f /etc/arch-release ]; then
    OS="arch"; OS_LIKE="arch"
elif [ -f /etc/alpine-release ]; then
    OS="alpine"; OS_LIKE="alpine"
elif [ -f /etc/SuSE-release ]; then
    OS="suse"; OS_LIKE="suse"
else
    echo "无法确定操作系统类型"
    exit 1
fi
echo "当前操作系统类型为 $OS"

# 安装 Docker
install_docker() {
    case "$OS" in
        debian|raspbian)
            run_as_root apt-get remove -y docker docker-engine docker.io containerd runc || true
            run_as_root apt-get update
            run_as_root apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            run_as_root install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg \
              | run_as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            run_as_root chmod a+r /etc/apt/keyrings/docker.gpg
            codename="${OS_VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo "bookworm")}"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
              https://download.docker.com/linux/debian $codename stable" \
              | run_as_root tee /etc/apt/sources.list.d/docker.list > /dev/null
            run_as_root apt-get update
            run_as_root apt-get install -y docker-ce docker-ce-cli containerd.io \
                                          docker-buildx-plugin docker-compose-plugin
            ;;
        ubuntu|linuxmint|elementary|pop)
            run_as_root apt-get remove -y docker docker-engine docker.io containerd runc || true
            run_as_root apt-get update
            run_as_root apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            run_as_root install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
              | run_as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            run_as_root chmod a+r /etc/apt/keyrings/docker.gpg
            codename="${OS_VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo "jammy")}"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
              https://download.docker.com/linux/ubuntu $codename stable" \
              | run_as_root tee /etc/apt/sources.list.d/docker.list > /dev/null
            run_as_root apt-get update
            run_as_root apt-get install -y docker-ce docker-ce-cli containerd.io \
                                          docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|rocky|almalinux|ol)
            run_as_root yum remove -y docker docker-client docker-common docker-engine || true
            run_as_root yum install -y yum-utils
            run_as_root yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            run_as_root yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        fedora)
            run_as_root dnf remove -y docker docker-client docker-common docker-engine || true
            run_as_root dnf -y install dnf-plugins-core
            run_as_root dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            run_as_root dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        arch)
            run_as_root pacman -Sy --noconfirm
            run_as_root pacman -S --noconfirm docker docker-compose
            ;;
        alpine)
            run_as_root apk update
            run_as_root apk add docker docker-compose
            ;;
        suse|opensuse-leap|opensuse-tumbleweed)
            run_as_root zypper refresh
            run_as_root zypper install -y docker docker-compose
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
}

# 如果没装 Docker，就安装并启动
if ! command -v docker &>/dev/null; then
    install_docker
    if [ "$OS" = "alpine" ]; then
        run_as_root rc-update add docker boot
        run_as_root service docker start
    elif command -v systemctl &>/dev/null; then
        run_as_root systemctl enable --now docker
    else
        run_as_root service docker start
    fi

    [ "$IS_ROOT" -eq 0 ] && {
      run_as_root usermod -aG docker "$REAL_USER" || true
      echo "已将 $REAL_USER 加入 docker 组，可能需要重新登录后生效"
    }

    docker --version &>/dev/null || {
      echo "Docker 安装失败"
      exit 1
    }
else
    echo "Docker 已安装，跳过安装"
fi

# 设置 docker compose 命令
DOCKER_COMPOSE_CMD=""
setup_docker_compose() {
    if docker compose version &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"; return
    fi
    if command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"; return
    fi

    case "$OS_LIKE" in
      *debian*|*ubuntu*)
        run_as_root apt-get update
        run_as_root apt-get install -y docker-compose-plugin || run_as_root apt-get install -y docker-compose
        ;;
      *rhel*|*fedora*|*centos*)
        if command -v dnf &>/dev/null; then
          run_as_root dnf install -y docker-compose-plugin || run_as_root dnf install -y docker-compose
        else
          run_as_root yum install -y docker-compose-plugin || run_as_root yum install -y docker-compose
        fi
        ;;
      *arch*)
        run_as_root pacman -S --noconfirm docker-compose
        ;;
      *alpine*)
        run_as_root apk add docker-compose
        ;;
      *suse*)
        run_as_root zypper install -y docker-compose
        ;;
      *)
        echo "不支持的系统: $OS"
        exit 1
        ;;
    esac

    if docker compose version &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo "docker compose 安装失败"
        exit 1
    fi
}
setup_docker_compose

# 创建工作目录
run_as_root mkdir -p /data/docker/sillytavern
cd /data/docker/sillytavern

# 写入 docker-compose.yaml
run_as_root tee docker-compose.yaml > /dev/null << 'EOF'
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

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400 --cleanup --label-enable
    restart: always
    networks:
      - DockerNet

networks:
  DockerNet:
    name: DockerNet
EOF

# 交互：是否开启外网访问
enable_external_access="n"
while true; do
    read -rp "是否开启外网访问？(y/n): " yn
    case "$yn" in
      [Yy]*) enable_external_access="y"; break;;
      [Nn]*) enable_external_access="n"; break;;
      *) echo "请输入 y 或 n";;
    esac
done

# 随机串函数
generate_random_string() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

if [ "$enable_external_access" = "y" ]; then
    echo "请选择用户名密码生成方式：1) 随机生成  2) 手动输入"
    while true; do
      read -rp "请输入选项(1/2): " choice
      case "$choice" in
        1)
          username=$(generate_random_string)
          password=$(generate_random_string)
          echo "随机用户名: $username"
          echo "随机密码: $password"
          break
          ;;
        2)
          while true; do
            read -rp "请输入用户名(非纯数字): " username
            [[ -n $username && ! $username =~ ^[0-9]+$ ]] && break
            echo "用户名不能为空且不能是纯数字"
          done
          while true; do
            read -rp "请输入密码(非纯数字): " password
            [[ -n $password && ! $password =~ ^[0-9]+$ ]] && break
            echo "密码不能为空且不能是纯数字"
          done
          break
          ;;
        *)
          echo "请输入 1 或 2"
          ;;
      esac
    done

    # 写入 config/config.yaml
    run_as_root mkdir -p config
    run_as_root tee config/config.yaml > /dev/null <<EOF
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
  username: ${username}
  password: ${password}
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
cookieSecret: $(generate_random_string)
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

    echo "外网访问已开启，用户名: $username  密码: $password"
else
    echo "未开启外网访问，使用默认内部访问配置"
fi

# 启动或重启服务
if $SUDO $DOCKER_COMPOSE_CMD ps | grep -q sillytavern.*Up; then
    echo "检测到服务已在运行，执行重启..."
    $SUDO $DOCKER_COMPOSE_CMD down
fi

echo "启动服务中..."
$SUDO $DOCKER_COMPOSE_CMD up -d

if [ $? -eq 0 ]; then
    if command -v curl &>/dev/null; then
        public_ip=$(curl -sS https://api.ipify.org)
    else
        public_ip="(未安装 curl，无法获取外网 IP)"
    fi
    echo "部署成功！访问地址: http://${public_ip}:8000"
    [ "$enable_external_access" = "y" ] && echo "用户名: $username   密码: $password"
else
    echo "服务启动失败，请检查日志："
    $SUDO $DOCKER_COMPOSE_CMD logs
    exit 1
fi
