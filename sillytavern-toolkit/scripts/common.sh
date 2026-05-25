#!/usr/bin/env bash
set -euo pipefail

# 通用运行时、系统检测与基础工具函数。

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

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

APP_DIR="${APP_DIR:-/data/docker/sillytavern}"
ST_PATH="${APP_DIR}"
ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"

log() { printf '%s\n' "$*"; }
msg_info() { printf '%b[INFO]%b %s\n' "${C_BLUE}" "${C_RESET}" "$*"; }
msg_ok() { printf '%b[OK]%b %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
msg_warn() { printf '%b[WARN]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
msg_error() { printf '%b[ERROR]%b %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
fatal() { msg_error "$*"; exit 1; }
pause_to_continue() { read -r -p "按 [Enter] 键返回..." </dev/tty || true; }

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

run_quiet() {
  local title="$1"
  shift

  local logfile pid frames i
  logfile="$(mktemp "/tmp/st-toolkit-log.XXXXXX")"
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
  fi

  printf '\r%s ❌\n' "${title}"
  log "命令执行失败，日志文件: ${logfile}"
  log "最近日志:"
  tail -n 80 "${logfile}" || true
  return 1
}

fetch_url_quiet() {
  local url="$1"

  if command -v curl &>/dev/null; then
    curl -fsSL --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 1 --retry-connrefused "${url}"
  elif command -v wget &>/dev/null; then
    wget -qO- --timeout=30 --tries=3 "${url}"
  else
    return 1
  fi
}

safe_curl_download() {
  command -v curl &>/dev/null || fatal "curl 不存在，无法下载文件。"
  curl -fL --progress-bar --connect-timeout 10 --max-time 180 --retry 3 --retry-delay 1 --retry-connrefused "$@"
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
  grep -RqsE "aliyun|tuna|ustc|163|tencent|huawei" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
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

  msg_ok "APT 源已完整备份到: ${backup_dir}"
}

backup_main_apt_sources_only() {
  local ts
  ts="$(date +%F_%H%M%S)"

  if [[ -f /etc/apt/sources.list ]]; then
    "${SUDO[@]}" cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.${ts}" || true
    msg_ok "已备份 /etc/apt/sources.list 到 /etc/apt/sources.list.bak.${ts}"
  fi
}

mirror_host_for_provider() {
  local provider="${1:-aliyun}"
  local distro="${2:-debian}"

  case "${provider}:${distro}" in
    aliyun:debian) echo "http://mirrors.aliyun.com/debian" ;;
    aliyun:ubuntu) echo "http://mirrors.aliyun.com/ubuntu" ;;
    tencent:debian) echo "http://mirrors.cloud.tencent.com/debian" ;;
    tencent:ubuntu) echo "http://mirrors.cloud.tencent.com/ubuntu" ;;
    huawei:debian) echo "https://repo.huaweicloud.com/debian" ;;
    huawei:ubuntu) echo "https://repo.huaweicloud.com/ubuntu" ;;
    *) return 1 ;;
  esac
}

write_debian_sources() {
  local codename="$1"
  local components="$2"
  local base_url="$3"
  local security_url="${4:-${base_url}-security}"

  cat <<EOF | "${SUDO[@]}" tee /etc/apt/sources.list >/dev/null
deb ${base_url} ${codename} ${components}
deb ${base_url} ${codename}-updates ${components}
deb ${security_url} ${codename}-security ${components}
EOF
}

write_ubuntu_sources() {
  local codename="$1"
  local base_url="$2"

  cat <<EOF | "${SUDO[@]}" tee /etc/apt/sources.list >/dev/null
deb ${base_url} ${codename} main restricted universe multiverse
deb ${base_url} ${codename}-updates main restricted universe multiverse
deb ${base_url} ${codename}-backports main restricted universe multiverse
deb ${base_url} ${codename}-security main restricted universe multiverse
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

  msg_warn "APT 源不可用，进入自愈流程..."

  local codename components
  codename="$(get_apt_codename)"
  [[ -n "${codename}" ]] || fatal "无法获取系统代号 VERSION_CODENAME。"

  backup_apt_sources_full_for_repair

  if [[ "${OS}" == "debian" ]]; then
    components="$(debian_components)"
    if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
      write_debian_sources "${codename}" "${components}" "http://mirrors.aliyun.com/debian" "http://mirrors.aliyun.com/debian-security"
    else
      write_debian_sources "${codename}" "${components}" "http://deb.debian.org/debian" "http://security.debian.org/debian-security"
    fi
  else
    if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
      write_ubuntu_sources "${codename}" "http://mirrors.aliyun.com/ubuntu"
    else
      write_ubuntu_sources "${codename}" "http://archive.ubuntu.com/ubuntu"
    fi
  fi

  "${SUDO[@]}" rm -rf /var/lib/apt/lists/*
  run_quiet "刷新修复后的 APT 索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3
  apt_has_candidate "ca-certificates" || fatal "APT 源修复后仍不可用。"
}

install_redhat_gnupg_compatible() {
  case "${PKG_MANAGER}" in
    dnf)
      run_quiet "安装 gnupg2" "${SUDO[@]}" dnf install -y gnupg2 && return 0
      run_quiet "安装 gnupg" "${SUDO[@]}" dnf install -y gnupg && return 0
      ;;
    yum)
      run_quiet "安装 gnupg2" "${SUDO[@]}" yum install -y gnupg2 && return 0
      run_quiet "安装 gnupg" "${SUDO[@]}" yum install -y gnupg && return 0
      ;;
  esac

  msg_warn "gnupg/gnupg2 安装失败，但当前 RedHat Docker 安装流程不强依赖该包，继续执行。"
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

detect_compose_cmd() {
  COMPOSE_CMD=()

  if "${SUDO[@]}" docker compose version &>/dev/null; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi

  local compose_bin=""
  compose_bin="$(command -v docker-compose 2>/dev/null || true)"
  if [[ -n "${compose_bin}" ]]; then
    COMPOSE_CMD=("${compose_bin}")
    return 0
  fi

  return 1
}

compose_quiet() {
  local title="$1"
  shift
  run_quiet "${title}" "${SUDO[@]}" "${COMPOSE_CMD[@]}" "$@"
}

read_yes_no() {
  local prompt="$1"
  local result_var="$2"
  local response=""

  while true; do
    read -r -p "${prompt}" response </dev/tty
    case "${response}" in
      [Yy]*) printf -v "${result_var}" "y"; return 0 ;;
      [Nn]*) printf -v "${result_var}" "n"; return 0 ;;
      *) msg_warn "请输入 y 或 n。" ;;
    esac
  done
}

toolkit_status_header() {
  log "系统: ${OS}, 系列: ${OS_FAMILY}, 版本: ${OS_VERSION_ID:-N/A}, 代号: ${OS_VERSION_CODENAME:-N/A}"
  log "服务管理器: ${INIT_SYSTEM}, 包管理器: ${PKG_MANAGER}, 中国镜像: ${USE_CHINA_MIRROR}"
}

init_environment() {
  if [[ "${ST_TOOLKIT_REQUIRE_SUDO:-1}" == "1" ]]; then
    init_sudo
  else
    SUDO=()
  fi

  detect_os
  detect_init_system
  detect_package_manager

  if [[ "${ST_TOOLKIT_SKIP_COUNTRY:-0}" == "1" ]]; then
    USE_CHINA_MIRROR=false
  else
    detect_country
  fi
}

init_environment
