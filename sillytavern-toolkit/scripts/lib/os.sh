#!/usr/bin/env bash

init_sudo() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    SUDO=()
  else
    command -v sudo &>/dev/null || fatal "sudo 未安装。请使用 root 运行或先安装 sudo。"
    sudo -v &>/dev/null || fatal "当前用户没有 sudo 权限。"
    SUDO=(sudo)
  fi
}

check_sudo() {
  init_sudo
}

os_like_has() {
  local item="$1"
  [[ " ${OS_LIKE:-} " == *" ${item} "* ]]
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
    OS_UBUNTU_CODENAME="${UBUNTU_CODENAME:-}"
  elif [[ -f /etc/arch-release ]]; then
    OS="arch"
  elif [[ -f /etc/alpine-release ]]; then
    OS="alpine"
    OS_VERSION_ID="$(cut -d'.' -f1,2 /etc/alpine-release)"
  else
    fatal "无法识别当前 Linux 发行版。"
  fi

  case "${OS}" in
    debian|ubuntu) OS_FAMILY="debian" ;;
    centos|rhel|fedora|rocky|almalinux|ol|oracle|centos_stream) OS_FAMILY="redhat" ;;
    arch|manjaro) OS_FAMILY="arch" ;;
    alpine) OS_FAMILY="alpine" ;;
    opensuse-leap|opensuse-tumbleweed|sles|suse) OS_FAMILY="suse" ;;
    *)
      if os_like_has ubuntu || os_like_has debian; then
        OS_FAMILY="debian"
      elif os_like_has rhel || os_like_has fedora || os_like_has centos; then
        OS_FAMILY="redhat"
      elif os_like_has arch; then
        OS_FAMILY="arch"
      elif os_like_has suse; then
        OS_FAMILY="suse"
      else
        fatal "暂不支持的系统: ${OS}"
      fi
      ;;
  esac

  if [[ "${OS_FAMILY}" == "debian" ]]; then
    if [[ "${OS}" == "ubuntu" ]] || os_like_has ubuntu || [[ -n "${OS_UBUNTU_CODENAME}" ]]; then
      DOCKER_REPO_OS="ubuntu"
    else
      DOCKER_REPO_OS="debian"
    fi
  fi
}

detect_init_system() {
  if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service &>/dev/null || command -v rc-update &>/dev/null; then
    INIT_SYSTEM="openrc"
  else
    INIT_SYSTEM="unknown"
  fi
}

detect_package_manager() {
  case "${OS_FAMILY}" in
    debian)
      command -v apt-get &>/dev/null || fatal "未找到 apt-get。"
      PKG_MANAGER="apt"
      ;;
    redhat)
      if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
      elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
      else
        fatal "未找到 dnf/yum。"
      fi
      ;;
    arch)
      command -v pacman &>/dev/null || fatal "未找到 pacman。"
      PKG_MANAGER="pacman"
      ;;
    alpine)
      command -v apk &>/dev/null || fatal "未找到 apk。"
      PKG_MANAGER="apk"
      ;;
    suse)
      command -v zypper &>/dev/null || fatal "未找到 zypper。"
      PKG_MANAGER="zypper"
      ;;
  esac
}

detect_country() {
  local country_code=""
  country_code="$(fetch_url_quiet "https://ipinfo.io/country" 2>/dev/null | tr -d '\r\n' || true)"

  if [[ "${country_code}" == "CN" ]]; then
    USE_CHINA_MIRROR=true
  else
    USE_CHINA_MIRROR=false
  fi
}

toolkit_status_header() {
  log "系统: ${OS}, 系列: ${OS_FAMILY}, 版本: ${OS_VERSION_ID:-N/A}, 代号: ${OS_VERSION_CODENAME:-N/A}"
  log "服务管理器: ${INIT_SYSTEM}, 包管理器: ${PKG_MANAGER}, 中国镜像: ${USE_CHINA_MIRROR}"
}
