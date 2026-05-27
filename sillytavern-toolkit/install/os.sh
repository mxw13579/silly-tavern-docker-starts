init_sudo() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    SUDO=()
  else
    command -v sudo &>/dev/null || fatal "sudo 未安装。请使用 root 运行或先安装 sudo。"
    sudo -v &>/dev/null || fatal "当前用户没有 sudo 权限。"
    SUDO=(sudo)
  fi
}

os_like_has() {
  local item="$1"
  [[ " ${OS_LIKE:-} " == *" ${item} "* ]]
}

detect_os() {
  msg_info "正在检测操作系统..."

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
  elif [[ -f /etc/arch-release ]]; then
    OS="arch"
    OS_LIKE=""
  elif [[ -f /etc/alpine-release ]]; then
    OS="alpine"
    OS_LIKE=""
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

  case "${OS_FAMILY}" in
    debian) PKG_MANAGER="apt-get" ;;
    redhat)
      if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      ;;
    arch) PKG_MANAGER="pacman" ;;
    alpine) PKG_MANAGER="apk" ;;
    suse) PKG_MANAGER="zypper" ;;
  esac

  msg_ok "系统: ${OS}, 系列: ${OS_FAMILY}, 包管理器: ${PKG_MANAGER}"
}

detect_country() {
  local country_code=""

  if command -v curl &>/dev/null; then
    country_code="$(curl -fsSL --connect-timeout 10 --max-time 20 --retry 2 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n' || true)"
  elif command -v wget &>/dev/null; then
    country_code="$(wget -qO- --timeout=20 --tries=2 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n' || true)"
  fi

  if [[ "${country_code}" == "CN" ]]; then
    USE_CHINA_MIRROR=true
    msg_ok "检测到服务器位于中国，将使用国内代理下载。"
  else
    USE_CHINA_MIRROR=false
    msg_info "服务器不在中国或检测失败，使用 GitHub。Country: ${country_code:-未知}"
  fi
}

install_dependency() {
  local pkg="$1"
  command -v "${pkg}" &>/dev/null && return 0

  msg_info "安装依赖: ${pkg}"

  case "${PKG_MANAGER}" in
    apt-get)
      "${SUDO[@]}" apt-get update -o Acquire::Retries=3
      "${SUDO[@]}" apt-get install -y "${pkg}"
      ;;
    dnf|yum)
      "${SUDO[@]}" "${PKG_MANAGER}" install -y "${pkg}"
      ;;
    pacman)
      "${SUDO[@]}" pacman -Sy --noconfirm "${pkg}"
      ;;
    apk)
      "${SUDO[@]}" apk add --no-cache "${pkg}"
      ;;
    zypper)
      "${SUDO[@]}" zypper --non-interactive install "${pkg}"
      ;;
    *)
      fatal "无法确定包管理器，请手动安装 ${pkg}。"
      ;;
  esac
}
