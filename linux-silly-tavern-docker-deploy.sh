#!/bin/bash
# 设置-e，让脚本在任何命令失败时立即退出
set -e
# 检查是否具有sudo权限
if ! command -v sudo &> /dev/null; then
    echo "错误: sudo 命令未找到。请确保已安装sudo并且当前用户有权限运行它。"
    exit 1
fi
if [[ $EUID -ne 0 ]]; then
    if ! sudo -v &> /dev/null; then
      echo "错误: 需要sudo权限来运行此脚本。请以root用户运行或确保当前用户有sudo权限。"
      exit 1
    fi
fi
# -----------------------------------------------------------------------------
# 1. 检测服务器地理位置，判断是否在中国
# -----------------------------------------------------------------------------
echo "==> 1. 正在检测服务器位置..."
# 增加重试和超时机制
COUNTRY_CODE=$(curl -sS --connect-timeout 30 --max-time 30 -w "%{http_code}" ipinfo.io/country | sed 's/200$//') || COUNTRY_CODE=""
USE_CHINA_MIRROR=false
if [ "$COUNTRY_CODE" = "CN" ]; then
    echo "检测到服务器位于中国 (CN)，将全面使用国内镜像源进行加速。"
    USE_CHINA_MIRROR=true
else
    echo "服务器不在中国 (Country: ${COUNTRY_CODE:-"未知"})，将使用官方源。"
fi
# -----------------------------------------------------------------------------
# 2. 检测操作系统类型和版本
# -----------------------------------------------------------------------------
echo "==> 2. 检测系统类型..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION_CODENAME=$VERSION_CODENAME
    OS_VERSION_ID=$VERSION_ID
elif [ -f /etc/redhat-release ]; then
    OS=$(cat /etc/redhat-release | sed 's/\(.*\)release.*/\1/' | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    OS_VERSION_ID=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
elif [ -f /etc/arch-release ]; then
    OS="arch"
elif [ -f /etc/alpine-release ]; then
    OS="alpine"
    OS_VERSION_ID=$(cut -d'.' -f1,2 /etc/alpine-release)
elif [ -f /etc/SuSE-release ]; then
    OS="suse"
else
    echo "错误: 无法确定操作系统类型。"
    exit 1
fi
echo "当前操作系统: $OS, 版本: ${OS_VERSION_ID:-"N/A"}, 代号: ${OS_VERSION_CODENAME:-"N/A"}"
# -----------------------------------------------------------------------------
# 3. 定义安装和配置函数
# -----------------------------------------------------------------------------
# --- NEW FUNCTION ---
# 配置系统级软件包管理器的镜像源
configure_system_mirrors() {
    if [ "$USE_CHINA_MIRROR" = false ]; then
        echo "跳过系统镜像源配置（不在中国大陆）。"
        return
    fi
    echo "==> 3. 正在配置系统镜像源..."
    case $OS in
        debian|ubuntu)
            # 检查是否已经是国内源
            if grep -q -E "aliyun|tuna|ustc|163" /etc/apt/sources.list; then
                echo "检测到 /etc/apt/sources.list 已使用国内镜像，跳过替换。"
                sudo apt-get update
                return
            fi
            echo "备份当前 aports.list..."
            sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
            if [ "$OS" = "debian" ]; then
                MIRROR_URL="https://mirrors.aliyun.com/debian"
                SECURITY_MIRROR_URL="https://mirrors.aliyun.com/debian-security"
                sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb ${MIRROR_URL}/ ${OS_VERSION_CODENAME} main contrib non-free
deb-src ${MIRROR_URL}/ ${OS_VERSION_CODENAME} main contrib non-free
deb ${SECURITY_MIRROR_URL}/ ${OS_VERSION_CODENAME}-security main contrib non-free
deb-src ${SECURITY_MIRROR_URL}/ ${OS_VERSION_CODENAME}-security main contrib non-free
deb ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-updates main contrib non-free
deb-src ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-updates main contrib non-free
deb ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-backports main contrib non-free
deb-src ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-backports main contrib non-free
EOF
            elif [ "$OS" = "ubuntu" ]; then
                MIRROR_URL="https://mirrors.aliyun.com/ubuntu"
                sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb ${MIRROR_URL}/ ${OS_VERSION_CODENAME} main restricted universe multiverse
deb-src ${MIRROR_URL}/ ${OS_VERSION_CODENAME} main restricted universe multiverse
deb ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-updates main restricted universe multiverse
deb-src ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-updates main restricted universe multiverse
deb ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-backports main restricted universe multiverse
deb-src ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-backports main restricted universe multiverse
deb ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-security main restricted universe multiverse
deb-src ${MIRROR_URL}/ ${OS_VERSION_CODENAME}-security main restricted universe multiverse
EOF
            fi
            echo "系统源已替换为阿里云镜像。正在刷新..."
            sudo apt-get update
            ;;
        centos|rhel|fedora)
            if [ "$OS" = "fedora" ]; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            # 检查是否已是国内源
            if grep -q -E "aliyun|tuna|ustc|163" /etc/yum.repos.d/*.repo; then
                echo "检测到 /etc/yum.repos.d/ 已使用国内镜像，跳过替换。"
                sudo ${PKG_MANAGER} clean all && sudo ${PKG_MANAGER} makecache
                return
            fi

            echo "备份当前 yum repo 文件..."
            sudo mkdir -p /etc/yum.repos.d/bak
            sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ || true
            if [ "$OS" = "fedora" ]; then
                REPO_URL="https://mirrors.aliyun.com/fedora/fedora-$(rpm -E %fedora).repo"
            else # CentOS
                REPO_URL="https://mirrors.aliyun.com/repo/Centos-${OS_VERSION_ID}.repo"
            fi

            echo "下载新的 repo 文件从 ${REPO_URL}"
            sudo curl -o /etc/yum.repos.d/aliyun-mirror.repo ${REPO_URL}

            echo "系统源已替换为阿里云镜像。正在刷新..."
            sudo ${PKG_MANAGER} clean all && sudo ${PKG_MANAGER} makecache
            ;;
        arch)
            if grep -q "tuna.tsinghua.edu.cn" /etc/pacman.d/mirrorlist; then
                echo "检测到 pacman mirrorlist 已包含清华大学镜像，跳过。"
                sudo pacman -Syy --noconfirm
                return
            fi
            echo "备份 pacman mirrorlist..."
            sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
            echo "将清华大学镜像源置顶..."
            sudo sed -i '1s|^|Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch\n|' /etc/pacman.d/mirrorlist
            sudo pacman -Syy --noconfirm
            ;;
        alpine)
            if grep -q "aliyun" /etc/apk/repositories; then
                echo "检测到 apk repositories 已使用国内镜像，跳过。"
                sudo apk update
                return
            fi
            echo "备份 apk repositories..."
            sudo cp /etc/apk/repositories /etc/apk/repositories.bak
            echo "替换为阿里云镜像源..."
            sudo sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
            sudo apk update
            ;;

        *)
            echo "当前操作系统 $OS 的系统镜像源自动配置暂不支持。"
            ;;
    esac
}
# 配置Docker镜像加速器
configure_docker_mirror() {
    # 此函数逻辑不变
    if [ "$USE_CHINA_MIRROR" = true ]; then
        echo "配置 Docker 国内镜像加速器..."
        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://registry.docker-cn.com"
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
    # 此函数逻辑基本不变
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
    echo "未检测到 docker compose，将尝试安装..."
    case $OS in
        debian|ubuntu) sudo apt-get install -y docker-compose-v2 ;; # 推荐 v2
        centos|rhel|fedora)
            COMPOSE_URL="https://get.daocloud.io/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)"
            if [ "$USE_CHINA_MIRROR" = false ]; then
                COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
            fi
            sudo curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            ;;
        *)
            echo "对于 $OS, 推荐安装 docker-compose-plugin, 尝试通过包管理器安装..."
            case $OS in
                arch) sudo pacman -S --noconfirm docker-compose ;;
                alpine) sudo apk add docker-compose ;;
                suse) sudo zypper install -y docker-compose ;;
                *) echo "警告: 无法为 $OS 自动安装 docker-compose。"; exit 1 ;;
            esac
            ;;
    esac
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose 安装成功"
        DOCKER_COMPOSE_CMD="docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose (plugin) 安装成功"
        DOCKER_COMPOSE_CMD="docker compose"
    else
        echo "docker-compose 安装失败"
        exit 1
    fi
}
# 安装Docker的函数 - Debian/Ubuntu系统
install_docker_debian_based() {
    local os_name=$1
    echo "在 $os_name 系统上安装 Docker..."
    DOCKER_REPO_URL="https://download.docker.com"
    if [ "$USE_CHINA_MIRROR" = true ]; then
        DOCKER_REPO_URL="https://mirrors.aliyun.com/docker-ce"
    fi
    echo "使用Docker安装源: $DOCKER_REPO_URL"
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
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
    [ "$OS" = "fedora" ] && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
    sudo $PKG_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
    sudo $PKG_MANAGER install -y ${PKG_MANAGER}-utils

    REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"
    if [ "$OS" = "fedora" ]; then
        REPO_URL="https://download.docker.com/linux/fedora/docker-ce.repo"
    fi
    if [ "$USE_CHINA_MIRROR" = true ]; then
        REPO_URL="http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
        [ "$OS" = "fedora" ] && REPO_URL="https://mirrors.aliyun.com/docker-ce/linux/fedora/docker-ce.repo"
    fi
    echo "使用Docker安装源: $REPO_URL"
    sudo ${PKG_MANAGER}-config-manager --add-repo $REPO_URL
    sudo $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}
# 其他发行版安装函数
install_docker_arch() { sudo pacman -S --noconfirm docker docker-compose; }
install_docker_alpine() { sudo apk add docker docker-compose; }
install_docker_suse() { sudo zypper install -y docker docker-compose; }
# -----------------------------------------------------------------------------
# 4. 主安装流程
# -----------------------------------------------------------------------------
# --- CALL THE NEW FUNCTION ---
# 在所有包安装操作之前，先配置好系统源
configure_system_mirrors
echo "==> 4. 检查并安装 Docker..."
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，开始安装..."
    case $OS in
        debian|ubuntu) install_docker_debian_based $OS ;;
        centos|rhel|fedora) install_docker_redhat_based ;;
        arch) install_docker_arch ;;
        alpine) install_docker_alpine ;;
        suse|opensuse-leap|opensuse-tumbleweed) install_docker_suse ;;
        *) echo "不支持的操作系统: $OS"; exit 1 ;;
    esac
    if ! command -v docker &> /dev/null; then echo "Docker安装失败"; exit 1; fi
    echo "Docker 安装成功。"
    if [ "$OS" = "alpine" ]; then
        sudo rc-update add docker boot && sudo service docker start
    else
        sudo systemctl start docker && sudo systemctl enable docker
    fi

    # 首次安装完Docker后，配置镜像
    configure_docker_mirror
else
    echo "Docker已安装，跳过安装步骤。"
    # 如果已安装，也检查一下镜像配置
    if [ "$USE_CHINA_MIRROR" = true ] && ! grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
        echo "Docker已安装但未配置国内镜像，现在进行配置..."
        configure_docker_mirror
    fi
fi
echo "==> 5. 检查并安装 Docker Compose..."
setup_docker_compose
# -----------------------------------------------------------------------------
# 5. 部署 SillyTavern 应用 (此部分与原脚本一致)
# -----------------------------------------------------------------------------
echo "==> 6. 正在配置 SillyTavern..."
sudo mkdir -p /data/docker/sillytavem
SILLYTAVERN_IMAGE="ghcr.io/sillytavern/sillytavern:latest"
WATCHTOWER_IMAGE="containrrr/watchtower"
if [ "$USE_CHINA_MIRROR" = true ]; then
    echo "检测到在中国，将 docker-compose.yaml 中的镜像地址替换为南京大学镜像站..."
    SILLYTAVERN_IMAGE="ghcr.nju.edu.cn/sillytavern/sillytavern:latest"
    WATCHTOWER_IMAGE="ghcr.nju.edu.cn/containrrr/watchtower"
fi
echo "SillyTavern 镜像将使用: $SILLYTAVERN_IMAGE"
echo "Watchtower 镜像将使用: $WATCHTOWER_IMAGE"
cat <<EOF | sudo tee /data/docker/sillytavem/docker-compose.yaml
services:
  sillytavern:
    image: ${SILLYTAVERN_IMAGE}
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
    image: ${WATCHTOWER_IMAGE}
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


echo "--------------------------------------------------"
echo "请选择是否开启外网访问（并设置用户名密码）"
while true; do
    read -p "是否开启外网访问？(y/n): " -r response </dev/tty
    case $response in
        [Yy]* ) enable_external_access="y"; break ;;
        [Nn]* ) enable_external_access="n"; break ;;
        * ) echo "请输入 y 或 n" ;;
    esac
done

echo "您选择了: $([ "$enable_external_access" = "y" ] && echo "开启" || echo "不开启")外网访问"

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
                echo "已生成随机用户名: $username"; echo "已生成随机密码: $password"; break ;;
            2)
                read -p "请输入用户名(不可以使用纯数字): " -r username </dev/tty
                read -p "请输入密码(不可以使用纯数字): " -r password </dev/tty
                break ;;
            *) echo "无效输入，请输入 1 或 2" ;;
        esac
    done

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

# -----------------------------------------------------------------------------
# 6. 启动或重启服务
# -----------------------------------------------------------------------------
cd /data/docker/sillytavem

echo "--------------------------------------------------"
echo "第1步: 正在拉取所需镜像 (已使用国内镜像地址)..."
echo "此过程现在应该会很快，请稍候。"
if sudo $DOCKER_COMPOSE_CMD pull; then
    echo "✅ 镜像拉取成功。"
else
    echo "❌ 镜像拉取失败。请检查您的网络连接或镜像地址是否正确。"
    exit 1
fi

echo "--------------------------------------------------"
echo "第2步: 正在启动服务..."
sudo $DOCKER_COMPOSE_CMD up -d

if [ $? -eq 0 ]; then
    # 清屏
    clear

    echo "--------------------------------------------------"
    echo "✅ SillyTavern 已成功部署！"
    echo "--------------------------------------------------"
    # 从 ipinfo.io 的返回结果中解析出 IP 地址
    public_ip=$(curl -sS ipinfo.io | grep '"ip":' | cut -d'"' -f4)

    # 如果获取失败，则提供一个占位符
    [ -z "$public_ip" ] && public_ip="<你的服务器公网IP>"

    echo "访问地址: http://${public_ip}:8000"
    if [[ $enable_external_access == "y" ]]; then
        echo "用户名: ${username}"
        echo "密码: ${password}"
    fi
    echo "--------------------------------------------------"
    echo ""
    echo "本酒馆安装脚本由FuFu API 提供"
    echo "群号为 1019836466"
    echo "请勿盗用"
    echo "--------------------------------------------------"
else
    echo "❌ 服务启动失败，请检查日志"
    sudo $DOCKER_COMPOSE_CMD logs
fi
