#!/usr/bin/env bash
set -euo pipefail

# SillyTavern Toolkit 安装/更新程序。

REPO_USER="mxw13579"
REPO_NAME="silly-tavern-docker-starts"
REPO_PATH="sillytavern-toolkit"
BRANCH="main"
TOOLKIT_DIR="${TOOLKIT_DIR:-${HOME}/sillytavern-toolkit}"
LAUNCH_TOOLKIT=true
ASSUME_YES=false

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'

msg_info() { printf '%b[INFO]%b %s\n' "${C_BLUE}" "${C_RESET}" "$*"; }
msg_ok() { printf '%b[OK]%b %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
msg_warn() { printf '%b[WARN]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
fatal() { printf '%b[ERROR]%b %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }

SUDO=()
OS=""
OS_FAMILY=""
PKG_MANAGER=""
USE_CHINA_MIRROR=false

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --no-launch)
        LAUNCH_TOOLKIT=false
        ;;
      -y|--yes)
        ASSUME_YES=true
        ;;
      -h|--help)
        echo "用法: $0 [--no-launch] [--yes]"
        exit 0
        ;;
      *)
        fatal "未知参数: $1"
        ;;
    esac
    shift
  done
}

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

backup_existing_toolkit() {
  [[ -e "${TOOLKIT_DIR}" ]] || return 0

  local backup_dir
  backup_dir="${TOOLKIT_DIR}.bak_$(date +%Y%m%d_%H%M%S)"
  msg_warn "检测到已存在的工具箱目录，将备份为: ${backup_dir}"
  mv "${TOOLKIT_DIR}" "${backup_dir}"
}

confirm_proxy_download() {
  if [[ "${ASSUME_YES}" == "true" ]]; then
    return 0
  fi

  msg_warn "中国区安装将通过第三方代理 ghfast.top 下载脚本文件。"
  msg_warn "该方式可改善 GitHub 访问，但存在代理服务可用性和供应链信任风险。"

  if [[ ! -r /dev/tty ]]; then
    fatal "当前环境非交互。请改用 GitHub 直连，或显式传入 --yes 接受代理下载风险。"
  fi

  local answer=""
  read -r -p "是否继续通过 ghfast.top 下载？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*) return 0 ;;
    *) fatal "已取消安装。" ;;
  esac
}

install_from_proxy() {
  install_dependency "curl"
  confirm_proxy_download

  local proxy_url base_url temp_dir
  proxy_url="https://ghfast.top"
  base_url="${proxy_url}/https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/${REPO_PATH}"
  temp_dir="$(mktemp -d)"

  cleanup_proxy_tmp() {
    rm -rf "${temp_dir}"
  }
  trap cleanup_proxy_tmp RETURN

  local files=(
    "install.sh"
    "st-toolkit.sh"
    "scripts/common.sh"
    "scripts/docker.sh"
    "scripts/sillytavern.sh"
    "scripts/sources.sh"
  )

  mkdir -p "${temp_dir}/scripts"

  local file
  for file in "${files[@]}"; do
    msg_info "下载: ${file}"
    curl -fsSL --connect-timeout 10 --max-time 180 --retry 3 --retry-delay 1 \
      "${base_url}/${file}" -o "${temp_dir}/${file}"
  done

  backup_existing_toolkit
  mv "${temp_dir}" "${TOOLKIT_DIR}"
  trap - RETURN
}

install_from_git() {
  install_dependency "git"
  backup_existing_toolkit

  local temp_dir repo_git_url
  temp_dir="$(mktemp -d)"
  repo_git_url="https://github.com/${REPO_USER}/${REPO_NAME}.git"

  cleanup() {
    rm -rf "${temp_dir}"
  }
  trap cleanup EXIT

  msg_info "正在从 GitHub 克隆仓库..."
  git clone --depth 1 "${repo_git_url}" "${temp_dir}"

  [[ -d "${temp_dir}/${REPO_PATH}" ]] || fatal "仓库中未找到 ${REPO_PATH}。"
  mv "${temp_dir}/${REPO_PATH}" "${TOOLKIT_DIR}"
}

main() {
  parse_args "$@"

  msg_info "================================================="
  msg_info "== 欢迎使用 SillyTavern Docker 工具箱安装程序 =="
  msg_info "================================================="

  init_sudo
  detect_os

  if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    install_dependency "curl"
  fi

  detect_country

  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    install_from_proxy
  else
    install_from_git
  fi

  chmod +x "${TOOLKIT_DIR}/st-toolkit.sh" "${TOOLKIT_DIR}"/scripts/*.sh

  echo
  msg_ok "工具箱已成功安装/更新。"
  echo "启动命令:"
  echo "  cd \"${TOOLKIT_DIR}\" && ./st-toolkit.sh"
  echo

  if [[ "${LAUNCH_TOOLKIT}" == "true" ]]; then
    cd "${TOOLKIT_DIR}"
    ./st-toolkit.sh
  fi
}

main "$@"
