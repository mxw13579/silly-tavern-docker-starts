#!/bin/bash
set -euo pipefail

# 检查是否为交互式终端
if ! [ -t 0 ]; then
    echo "请不要用 'curl ... | sudo bash' 方式运行本脚本。"
    echo "请用 'curl ... | bash' 或先下载后执行。"
    exit 1
fi

# 检查是否具有sudo权限
if ! command -v sudo &> /dev/null; then
    echo "需要sudo权限来安装Docker"
    exit 1
fi
if ! sudo -n true 2>/dev/null; then
    echo "当前用户没有sudo权限，请切换到有sudo权限的用户"
    exit 1
fi

# 检查系统类型
echo "检测系统类型..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS="${ID,,}"
    OS_LIKE="${ID_LIKE:-$OS}"
    OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
elif [ -f /etc/redhat-release ]; then
    OS="rhel"
    OS_LIKE="rhel"
elif [ -f /etc/arch-release ]; then
    OS="arch"
    OS_LIKE="arch"
elif [ -f /etc/alpine-release ]; then
    OS="alpine"
    OS_LIKE="alpine"
elif [ -f /etc/SuSE-release ]; then
    OS="suse"
    OS_LIKE="suse"
else
    echo "无法确定操作系统类型"
    exit 1
fi

echo "当前操作系统类型为 $OS"

# 获取真实用户
if [ "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(logname 2>/dev/null || whoami)"
fi

# 安装 Docker
install_docker() {
    case "$OS" in
        debian|raspbian)
            echo "在 Debian 系统上安装 Docker..."
            sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            codename="${OS_VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo "bookworm")}"
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
                $codename stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        ubuntu|linuxmint|elementary|pop)
            echo "在 Ubuntu 系统上安装 Docker..."
            sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            codename="${OS_VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo "jammy")}"
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                $codename stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|rocky|almalinux|ol)
            echo "在 RHEL/CentOS 系统上安装 Docker..."
            sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        fedora)
            echo "在 Fedora 系统上安装 Docker..."
            sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        arch)
            echo "在 Arch Linux 系统上安装 Docker..."
            sudo pacman -Sy --noconfirm
            sudo pacman -S --noconfirm docker docker-compose
            ;;
        alpine)
            echo "在 Alpine Linux 系统上安装 Docker..."
            sudo apk update
            sudo apk add docker docker-compose
            ;;
        suse|opensuse-leap|opensuse-tumbleweed)
            echo "在 openSUSE 系统上安装 Docker..."
            sudo zypper refresh
            sudo zypper install -y docker docker-compose
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
}

# 检查并安装 Docker
if ! command -v docker &> /dev/null; then
    install_docker
    # 启动 Docker 服务
    if [ "$OS" = "alpine" ]; then
        sudo rc-update add docker boot
        sudo service docker start
    elif command -v systemctl &>/dev/null; then
        sudo systemctl enable --now docker
    elif command -v service &>/dev/null; then
        sudo service docker start
    else
        echo "无法自动启动 Docker 服务，请手动启动"
    fi
    # 加入 docker 用户组（可选）
    if ! id "$REAL_USER" | grep -qw docker; then
        sudo usermod -aG docker "$REAL_USER" || true
        echo "已将 $REAL_USER 加入 docker 组，可能需要重新登录后生效"
    fi
    # 验证 Docker 安装
    if ! docker --version > /dev/null 2>&1; then
        echo "Docker安装失败"
        exit 1
    fi
else
    echo "Docker已安装，跳过安装步骤"
fi

# 检查并设置 docker compose 命令
DOCKER_COMPOSE_CMD=""
setup_docker_compose() {
    if docker compose version &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    fi
    if command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    fi
    # 安装 compose-plugin 或 docker-compose
    case "$OS_LIKE" in
        *debian*|*ubuntu*)
            sudo apt-get update
            sudo apt-get install -y docker-compose-plugin || sudo apt-get install -y docker-compose
            ;;
        *rhel*|*fedora*|*centos*)
            if command -v dnf &>/dev/null; then
                sudo dnf install -y docker-compose-plugin || sudo dnf install -y docker-compose
            else
                sudo yum install -y docker-compose-plugin || sudo yum install -y docker-compose
            fi
            ;;
        *arch*)
            sudo pacman -S --noconfirm docker-compose
            ;;
        *alpine*)
            sudo apk add docker-compose
            ;;
        *suse*)
            sudo zypper install -y docker-compose
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    if docker compose version &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    elif command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    else
        echo "docker compose 安装失败"
        exit 1
    fi
}
setup_docker_compose

# 创建所需目录
sudo mkdir -p /data/docker/sillytavern

# 写入 docker-compose.yaml 文件内容
sudo tee /data/docker/sillytavern/docker-compose.yaml > /dev/null <<EOF
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
echo "请选择是否开启外网访问"
while true; do
    echo -n "是否开启外网访问？(y/n): "
    if ! read -r response </dev/tty 2>/dev/null; then
        read -r response
    fi
    case "$response" in
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

# 生成随机字符串
generate_random_string() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16
}

if [[ "$enable_external_access" =~ ^[Yy]$ ]]; then
    # 让用户选择用户名密码的生成方式
    echo "请选择用户名密码的生成方式:"
    echo "1. 随机生成"
    echo "2. 手动输入(推荐)"
    while true; do
        echo -n "请输入选项(1/2): "
        if ! read -r choice </dev/tty 2>/dev/null; then
            read -r choice
        fi
        case "$choice" in
            1)
                username="$(generate_random_string)"
                password="$(generate_random_string)"
                echo "已生成随机用户名: $username"
                echo "已生成随机密码: $password"
                break
                ;;
            2)
                while true; do
                    echo -n "请输入用户名(不可以使用纯数字): "
                    if ! read -r username </dev/tty 2>/dev/null; then
                        read -r username
                    fi
                    if [[ ! "${username}" =~ ^[0-9]+$ && -n "${username}" ]]; then
                        break
                    else
                        echo "用户名不能为纯数字且不能为空"
                    fi
                done
                while true; do
                    echo -n "请输入密码(不可以使用纯数字): "
                    if ! read -r password </dev/tty 2>/dev/null; then
                        read -r password
                    fi
                    if [[ ! "${password}" =~ ^[0-9]+$ && -n "${password}" ]]; then
                        break
                    else
                        echo "密码不能为纯数字且不能为空"
                    fi
                done
                break
                ;;
            *)
                echo "请输入 1 或 2"
                ;;
        esac
    done

    # 创建 config 目录和配置文件
    sudo mkdir -p /data/docker/sillytavern/config
    sudo tee /data/docker/sillytavern/config/config.yaml > /dev/null <<EOF
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

    echo "已开启外网访问"
    echo "用户名: $username"
    echo "密码: $password"
else
    echo "未开启外网访问，将使用默认配置。"
fi

# 启动/重启服务
cd /data/docker/sillytavern

if sudo $DOCKER_COMPOSE_CMD ps | grep -q "sillytavern.*Up"; then
    echo "检测到服务正在运行，正在重启..."
    sudo $DOCKER_COMPOSE_CMD down
fi

echo "正在启动服务..."
if sudo $DOCKER_COMPOSE_CMD up -d; then
    # 获取外网IP
    if command -v curl &>/dev/null; then
        public_ip=$(curl -sS https://api.ipify.org)
    else
        public_ip="(未检测到 curl，无法获取外网IP)"
    fi
    echo "SillyTavern 已成功部署"
    echo "访问地址: http://${public_ip}:8000"
    if [[ "$enable_external_access" =~ ^[Yy]$ ]]; then
        echo "用户名: ${username}"
        echo "密码: ${password}"
    fi
else
    echo "服务启动失败，请检查日志"
    sudo $DOCKER_COMPOSE_CMD logs
fi
