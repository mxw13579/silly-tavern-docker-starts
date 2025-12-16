#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 工具函数
# -----------------------------------------------------------------------------
log() { printf '%s\n' "$*"; }
fatal() { printf '错误: %s\n' "$*" >&2; exit 1; }

safe_curl() {
  # 统一 curl 行为：失败返回非 0；带超时与重试
  # 用法: safe_curl URL 或 safe_curl -o file URL
  curl -fsSL --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 1 --retry-connrefused "$@"
}

is_pure_number() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

generate_random_string() {
  local len="${1:-16}"
  if ! [[ "${len}" =~ ^[0-9]+$ ]] || ((len < 8)); then
    len=16
  fi

  [[ -r /dev/urandom ]] || fatal "/dev/urandom 不可用，无法生成随机字符串。"

  local out="" chunk="" attempts=0
  while ((${#out} < len)); do
    chunk="$(head -c 256 /dev/urandom | tr -dc 'A-Za-z0-9' | tr -d '\n')"
    out+="${chunk}"
    ((attempts++))
    ((attempts < 20)) || fatal "随机字符串生成失败，请检查系统环境。"
  done

  out="${out:0:len}"
  is_pure_number "${out}" && out="a${out:1}"
  printf '%s' "${out}"
}

# -----------------------------------------------------------------------------
# 0. sudo / root 检查
# -----------------------------------------------------------------------------
if ! command -v sudo &>/dev/null; then
  fatal "sudo 命令未找到。请先安装 sudo 或直接使用 root 运行。"
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  sudo -v &>/dev/null || fatal "需要 sudo 权限来运行此脚本。请以 root 用户运行或确保当前用户有 sudo 权限。"
fi

# -----------------------------------------------------------------------------
# 1. 检测服务器地理位置：是否中国
# -----------------------------------------------------------------------------
log "==> 1. 正在检测服务器位置..."
COUNTRY_CODE=""
if COUNTRY_CODE="$(safe_curl ipinfo.io/country 2>/dev/null | tr -d '\n' | tr -d '\r')"; then
  :
else
  COUNTRY_CODE=""
fi

USE_CHINA_MIRROR=false
if [[ "${COUNTRY_CODE}" == "CN" ]]; then
  log "检测到服务器位于中国 (CN)，将全面使用国内镜像源进行加速。"
  USE_CHINA_MIRROR=true
else
  log "服务器不在中国 (Country: ${COUNTRY_CODE:-未知})，将使用官方源。"
fi

# -----------------------------------------------------------------------------
# 2. 检测操作系统类型和版本
# -----------------------------------------------------------------------------
log "==> 2. 检测系统类型..."

OS=""
OS_VERSION_CODENAME=""
OS_VERSION_ID=""

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS="${ID:-}"
  OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
  OS_VERSION_ID="${VERSION_ID:-}"
elif [[ -f /etc/redhat-release ]]; then
  OS="$(sed 's/\(.*\)release.*/\1/' /etc/redhat-release | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  OS_VERSION_ID="$(grep -oE '[0-9]+' /etc/redhat-release | head -1 || true)"
elif [[ -f /etc/arch-release ]]; then
  OS="arch"
elif [[ -f /etc/alpine-release ]]; then
  OS="alpine"
  OS_VERSION_ID="$(cut -d'.' -f1,2 /etc/alpine-release)"
elif [[ -f /etc/SuSE-release ]]; then
  OS="suse"
else
  fatal "无法确定操作系统类型。"
fi

log "当前操作系统: ${OS}, 版本: ${OS_VERSION_ID:-N/A}, 代号: ${OS_VERSION_CODENAME:-N/A}"

# -----------------------------------------------------------------------------
# 3. APT 自愈（Debian/Ubuntu）
# -----------------------------------------------------------------------------
guess_debian_codename_from_version() {
  # 仅作为兜底；无法可靠推断时返回空
  local dv=""
  dv="$(cat /etc/debian_version 2>/dev/null || true)"
  case "${dv}" in
    11* ) echo "bullseye" ;;
    12* ) echo "bookworm" ;;
    10* ) echo "buster" ;;
    9*  ) echo "stretch" ;;
    * ) echo "" ;;
  esac
}

apt_has_candidate() {
  local pkg="${1:-}"
  [[ -n "${pkg}" ]] || return 1
  command -v apt-cache &>/dev/null || return 0

  local candidate=""
  candidate="$(apt-cache policy "${pkg}" 2>/dev/null | sed -n 's/^[[:space:]]*Candidate: //p' | tail -n 1 || true)"
  [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

ensure_apt_ready_debian() {
  if [[ "${OS}" != "debian" && "${OS}" != "ubuntu" ]]; then
    return 0
  fi

  local check_pkg="gnupg"

  if [[ ! -f /etc/apt/sources.list ]]; then
    log "警告: /etc/apt/sources.list 不存在，将通过自愈创建官方源配置..."
  fi

  # 先尝试 update；部分环境会出现“update 成功但无有效源”的情况，因此额外校验 Candidate。
  if sudo apt-get update -o Acquire::Retries=3; then
    if apt_has_candidate "${check_pkg}"; then
      return 0
    fi
    log "警告: apt-get update 成功但无有效软件源(Candidate 为空)，将尝试自动修复 APT 源并重试..."
  else
    log "警告: apt-get update 失败，尝试自动修复 APT 源并重试..."
  fi

  local ts codename backup_dir
  ts="$(date +%F_%H%M%S)"
  sudo cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.${ts}" || true
  if [[ -d /etc/apt/sources.list.d ]]; then
    backup_dir="/etc/apt/sources.list.d.bak.${ts}"
    sudo mkdir -p "${backup_dir}" || true
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
      [[ -e "${f}" ]] || continue
      sudo mv -f "${f}" "${backup_dir}/" || true
    done
    log "已备份 /etc/apt/sources.list.d 下的第三方源到: ${backup_dir}"
  fi

  codename="${OS_VERSION_CODENAME:-}"
  if [[ -z "${codename}" && "${OS}" == "debian" ]]; then
    codename="$(guess_debian_codename_from_version)"
  fi

  [[ -n "${codename}" ]] || fatal "无法获取系统代号(VERSION_CODENAME)。请检查 /etc/os-release。"

  if [[ "${OS}" == "debian" ]]; then
    sudo tee /etc/apt/sources.list >/dev/null <<EOF
deb http://deb.debian.org/debian ${codename} main contrib non-free
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free
deb http://security.debian.org/debian-security ${codename}-security main contrib non-free
EOF
  else
    sudo tee /etc/apt/sources.list >/dev/null <<EOF
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
  fi

  sudo rm -rf /var/lib/apt/lists/*
  if ! sudo apt-get update -o Acquire::Retries=3; then
    fatal "APT 源修复后 apt-get update 仍失败。请检查网络/DNS；备份文件: /etc/apt/sources.list.bak.${ts}"
  fi
  apt_has_candidate "${check_pkg}" || fatal "APT 源修复后仍无法获取可用软件包索引（${check_pkg} Candidate 为空）。请检查网络/DNS；备份文件: /etc/apt/sources.list.bak.${ts}"
}

# -----------------------------------------------------------------------------
# 4. 配置系统级镜像源（仅中国）
# -----------------------------------------------------------------------------
configure_system_mirrors() {
  if [[ "${USE_CHINA_MIRROR}" != "true" ]]; then
    log "跳过系统镜像源配置（不在中国大陆）。"
    return 0
  fi

  log "==> 3. 正在配置系统镜像源..."
  case "${OS}" in
    debian|ubuntu)
      local codename="${OS_VERSION_CODENAME:-}"
      [[ -n "${codename}" ]] || fatal "无法获取系统代号(VERSION_CODENAME)，无法配置 APT 镜像源。"

      if grep -q -E "aliyun|tuna|ustc|163|tencent" /etc/apt/sources.list 2>/dev/null; then
        log "检测到 /etc/apt/sources.list 已使用国内镜像，跳过替换。"
        sudo apt-get update -o Acquire::Retries=3 || true
        return 0
      fi

      log "备份当前 sources.list..."
      sudo cp -a /etc/apt/sources.list /etc/apt/sources.list.bak || true

      if [[ "${OS}" == "debian" ]]; then
        local MIRROR_URL="https://mirrors.aliyun.com/debian"
        local SECURITY_MIRROR_URL="https://mirrors.aliyun.com/debian-security"
        sudo tee /etc/apt/sources.list >/dev/null <<EOF
deb ${MIRROR_URL}/ ${codename} main contrib non-free
deb-src ${MIRROR_URL}/ ${codename} main contrib non-free
deb ${SECURITY_MIRROR_URL}/ ${codename}-security main contrib non-free
deb-src ${SECURITY_MIRROR_URL}/ ${codename}-security main contrib non-free
deb ${MIRROR_URL}/ ${codename}-updates main contrib non-free
deb-src ${MIRROR_URL}/ ${codename}-updates main contrib non-free
deb ${MIRROR_URL}/ ${codename}-backports main contrib non-free
deb-src ${MIRROR_URL}/ ${codename}-backports main contrib non-free
EOF
      else
        local MIRROR_URL="https://mirrors.aliyun.com/ubuntu"
        sudo tee /etc/apt/sources.list >/dev/null <<EOF
deb ${MIRROR_URL}/ ${codename} main restricted universe multiverse
deb-src ${MIRROR_URL}/ ${codename} main restricted universe multiverse
deb ${MIRROR_URL}/ ${codename}-updates main restricted universe multiverse
deb-src ${MIRROR_URL}/ ${codename}-updates main restricted universe multiverse
deb ${MIRROR_URL}/ ${codename}-backports main restricted universe multiverse
deb-src ${MIRROR_URL}/ ${codename}-backports main restricted universe multiverse
deb ${MIRROR_URL}/ ${codename}-security main restricted universe multiverse
deb-src ${MIRROR_URL}/ ${codename}-security main restricted universe multiverse
EOF
      fi

      log "系统源已替换为阿里云镜像。正在刷新..."
      sudo rm -rf /var/lib/apt/lists/*
      sudo apt-get update -o Acquire::Retries=3
      ;;
    centos|rhel|fedora)
      local PKG_MANAGER="yum"
      [[ "${OS}" == "fedora" ]] && PKG_MANAGER="dnf"

      if grep -q -E "aliyun|tuna|ustc|163" /etc/yum.repos.d/*.repo 2>/dev/null; then
        log "检测到 /etc/yum.repos.d/ 已使用国内镜像，跳过替换。"
        sudo "${PKG_MANAGER}" clean all && sudo "${PKG_MANAGER}" makecache
        return 0
      fi

      log "备份当前 yum repo 文件..."
      sudo mkdir -p /etc/yum.repos.d/bak
      sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ || true

      local REPO_URL=""
      if [[ "${OS}" == "fedora" ]]; then
        REPO_URL="https://mirrors.aliyun.com/fedora/fedora-$(rpm -E %fedora).repo"
      else
        REPO_URL="https://mirrors.aliyun.com/repo/Centos-${OS_VERSION_ID}.repo"
      fi

      log "下载新的 repo 文件从 ${REPO_URL}"
      sudo curl -fsSL -o /etc/yum.repos.d/aliyun-mirror.repo "${REPO_URL}"

      log "系统源已替换为阿里云镜像。正在刷新..."
      sudo "${PKG_MANAGER}" clean all && sudo "${PKG_MANAGER}" makecache
      ;;
    arch)
      if grep -q "tuna.tsinghua.edu.cn" /etc/pacman.d/mirrorlist 2>/dev/null; then
        log "检测到 pacman mirrorlist 已包含清华大学镜像，跳过。"
        sudo pacman -Syy --noconfirm
        return 0
      fi
      log "备份 pacman mirrorlist..."
      sudo cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
      log "将清华大学镜像源置顶..."
      sudo sed -i '1s|^|Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch\n|' /etc/pacman.d/mirrorlist
      sudo pacman -Syy --noconfirm
      ;;
    alpine)
      if grep -q "aliyun" /etc/apk/repositories 2>/dev/null; then
        log "检测到 apk repositories 已使用国内镜像，跳过。"
        sudo apk update
        return 0
      fi
      log "备份 apk repositories..."
      sudo cp -a /etc/apk/repositories /etc/apk/repositories.bak
      log "替换为阿里云镜像源..."
      sudo sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
      sudo apk update
      ;;
    *)
      log "当前操作系统 ${OS} 的系统镜像源自动配置暂不支持。"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# 5. Docker 镜像加速（仅中国）
# -----------------------------------------------------------------------------
configure_docker_mirror() {
  [[ "${USE_CHINA_MIRROR}" == "true" ]] || return 0

  log "配置 Docker 国内镜像加速器..."
  sudo mkdir -p /etc/docker
  sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com"
  ]
}
EOF

  log "重启 Docker 服务以应用镜像加速配置..."
  if command -v systemctl &>/dev/null; then
    sudo systemctl daemon-reload || true
    sudo systemctl restart docker || true
  fi
}

# -----------------------------------------------------------------------------
# 6. Docker Compose 检测/安装
# -----------------------------------------------------------------------------
DOCKER_COMPOSE_CMD=""

setup_docker_compose() {
  if docker compose version &>/dev/null; then
    log "检测到 docker compose 命令可用"
    DOCKER_COMPOSE_CMD="docker compose"
    return 0
  fi

  if command -v docker-compose &>/dev/null; then
    log "检测到 docker-compose 命令可用"
    DOCKER_COMPOSE_CMD="docker-compose"
    return 0
  fi

  log "未检测到 docker compose，将尝试安装..."
  case "${OS}" in
    debian|ubuntu)
      ensure_apt_ready_debian
      sudo apt-get install -y docker-compose-plugin || sudo apt-get install -y docker-compose-v2
      ;;
    centos|rhel|fedora)
      local COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
      if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
        COMPOSE_URL="https://get.daocloud.io/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)"
      fi
      sudo curl -fL --connect-timeout 10 --max-time 60 "${COMPOSE_URL}" -o /usr/local/bin/docker-compose
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
      fatal "无法为 ${OS} 自动安装 docker-compose。"
      ;;
  esac

  if docker compose version &>/dev/null; then
    log "docker compose (plugin) 安装成功"
    DOCKER_COMPOSE_CMD="docker compose"
  elif command -v docker-compose &>/dev/null; then
    log "docker-compose 安装成功"
    DOCKER_COMPOSE_CMD="docker-compose"
  else
    fatal "docker-compose 安装失败"
  fi
}

# -----------------------------------------------------------------------------
# 7. 安装 Docker
# -----------------------------------------------------------------------------
install_docker_debian_based() {
  local os_name="$1"
  log "在 ${os_name} 系统上安装 Docker..."

  ensure_apt_ready_debian

  local DOCKER_REPO_URL="https://download.docker.com"
  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    DOCKER_REPO_URL="https://mirrors.cloud.tencent.com/docker-ce"
  fi
  log "使用Docker安装源: ${DOCKER_REPO_URL}"

  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
  if ! sudo apt-get install -y ca-certificates curl gnupg lsb-release; then
    log "警告: 依赖包安装失败，尝试 APT 自愈后重试..."
    ensure_apt_ready_debian
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
  fi

  sudo install -m 0755 -d /etc/apt/keyrings
  safe_curl "${DOCKER_REPO_URL}/linux/${os_name}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  local codename="${OS_VERSION_CODENAME:-}"
  if [[ -z "${codename}" ]]; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi
  [[ -n "${codename}" ]] || fatal "无法获取系统代号用于 Docker 仓库配置。"

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_REPO_URL}/linux/${os_name} ${codename} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update -o Acquire::Retries=3
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_redhat_based() {
  log "在 ${OS} 系统上安装 Docker..."
  local PKG_MANAGER="yum"
  [[ "${OS}" == "fedora" ]] && PKG_MANAGER="dnf"

  sudo "${PKG_MANAGER}" remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
  sudo "${PKG_MANAGER}" install -y "${PKG_MANAGER}-utils"

  local REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"
  [[ "${OS}" == "fedora" ]] && REPO_URL="https://download.docker.com/linux/fedora/docker-ce.repo"

  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    REPO_URL="http://mirrors.cloud.tencent.com/docker-ce/linux/centos/docker-ce.repo"
    [[ "${OS}" == "fedora" ]] && REPO_URL="https://mirrors.cloud.tencent.com/docker-ce/linux/fedora/docker-ce.repo"
  fi

  log "使用Docker安装源: ${REPO_URL}"
  sudo "${PKG_MANAGER}-config-manager" --add-repo "${REPO_URL}"
  sudo "${PKG_MANAGER}" install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

install_docker_arch() { sudo pacman -S --noconfirm docker docker-compose; }
install_docker_alpine() { sudo apk add docker docker-compose; }
install_docker_suse() { sudo zypper install -y docker docker-compose; }

start_and_verify_docker() {
  if [[ "${OS}" == "alpine" ]]; then
    sudo rc-update add docker boot
    sudo service docker start
  else
    command -v systemctl &>/dev/null || fatal "systemctl 不存在，无法在非 alpine 系统上管理 docker 服务。"
    if ! sudo systemctl enable --now docker; then
      log "❌ Docker 启动失败，日志如下："
      sudo journalctl -xeu docker.service --no-pager -n 80 || true
      exit 1
    fi
  fi

  if ! docker version &>/dev/null; then
    log "❌ Docker 似乎未正常运行，日志如下："
    if command -v journalctl &>/dev/null; then
      sudo journalctl -xeu docker.service --no-pager -n 80 || true
    fi
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# 8. 主安装流程
# -----------------------------------------------------------------------------
configure_system_mirrors

log "==> 4. 检查并安装 Docker..."
if ! command -v docker &>/dev/null; then
  log "Docker 未安装，开始安装..."
  case "${OS}" in
    debian|ubuntu) install_docker_debian_based "${OS}" ;;
    centos|rhel|fedora) install_docker_redhat_based ;;
    arch) install_docker_arch ;;
    alpine) install_docker_alpine ;;
    suse|opensuse-leap|opensuse-tumbleweed) install_docker_suse ;;
    *) fatal "不支持的操作系统: ${OS}" ;;
  esac

  command -v docker &>/dev/null || fatal "Docker 安装失败"
  log "Docker 安装成功。"

  start_and_verify_docker
  configure_docker_mirror
else
  log "Docker 已安装，跳过安装步骤。"
  if [[ "${USE_CHINA_MIRROR}" == "true" ]] && ! grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
    log "Docker 已安装但未配置国内镜像，现在进行配置..."
    configure_docker_mirror
  fi
fi

log "==> 5. 检查并安装 Docker Compose..."
setup_docker_compose

# -----------------------------------------------------------------------------
# 9. 部署 SillyTavern
# -----------------------------------------------------------------------------
log "==> 6. 正在配置 SillyTavern..."
sudo mkdir -p /data/docker/sillytavem

SILLYTAVERN_IMAGE="ghcr.io/sillytavern/sillytavern:latest"
WATCHTOWER_IMAGE="containrrr/watchtower"
if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
  log "检测到在中国，将 docker-compose.yaml 中的镜像地址替换为南京大学镜像站..."
  SILLYTAVERN_IMAGE="ghcr.nju.edu.cn/sillytavern/sillytavern:latest"
  WATCHTOWER_IMAGE="ghcr.nju.edu.cn/containrrr/watchtower"
fi

log "SillyTavern 镜像将使用: ${SILLYTAVERN_IMAGE}"
log "Watchtower 镜像将使用: ${WATCHTOWER_IMAGE}"

cat <<EOF | sudo tee /data/docker/sillytavem/docker-compose.yaml >/dev/null
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

log "--------------------------------------------------"
log "请选择是否开启外网访问（并设置用户名密码）"

enable_external_access="n"
while true; do
  read -r -p "是否开启外网访问？(y/n): " response </dev/tty
  case "${response}" in
    [Yy]*) enable_external_access="y"; break ;;
    [Nn]*) enable_external_access="n"; break ;;
    *) log "请输入 y 或 n" ;;
  esac
done

log "您选择了: $([[ "${enable_external_access}" == "y" ]] && echo "开启" || echo "不开启")外网访问"

username=""
password=""

if [[ "${enable_external_access}" == "y" ]]; then
  log "请选择用户名密码的生成方式:"
  log "1. 随机生成"
  log "2. 手动输入(推荐)"

  choice=""
  while true; do
    read -r -p "请输入您的选择 (1/2): " choice </dev/tty
    case "${choice}" in
      1)
        username="$(generate_random_string)"
        password="$(generate_random_string)"
        log "已生成随机用户名: ${username}"
        log "已生成随机密码: ${password}"
        break
        ;;
      2)
        while true; do
          read -r -p "请输入用户名(不可以使用纯数字): " username </dev/tty
          [[ -n "${username}" ]] || { log "用户名不能为空"; continue; }
          if is_pure_number "${username}"; then
            log "❌ 用户名不能为纯数字"
            continue
          fi
          break
        done
        while true; do
          read -r -p "请输入密码(不可以使用纯数字): " password </dev/tty
          [[ -n "${password}" ]] || { log "密码不能为空"; continue; }
          if is_pure_number "${password}"; then
            log "❌ 密码不能为纯数字"
            continue
          fi
          break
        done
        break
        ;;
      *) log "无效输入，请输入 1 或 2" ;;
    esac
  done

  sudo mkdir -p /data/docker/sillytavem/config
  cat <<EOF | sudo tee /data/docker/sillytavem/config/config.yaml >/dev/null
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
EOF

  log "已开启外网访问并配置用户名密码。"
else
  log "未开启外网访问，将使用默认配置。"
fi

# -----------------------------------------------------------------------------
# 10. 启动服务
# -----------------------------------------------------------------------------
cd /data/docker/sillytavem

log "--------------------------------------------------"
log "第1步: 正在拉取所需镜像..."
sudo ${DOCKER_COMPOSE_CMD} pull

log "--------------------------------------------------"
log "第2步: 正在启动服务..."
sudo ${DOCKER_COMPOSE_CMD} up -d

clear || true
log "--------------------------------------------------"
log "✅ SillyTavern 已成功部署！"
log "--------------------------------------------------"

public_ip=""
if public_ip="$(safe_curl ipinfo.io 2>/dev/null | grep '"ip":' | cut -d'"' -f4 || true)"; then
  :
fi
[[ -z "${public_ip}" ]] && public_ip="<你的服务器公网IP>"

log "访问地址: http://${public_ip}:8000"
if [[ "${enable_external_access}" == "y" ]]; then
  log "用户名: ${username}"
  log "密码: ${password}"
fi

log "--------------------------------------------------"
log "本酒馆安装脚本由FuFu API 提供"
log "群号为 1019836466"
log "请勿盗用"
log "--------------------------------------------------"
