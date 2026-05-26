#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 基础变量
# -----------------------------------------------------------------------------
SUDO=()
OS=""
OS_LIKE=""
OS_FAMILY=""
OS_VERSION_ID=""
OS_VERSION_CODENAME=""
OS_UBUNTU_CODENAME=""
DOCKER_REPO_OS=""
PKG_MANAGER=""
INIT_SYSTEM=""
USE_CHINA_MIRROR=false
COMPOSE_CMD=()
APP_DIR="/data/docker/sillytavern"
ENABLE_EXTERNAL_ACCESS="n"
ENABLE_WATCHTOWER="n"
username=""
password=""

# -----------------------------------------------------------------------------
# 基础函数
# -----------------------------------------------------------------------------
log() { printf '%s\n' "$*"; }
fatal() { printf '错误: %s\n' "$*" >&2; exit 1; }

init_sudo() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    SUDO=()
  else
    command -v sudo &>/dev/null || fatal "sudo 未安装。请使用 root 运行或先安装 sudo。"
    sudo -v &>/dev/null || fatal "当前用户没有 sudo 权限。"
    SUDO=(sudo)
  fi
}

run_quiet() {
  local title="$1"
  shift

  local logfile pid frames i
  logfile="$(mktemp "/tmp/install-log.XXXXXX")"
  frames='|/-\'
  i=0
  pid=""

  printf '%s ' "${title}"

  "$@" >"${logfile}" 2>&1 &
  pid=$!

  cleanup_quiet() {
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
    printf '\n'
    log "已中断，日志文件: ${logfile}"
    exit 130
  }

  trap cleanup_quiet INT TERM

  while kill -0 "${pid}" 2>/dev/null; do
    printf '\r%s %s' "${title}" "${frames:i++%4:1}"
    sleep 0.15
  done

  trap - INT TERM

  if wait "${pid}"; then
    printf '\r%s ✅\n' "${title}"
    rm -f "${logfile}"
    return 0
  else
    printf '\r%s ❌\n' "${title}"
    log "命令执行失败，日志文件: ${logfile}"
    log "最近日志:"
    tail -n 80 "${logfile}" || true
    return 1
  fi
}

fetch_url_quiet() {
  local url="$1"

  if command -v curl &>/dev/null; then
    curl -fsSL \
      --connect-timeout 10 \
      --max-time 30 \
      --retry 3 \
      --retry-delay 1 \
      --retry-connrefused \
      "${url}"
  elif command -v wget &>/dev/null; then
    wget -qO- --timeout=30 --tries=3 "${url}"
  else
    return 1
  fi
}

safe_curl_download() {
  command -v curl &>/dev/null || fatal "curl 不存在，无法下载文件。"

  curl -fL \
    --progress-bar \
    --connect-timeout 10 \
    --max-time 180 \
    --retry 3 \
    --retry-delay 1 \
    --retry-connrefused \
    "$@"
}

is_pure_number() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

generate_random_string() {
  local len="${1:-16}"

  if ! [[ "${len}" =~ ^[0-9]+$ ]] || (( len < 8 )); then
    len=16
  fi

  [[ -r /dev/urandom ]] || fatal "/dev/urandom 不可用，无法生成随机字符串。"

  local out="" chunk="" attempts=0

  while (( ${#out} < len )); do
    chunk="$(head -c 256 /dev/urandom | tr -dc 'A-Za-z0-9' | tr -d '\n')"
    out+="${chunk}"
    attempts=$((attempts + 1))
    (( attempts < 20 )) || fatal "随机字符串生成失败。"
  done

  out="${out:0:len}"
  is_pure_number "${out}" && out="a${out:1}"

  printf '%s' "${out}"
}

validate_credential() {
  local value="${1:-}"

  [[ -n "${value}" ]] || return 1
  [[ ! "${value}" =~ ^[0-9]+$ ]] || return 1
  [[ "${value}" =~ ^[A-Za-z0-9._@-]{3,64}$ ]] || return 1
}

ensure_interactive_tty() {
  [[ -r /dev/tty ]] || fatal "当前环境没有可交互 TTY，无法读取用户输入。请使用 bash script.sh 方式运行。"
}

os_like_has() {
  local item="$1"
  [[ " ${OS_LIKE:-} " == *" ${item} "* ]]
}

# -----------------------------------------------------------------------------
# 系统检测
# -----------------------------------------------------------------------------
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
    debian|ubuntu)
      OS_FAMILY="debian"
      ;;
    centos|rhel|fedora|rocky|almalinux|ol|oracle|centos_stream)
      OS_FAMILY="redhat"
      ;;
    arch|manjaro)
      OS_FAMILY="arch"
      ;;
    alpine)
      OS_FAMILY="alpine"
      ;;
    opensuse-leap|opensuse-tumbleweed|sles|suse)
      OS_FAMILY="suse"
      ;;
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

  log "系统: ${OS}, 系列: ${OS_FAMILY}, 版本: ${OS_VERSION_ID:-N/A}, 代号: ${OS_VERSION_CODENAME:-N/A}"
}

detect_init_system() {
  if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service &>/dev/null || command -v rc-update &>/dev/null; then
    INIT_SYSTEM="openrc"
  else
    INIT_SYSTEM="unknown"
  fi

  log "服务管理器: ${INIT_SYSTEM}"
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

  log "包管理器: ${PKG_MANAGER}"
}

detect_country() {
  log "==> 检测服务器地区..."

  local country_code=""
  country_code="$(fetch_url_quiet "https://ipinfo.io/country" 2>/dev/null | tr -d '\r\n' || true)"

  if [[ "${country_code}" == "CN" ]]; then
    USE_CHINA_MIRROR=true
    log "检测到服务器位于中国，将使用国内镜像。"
  else
    USE_CHINA_MIRROR=false
    log "服务器不在中国或检测失败，使用官方源。Country: ${country_code:-未知}"
  fi
}

# -----------------------------------------------------------------------------
# APT 源处理
# -----------------------------------------------------------------------------
debian_components() {
  local components="main contrib non-free"

  if [[ "${OS}" == "debian" ]]; then
    local major="${OS_VERSION_ID%%.*}"
    if [[ "${major}" =~ ^[0-9]+$ ]] && (( major >= 12 )); then
      components="main contrib non-free non-free-firmware"
    fi
  fi

  printf '%s' "${components}"
}

guess_debian_codename_from_version() {
  local dv=""
  dv="$(cat /etc/debian_version 2>/dev/null || true)"

  case "${dv}" in
    13*) echo "trixie" ;;
    12*) echo "bookworm" ;;
    11*) echo "bullseye" ;;
    10*) echo "buster" ;;
    9*) echo "stretch" ;;
    *) echo "" ;;
  esac
}

get_apt_codename() {
  local codename="${OS_VERSION_CODENAME:-}"

  if [[ -z "${codename}" && "${OS}" == "debian" ]]; then
    codename="$(guess_debian_codename_from_version)"
  fi

  if [[ -z "${codename}" ]]; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi

  printf '%s' "${codename}"
}

get_docker_apt_codename() {
  local codename=""

  if [[ "${DOCKER_REPO_OS}" == "ubuntu" && -n "${OS_UBUNTU_CODENAME}" ]]; then
    codename="${OS_UBUNTU_CODENAME}"
  else
    codename="${OS_VERSION_CODENAME:-}"
  fi

  if [[ -z "${codename}" ]]; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi

  printf '%s' "${codename}"
}

apt_has_candidate() {
  local pkg="${1:-}"
  [[ -n "${pkg}" ]] || return 1
  command -v apt-cache &>/dev/null || return 0

  local candidate=""
  candidate="$(apt-cache policy "${pkg}" 2>/dev/null | sed -n 's/^[[:space:]]*Candidate: //p' | tail -n 1 || true)"
  [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

apt_sources_already_china_mirror() {
  grep -RqsE "aliyun|tuna|ustc|163|tencent|huawei" \
    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
}

backup_apt_sources_full_for_repair() {
  local ts backup_dir
  ts="$(date +%F_%H%M%S)"
  backup_dir="/etc/apt/sources.backup.${ts}"

  "${SUDO[@]}" mkdir -p "${backup_dir}"

  [[ -f /etc/apt/sources.list ]] && "${SUDO[@]}" cp -a /etc/apt/sources.list "${backup_dir}/sources.list" || true

  if [[ -d /etc/apt/sources.list.d ]]; then
    "${SUDO[@]}" mkdir -p "${backup_dir}/sources.list.d"
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
      [[ -e "${f}" ]] || continue
      "${SUDO[@]}" mv -f "${f}" "${backup_dir}/sources.list.d/" || true
    done
  fi

  log "APT 源已完整备份到: ${backup_dir}"
}

backup_main_apt_sources_only() {
  local ts
  ts="$(date +%F_%H%M%S)"

  if [[ -f /etc/apt/sources.list ]]; then
    "${SUDO[@]}" cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.${ts}" || true
    log "已备份 /etc/apt/sources.list 到 /etc/apt/sources.list.bak.${ts}"
  fi
}

write_debian_china_sources() {
  local codename="$1"
  local components="$2"

  cat <<EOF | "${SUDO[@]}" tee /etc/apt/sources.list >/dev/null
deb http://mirrors.aliyun.com/debian ${codename} ${components}
deb http://mirrors.aliyun.com/debian ${codename}-updates ${components}
deb http://mirrors.aliyun.com/debian-security ${codename}-security ${components}
EOF
}

write_ubuntu_china_sources() {
  local codename="$1"

  cat <<EOF | "${SUDO[@]}" tee /etc/apt/sources.list >/dev/null
deb http://mirrors.aliyun.com/ubuntu ${codename} main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu ${codename}-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
}

write_debian_official_sources() {
  local codename="$1"
  local components="$2"

  cat <<EOF | "${SUDO[@]}" tee /etc/apt/sources.list >/dev/null
deb http://deb.debian.org/debian ${codename} ${components}
deb http://deb.debian.org/debian ${codename}-updates ${components}
deb http://security.debian.org/debian-security ${codename}-security ${components}
EOF
}

write_ubuntu_official_sources() {
  local codename="$1"

  cat <<EOF | "${SUDO[@]}" tee /etc/apt/sources.list >/dev/null
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-backports main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
}

ensure_apt_ready_debian() {
  [[ "${OS_FAMILY}" == "debian" ]] || return 0

  if run_quiet "检测 APT 索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3; then
    if apt_has_candidate "ca-certificates"; then
      return 0
    fi
  fi

  if [[ "${OS}" != "debian" && "${OS}" != "ubuntu" ]]; then
    fatal "APT 源不可用，且当前为 Debian/Ubuntu 衍生系统 ${OS}，为避免误改系统源，已停止。请先修复软件源。"
  fi

  log "APT 源不可用，进入自愈流程..."

  local codename components
  codename="$(get_apt_codename)"
  [[ -n "${codename}" ]] || fatal "无法获取系统代号 VERSION_CODENAME。"

  backup_apt_sources_full_for_repair

  if [[ "${OS}" == "debian" ]]; then
    components="$(debian_components)"
    if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
      write_debian_china_sources "${codename}" "${components}"
    else
      write_debian_official_sources "${codename}" "${components}"
    fi
  else
    if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
      write_ubuntu_china_sources "${codename}"
    else
      write_ubuntu_official_sources "${codename}"
    fi
  fi

  "${SUDO[@]}" rm -rf /var/lib/apt/lists/*

  run_quiet "刷新修复后的 APT 索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3
  apt_has_candidate "ca-certificates" || fatal "APT 源修复后仍不可用。"
}

# -----------------------------------------------------------------------------
# 系统镜像源
# -----------------------------------------------------------------------------
configure_system_mirrors() {
  [[ "${USE_CHINA_MIRROR}" == "true" ]] || {
    log "跳过系统镜像源配置。"
    return 0
  }

  log "==> 配置系统镜像源..."

  case "${OS_FAMILY}" in
    debian)
      if [[ "${OS}" != "debian" && "${OS}" != "ubuntu" ]]; then
        log "检测到 Debian/Ubuntu 衍生系统 ${OS}，为避免误改系统源，跳过系统源替换。"
        return 0
      fi

      if apt_sources_already_china_mirror; then
        log "检测到已有国内 APT 镜像源，跳过系统源替换，仅刷新索引。"
        run_quiet "刷新 APT 镜像索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3
        return 0
      fi

      local codename components
      codename="$(get_apt_codename)"
      [[ -n "${codename}" ]] || fatal "无法获取系统代号 VERSION_CODENAME。"

      backup_main_apt_sources_only

      if [[ "${OS}" == "debian" ]]; then
        components="$(debian_components)"
        write_debian_china_sources "${codename}" "${components}"
      else
        write_ubuntu_china_sources "${codename}"
      fi

      "${SUDO[@]}" rm -rf /var/lib/apt/lists/*
      run_quiet "刷新 APT 镜像索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3
      ;;
    arch)
      if ! grep -q "mirrors.tuna.tsinghua.edu.cn" /etc/pacman.d/mirrorlist 2>/dev/null; then
        "${SUDO[@]}" cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak || true
        "${SUDO[@]}" sed -i '1s|^|Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch\n|' /etc/pacman.d/mirrorlist
      fi
      run_quiet "刷新 Pacman 镜像索引" "${SUDO[@]}" pacman -Syy --noconfirm
      ;;
    alpine)
      if ! grep -q "mirrors.aliyun.com" /etc/apk/repositories 2>/dev/null; then
        "${SUDO[@]}" cp -a /etc/apk/repositories /etc/apk/repositories.bak || true
        "${SUDO[@]}" sed -i 's|https://dl-cdn.alpinelinux.org|https://mirrors.aliyun.com|g' /etc/apk/repositories
        "${SUDO[@]}" sed -i 's|http://dl-cdn.alpinelinux.org|https://mirrors.aliyun.com|g' /etc/apk/repositories
      fi
      run_quiet "刷新 APK 镜像索引" "${SUDO[@]}" apk update
      ;;
    redhat|suse)
      log "为避免破坏企业源，${OS} 暂不自动替换系统源，仅 Docker 源使用镜像。"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# 基础依赖
# -----------------------------------------------------------------------------
install_redhat_gnupg_compatible() {
  case "${PKG_MANAGER}" in
    dnf)
      if run_quiet "安装 gnupg2" "${SUDO[@]}" dnf install -y gnupg2; then
        return 0
      fi

      if run_quiet "安装 gnupg" "${SUDO[@]}" dnf install -y gnupg; then
        return 0
      fi
      ;;
    yum)
      if run_quiet "安装 gnupg2" "${SUDO[@]}" yum install -y gnupg2; then
        return 0
      fi

      if run_quiet "安装 gnupg" "${SUDO[@]}" yum install -y gnupg; then
        return 0
      fi
      ;;
  esac

  log "警告: gnupg/gnupg2 均安装失败，但当前 RedHat Docker 安装流程不强依赖该包，继续执行。"
  return 0
}

install_base_packages() {
  case "${PKG_MANAGER}" in
    apt)
      ensure_apt_ready_debian
      run_quiet "安装基础依赖" "${SUDO[@]}" apt-get install -y ca-certificates curl gnupg lsb-release
      ;;
    dnf)
      run_quiet "安装基础依赖" "${SUDO[@]}" dnf install -y ca-certificates curl dnf-plugins-core
      install_redhat_gnupg_compatible
      ;;
    yum)
      run_quiet "安装基础依赖" "${SUDO[@]}" yum install -y ca-certificates curl yum-utils
      install_redhat_gnupg_compatible
      ;;
    pacman)
      run_quiet "安装基础依赖" "${SUDO[@]}" pacman -Sy --noconfirm curl ca-certificates gnupg
      ;;
    apk)
      run_quiet "安装基础依赖" "${SUDO[@]}" apk add --no-cache curl ca-certificates gnupg
      ;;
    zypper)
      if ! run_quiet "安装基础依赖" "${SUDO[@]}" zypper --non-interactive install curl ca-certificates gpg2; then
        run_quiet "安装基础依赖" "${SUDO[@]}" zypper --non-interactive install curl ca-certificates gnupg
      fi
      ;;
  esac
}

ensure_python3_available() {
  if command -v python3 &>/dev/null; then
    return 0
  fi

  log "未检测到 python3，尝试安装 python3 以安全处理 Docker JSON 配置..."

  case "${PKG_MANAGER}" in
    apt)
      ensure_apt_ready_debian
      run_quiet "安装 python3" "${SUDO[@]}" apt-get install -y python3 || return 1
      ;;
    dnf)
      run_quiet "安装 python3" "${SUDO[@]}" dnf install -y python3 || return 1
      ;;
    yum)
      run_quiet "安装 python3" "${SUDO[@]}" yum install -y python3 || return 1
      ;;
    pacman)
      run_quiet "安装 python3" "${SUDO[@]}" pacman -Sy --noconfirm python || return 1
      ;;
    apk)
      run_quiet "安装 python3" "${SUDO[@]}" apk add --no-cache python3 || return 1
      ;;
    zypper)
      run_quiet "安装 python3" "${SUDO[@]}" zypper --non-interactive install python3 || return 1
      ;;
    *)
      return 1
      ;;
  esac

  command -v python3 &>/dev/null
}

# -----------------------------------------------------------------------------
# Docker 安装
# -----------------------------------------------------------------------------
install_docker_debian_fallback() {
  log "尝试使用系统源安装 Docker 作为兜底方案..."

  "${SUDO[@]}" rm -f /etc/apt/sources.list.d/docker.list || true
  ensure_apt_ready_debian

  if run_quiet "安装系统源 Docker" "${SUDO[@]}" apt-get install -y docker.io docker-compose-plugin; then
    return 0
  fi

  if run_quiet "安装系统源 Docker 与 docker-compose" "${SUDO[@]}" apt-get install -y docker.io docker-compose; then
    return 0
  fi

  fatal "Docker 官方源和系统源安装均失败。"
}

install_docker_debian() {
  log "==> 安装 Docker..."

  install_base_packages

  local docker_repo_url="https://download.docker.com"
  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    docker_repo_url="https://mirrors.cloud.tencent.com/docker-ce"
  fi

  run_quiet "移除旧 Docker 包" "${SUDO[@]}" apt-get remove -y docker docker-engine docker.io containerd runc || true

  "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
  "${SUDO[@]}" rm -f /etc/apt/keyrings/docker.gpg

  local tmp_gpg codename
  tmp_gpg="$(mktemp)"

  if ! fetch_url_quiet "${docker_repo_url}/linux/${DOCKER_REPO_OS}/gpg" >"${tmp_gpg}"; then
    rm -f "${tmp_gpg}"
    install_docker_debian_fallback
    return 0
  fi

  if ! "${SUDO[@]}" gpg --dearmor -o /etc/apt/keyrings/docker.gpg "${tmp_gpg}" >/dev/null 2>&1; then
    rm -f "${tmp_gpg}"
    install_docker_debian_fallback
    return 0
  fi

  rm -f "${tmp_gpg}"
  "${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.gpg

  codename="$(get_docker_apt_codename)"
  [[ -n "${codename}" ]] || {
    install_docker_debian_fallback
    return 0
  }

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${docker_repo_url}/linux/${DOCKER_REPO_OS} ${codename} stable" \
    | "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null

  if ! run_quiet "刷新 Docker APT 源" "${SUDO[@]}" apt-get update -o Acquire::Retries=3; then
    install_docker_debian_fallback
    return 0
  fi

  if ! run_quiet "安装 Docker" "${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    install_docker_debian_fallback
    return 0
  fi
}

install_docker_redhat_fallback() {
  log "尝试使用系统源安装 Docker 作为兜底方案..."

  "${SUDO[@]}" rm -f /etc/yum.repos.d/docker-ce.repo || true
  run_quiet "刷新软件源缓存" "${SUDO[@]}" "${PKG_MANAGER}" makecache || true

  if run_quiet "安装系统源 Docker" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker docker-compose-plugin; then
    return 0
  fi

  if run_quiet "安装系统源 Docker 与 docker-compose" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker docker-compose; then
    return 0
  fi

  fatal "Docker 官方源和系统源安装均失败。"
}

install_docker_redhat() {
  log "==> 安装 Docker..."

  install_base_packages

  local repo_url=""

  case "${OS}" in
    fedora)
      repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
      [[ "${USE_CHINA_MIRROR}" == "true" ]] && repo_url="https://mirrors.cloud.tencent.com/docker-ce/linux/fedora/docker-ce.repo"
      ;;
    *)
      repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
      [[ "${USE_CHINA_MIRROR}" == "true" ]] && repo_url="https://mirrors.cloud.tencent.com/docker-ce/linux/centos/docker-ce.repo"
      ;;
  esac

  run_quiet "移除旧 Docker 包" "${SUDO[@]}" "${PKG_MANAGER}" remove -y \
    docker docker-client docker-client-latest docker-common docker-latest \
    docker-latest-logrotate docker-logrotate docker-engine || true

  local tmp_repo
  tmp_repo="$(mktemp)"

  if ! safe_curl_download -o "${tmp_repo}" "${repo_url}"; then
    rm -f "${tmp_repo}"
    install_docker_redhat_fallback
    return 0
  fi

  "${SUDO[@]}" mkdir -p /etc/yum.repos.d
  "${SUDO[@]}" cp "${tmp_repo}" /etc/yum.repos.d/docker-ce.repo
  rm -f "${tmp_repo}"

  if ! run_quiet "刷新 Docker 软件源缓存" "${SUDO[@]}" "${PKG_MANAGER}" makecache; then
    install_docker_redhat_fallback
    return 0
  fi

  if ! run_quiet "安装 Docker" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    install_docker_redhat_fallback
    return 0
  fi
}

install_docker_arch() {
  install_base_packages
  run_quiet "安装 Docker" "${SUDO[@]}" pacman -S --noconfirm docker docker-compose
}

install_docker_alpine() {
  install_base_packages

  if ! run_quiet "安装 Docker" "${SUDO[@]}" apk add --no-cache docker docker-cli-compose; then
    run_quiet "安装 Docker" "${SUDO[@]}" apk add --no-cache docker docker-compose
  fi
}

install_docker_suse() {
  install_base_packages
  run_quiet "安装 Docker" "${SUDO[@]}" zypper --non-interactive install docker docker-compose
}

ensure_docker_running() {
  if "${SUDO[@]}" docker info &>/dev/null; then
    return 0
  fi

  case "${INIT_SYSTEM}" in
    systemd)
      run_quiet "启动 Docker 服务" "${SUDO[@]}" systemctl enable --now docker || fatal "Docker 启动失败。"
      ;;
    openrc)
      "${SUDO[@]}" rc-update add docker boot || true
      run_quiet "启动 Docker 服务" "${SUDO[@]}" rc-service docker start || fatal "Docker 启动失败。"
      ;;
    *)
      fatal "当前环境没有 systemd/openrc，且 Docker 未运行。请手动启动 Docker 后重试。"
      ;;
  esac

  "${SUDO[@]}" docker info &>/dev/null || fatal "Docker 未正常运行。"
}

restart_docker_service_if_possible() {
  case "${INIT_SYSTEM}" in
    systemd)
      "${SUDO[@]}" systemctl daemon-reload || true
      run_quiet "重启 Docker 服务" "${SUDO[@]}" systemctl restart docker
      ;;
    openrc)
      run_quiet "重启 Docker 服务" "${SUDO[@]}" rc-service docker restart
      ;;
    *)
      log "警告: 当前环境没有 systemd/openrc，无法自动重启 Docker。"
      log "请手动重启 Docker 后继续。"
      ;;
  esac
}

configure_docker_mirror_safe() {
  log "==> 检查 Docker 镜像加速配置..."

  local daemon_json="/etc/docker/daemon.json"
  local backup_file=""
  local need_restart="false"

  "${SUDO[@]}" mkdir -p /etc/docker

  if [[ -f "${daemon_json}" ]] && grep -qsE "mirror\.ccs\.tencentyun\.com" "${daemon_json}"; then
    backup_file="/etc/docker/daemon.json.bak.$(date +%F_%H%M%S)"
    "${SUDO[@]}" cp -a "${daemon_json}" "${backup_file}" || true

    log "检测到失效 Docker Hub 镜像加速地址 mirror.ccs.tencentyun.com，正在清理..."
    log "原配置已备份到: ${backup_file}"

    if ensure_python3_available; then
      "${SUDO[@]}" python3 <<'PY'
import json
from pathlib import Path

path = Path("/etc/docker/daemon.json")
bad_mirrors = {
    "https://mirror.ccs.tencentyun.com",
    "http://mirror.ccs.tencentyun.com",
}

if not path.exists() or not path.read_text().strip():
    path.write_text("{}\n")
    raise SystemExit(0)

try:
    data = json.loads(path.read_text())
except Exception:
    invalid_backup = Path("/etc/docker/daemon.json.invalid")
    invalid_backup.write_text(path.read_text())
    path.write_text("{}\n")
    raise SystemExit(0)

if not isinstance(data, dict):
    path.write_text("{}\n")
    raise SystemExit(0)

mirrors = data.get("registry-mirrors")

if isinstance(mirrors, list):
    mirrors = [m for m in mirrors if m not in bad_mirrors]
    if mirrors:
        data["registry-mirrors"] = mirrors
    else:
        data.pop("registry-mirrors", None)

path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
    else
      log "警告: python3 不可用，无法安全合并 JSON。"
      log "为避免 Docker 继续使用失效镜像源，已备份原配置并写入最小 Docker 配置。"
      printf '{}\n' | "${SUDO[@]}" tee "${daemon_json}" >/dev/null
    fi

    need_restart="true"
  fi

  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    log "国内环境已启用专用镜像地址。"
    log "跳过 Docker Hub registry-mirrors 自动配置，避免写入失效或不稳定镜像源。"
  else
    log "非国内环境，跳过 Docker Hub 镜像加速配置。"
  fi

  if [[ "${need_restart}" == "true" ]]; then
    restart_docker_service_if_possible
  fi
}

install_or_verify_docker() {
  log "==> 检查 Docker..."

  if ! command -v docker &>/dev/null; then
    case "${OS_FAMILY}" in
      debian) install_docker_debian ;;
      redhat) install_docker_redhat ;;
      arch) install_docker_arch ;;
      alpine) install_docker_alpine ;;
      suse) install_docker_suse ;;
      *) fatal "不支持的系统系列: ${OS_FAMILY}" ;;
    esac
  else
    log "Docker 已安装，跳过安装。"
  fi

  command -v docker &>/dev/null || fatal "Docker 安装失败。"

  ensure_docker_running
  configure_docker_mirror_safe
  ensure_docker_running
}

# -----------------------------------------------------------------------------
# Docker Compose
# -----------------------------------------------------------------------------
setup_docker_compose() {
  log "==> 检查 Docker Compose..."

  if "${SUDO[@]}" docker compose version &>/dev/null; then
    COMPOSE_CMD=(docker compose)
    log "检测到 Docker Compose Plugin。"
    return 0
  fi

  local compose_bin=""
  compose_bin="$(command -v docker-compose 2>/dev/null || true)"

  if [[ -n "${compose_bin}" ]]; then
    COMPOSE_CMD=("${compose_bin}")
    log "检测到 docker-compose: ${compose_bin}"
    return 0
  fi

  log "未检测到 Docker Compose，尝试安装..."

  case "${OS_FAMILY}" in
    debian)
      ensure_apt_ready_debian
      if ! run_quiet "安装 Docker Compose 插件" "${SUDO[@]}" apt-get install -y docker-compose-plugin; then
        run_quiet "安装 docker-compose" "${SUDO[@]}" apt-get install -y docker-compose
      fi
      ;;
    redhat)
      run_quiet "安装 Docker Compose 插件" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker-compose-plugin
      ;;
    arch)
      run_quiet "安装 Docker Compose" "${SUDO[@]}" pacman -S --noconfirm docker-compose
      ;;
    alpine)
      if ! run_quiet "安装 Docker Compose" "${SUDO[@]}" apk add --no-cache docker-cli-compose; then
        run_quiet "安装 Docker Compose" "${SUDO[@]}" apk add --no-cache docker-compose
      fi
      ;;
    suse)
      run_quiet "安装 Docker Compose" "${SUDO[@]}" zypper --non-interactive install docker-compose
      ;;
  esac

  if "${SUDO[@]}" docker compose version &>/dev/null; then
    COMPOSE_CMD=(docker compose)
  else
    compose_bin="$(command -v docker-compose 2>/dev/null || true)"
    [[ -n "${compose_bin}" ]] || fatal "Docker Compose 安装失败。"
    COMPOSE_CMD=("${compose_bin}")
  fi

  log "Compose 命令: ${COMPOSE_CMD[*]}"
}

compose_quiet() {
  local title="$1"
  shift

  run_quiet "${title}" "${SUDO[@]}" "${COMPOSE_CMD[@]}" "$@"
}

# -----------------------------------------------------------------------------
# SillyTavern 配置
# -----------------------------------------------------------------------------
read_yes_no() {
  local prompt="$1"
  local result_var="$2"
  local response=""

  while true; do
    read -r -p "${prompt}" response </dev/tty
    case "${response}" in
      [Yy]*) printf -v "${result_var}" "y"; return 0 ;;
      [Nn]*) printf -v "${result_var}" "n"; return 0 ;;
      *) log "请输入 y 或 n。" ;;
    esac
  done
}

read_safe_username() {
  local input=""

  while true; do
    read -r -p "请输入用户名，仅允许 A-Z、a-z、0-9、.、_、@、-，不能为纯数字: " input </dev/tty
    if validate_credential "${input}"; then
      username="${input}"
      return 0
    fi
    log "用户名格式错误，长度 3-64 位，且不能为纯数字。"
  done
}

read_safe_password() {
  local input=""

  while true; do
    read -r -s -p "请输入密码，仅允许 A-Z、a-z、0-9、.、_、@、-，不能为纯数字: " input </dev/tty
    printf '\n'
    if validate_credential "${input}"; then
      password="${input}"
      return 0
    fi
    log "密码格式错误，长度 3-64 位，且不能为纯数字。"
  done
}

confirm_watchtower() {
  ENABLE_WATCHTOWER="n"

  log "--------------------------------------------------"
  log "Watchtower 可自动更新容器。"
  log "警告: Watchtower 需要挂载 /var/run/docker.sock。"
  log "警告: Docker socket 具有较高权限，容器一旦被攻击可能影响宿主机 Docker 环境。"
  log "默认建议不启用，除非你明确接受该风险。"
  read_yes_no "是否启用 Watchtower 自动更新？(y/n): " ENABLE_WATCHTOWER
}

prepare_app_dirs() {
  "${SUDO[@]}" mkdir -p \
    "${APP_DIR}/plugins" \
    "${APP_DIR}/config" \
    "${APP_DIR}/data" \
    "${APP_DIR}/extensions"

  "${SUDO[@]}" chown -R 1000:1000 \
    "${APP_DIR}/plugins" \
    "${APP_DIR}/config" \
    "${APP_DIR}/data" \
    "${APP_DIR}/extensions" || true
}

write_sillytavern_config() {
  local enable_external_access="$1"
  local config_username="${2:-}"
  local config_password="${3:-}"

  if [[ "${enable_external_access}" == "y" ]]; then
    validate_credential "${config_username}" || fatal "用户名格式非法。"
    validate_credential "${config_password}" || fatal "密码格式非法。"
  fi

  "${SUDO[@]}" mkdir -p "${APP_DIR}/config"

  if [[ "${enable_external_access}" == "y" ]]; then
    cat <<EOF | "${SUDO[@]}" tee "${APP_DIR}/config/config.yaml" >/dev/null
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
basicAuthMode: true
basicAuthUser:
  username: "${config_username}"
  password: "${config_password}"
EOF
  else
    cat <<'EOF' | "${SUDO[@]}" tee "${APP_DIR}/config/config.yaml" >/dev/null
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
enableForwardedWhitelist: false
whitelist:
  - ::1
  - 127.0.0.1
basicAuthMode: false
basicAuthUser:
  username: ""
  password: ""
EOF
  fi

  "${SUDO[@]}" chown -R 1000:1000 "${APP_DIR}/config" || true
}

generate_compose_file() {
  local enable_external_access="$1"
  local enable_watchtower="${2:-n}"
  local bind_host="127.0.0.1"

  if [[ "${enable_external_access}" == "y" ]]; then
    bind_host="0.0.0.0"
  fi

  local sillytavern_image="ghcr.io/sillytavern/sillytavern:latest"
  local watchtower_image="containrrr/watchtower:latest"

  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    sillytavern_image="ghcr.nju.edu.cn/sillytavern/sillytavern:latest"
    watchtower_image="ghcr.nju.edu.cn/containrrr/watchtower:latest"
  fi

  prepare_app_dirs

  cat <<EOF | "${SUDO[@]}" tee "${APP_DIR}/docker-compose.yaml" >/dev/null
services:
  sillytavern:
    image: ${sillytavern_image}
    ports:
      - "${bind_host}:8000:8000"
    volumes:
      - ./plugins:/home/node/app/plugins:rw
      - ./config:/home/node/app/config:rw
      - ./data:/home/node/app/data:rw
      - ./extensions:/home/node/app/public/scripts/extensions/third-party:rw
    restart: always
EOF

  if [[ "${enable_watchtower}" == "y" ]]; then
    cat <<EOF | "${SUDO[@]}" tee -a "${APP_DIR}/docker-compose.yaml" >/dev/null
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  watchtower:
    image: ${watchtower_image}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400 --cleanup --label-enable
    restart: always
EOF
  fi

  log "SillyTavern 镜像: ${sillytavern_image}"

  if [[ "${enable_watchtower}" == "y" ]]; then
    log "Watchtower 镜像: ${watchtower_image}"
  else
    log "Watchtower 未启用。"
  fi
}

configure_sillytavern_interactive() {
  ensure_interactive_tty

  log "==> 配置 SillyTavern..."
  log "请选择是否开启外网访问。"
  log "不开启时仅监听 127.0.0.1:8000。"
  log "开启时监听 0.0.0.0:8000，并强制配置用户名密码。"

  ENABLE_EXTERNAL_ACCESS="n"
  read_yes_no "是否开启外网访问？(y/n): " ENABLE_EXTERNAL_ACCESS

  username=""
  password=""

  confirm_watchtower
  generate_compose_file "${ENABLE_EXTERNAL_ACCESS}" "${ENABLE_WATCHTOWER}"

  if [[ "${ENABLE_EXTERNAL_ACCESS}" == "y" ]]; then
    log "请选择用户名密码生成方式:"
    log "1. 随机生成"
    log "2. 手动输入"

    local choice=""

    while true; do
      read -r -p "请输入选择 (1/2): " choice </dev/tty
      case "${choice}" in
        1)
          username="$(generate_random_string 16)"
          password="$(generate_random_string 20)"
          log "已生成随机用户名: ${username}"
          log "已生成随机密码: ${password}"
          break
          ;;
        2)
          read_safe_username
          read_safe_password
          break
          ;;
        *)
          log "请输入 1 或 2。"
          ;;
      esac
    done

    write_sillytavern_config "y" "${username}" "${password}"
    log "已开启外网访问并配置 Basic Auth。"
  else
    write_sillytavern_config "n"
    log "未开启外网访问，仅允许本机访问端口。"
  fi

  prepare_app_dirs
}

print_final_info() {
  local public_ip=""
  local ssh_user="root"

  public_ip="$(fetch_url_quiet "https://ipinfo.io/ip" 2>/dev/null | tr -d '\r\n' || true)"
  [[ -n "${public_ip}" ]] || public_ip="<你的服务器公网IP>"

  if [[ -n "${SUDO_USER:-}" ]]; then
    ssh_user="${SUDO_USER}"
  elif [[ -n "${USER:-}" ]]; then
    ssh_user="${USER}"
  fi

  log "--------------------------------------------------"
  log "✅ SillyTavern 已成功部署！"
  log "--------------------------------------------------"

  if [[ "${ENABLE_EXTERNAL_ACCESS}" == "y" ]]; then
    log "访问地址: http://${public_ip}:8000"
    log "用户名: ${username}"
    log "密码: ${password}"
  else
    log "本机访问地址: http://127.0.0.1:8000"
    log "外网访问未开启。"
    log "如需远程访问，可使用 SSH 隧道："
    log "ssh -L 8000:127.0.0.1:8000 ${ssh_user}@${public_ip}"
    log "然后在本地浏览器打开: http://127.0.0.1:8000"
  fi

  if [[ "${ENABLE_WATCHTOWER}" == "y" ]]; then
    log "Watchtower 自动更新: 已启用"
  else
    log "Watchtower 自动更新: 未启用"
  fi

  log "--------------------------------------------------"
  log "部署目录: ${APP_DIR}"
  log "Compose 文件: ${APP_DIR}/docker-compose.yaml"
  log "--------------------------------------------------"
}

# -----------------------------------------------------------------------------
# 主流程
# -----------------------------------------------------------------------------
main() {
  init_sudo
  detect_os
  detect_init_system
  detect_package_manager
  detect_country

  configure_system_mirrors
  install_or_verify_docker
  setup_docker_compose
  configure_sillytavern_interactive

  cd "${APP_DIR}"

  log "==> 拉取镜像并启动服务..."
  compose_quiet "拉取 Docker 镜像" pull
  compose_quiet "启动 SillyTavern 服务" up -d

  clear || true
  print_final_info
}

main "$@"
