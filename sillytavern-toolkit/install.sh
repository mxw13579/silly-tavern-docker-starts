#!/usr/bin/env bash
set -euo pipefail

# SillyTavern Toolkit 安装/更新程序。

REPO_USER="mxw13579"
REPO_NAME="silly-tavern-docker-starts"
REPO_PATH="sillytavern-toolkit"
BRANCH="main"
TOOLKIT_REF="${ST_TOOLKIT_REF:-${BRANCH}}"
TOOLKIT_DIR="${TOOLKIT_DIR:-${HOME}/sillytavern-toolkit}"
LAUNCH_TOOLKIT=true
ASSUME_YES=false
CHECKSUMS_URL="${ST_TOOLKIT_CHECKSUMS_URL:-}"

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
      --ref)
        shift
        [[ -n "${1:-}" ]] || fatal "--ref 需要一个分支、标签或 commit。"
        TOOLKIT_REF="$1"
        ;;
      -y|--yes)
        ASSUME_YES=true
        ;;
      -h|--help)
        cat <<EOF
用法: $0 [--no-launch] [--yes] [--ref <ref>]

环境变量:
  ST_TOOLKIT_REF=<ref>              指定下载分支、标签或 commit
  ST_TOOLKIT_YES=1                  非交互接受代理下载风险
  ST_TOOLKIT_NO_LAUNCH=1            安装后不自动启动菜单
  ST_TOOLKIT_CHECKSUMS_URL=<url>    可选 checksum manifest URL
EOF
        exit 0
        ;;
      *)
        fatal "未知参数: $1"
        ;;
    esac
    shift
  done
}

truthy_env() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    0|false|FALSE|no|NO|n|N|off|OFF|"") return 1 ;;
    *) return 2 ;;
  esac
}

is_full_commit_ref() {
  [[ "${TOOLKIT_REF}" =~ ^[0-9A-Fa-f]{40}$ ]]
}

init_env_options() {
  local rc

  if truthy_env "${ST_TOOLKIT_YES:-}"; then
    ASSUME_YES=true
  else
    rc=$?
    case "${rc}" in
      1) ;;
      2) fatal "ST_TOOLKIT_YES 只能为 1/0、true/false、yes/no、on/off。" ;;
    esac
  fi

  if truthy_env "${ST_TOOLKIT_NO_LAUNCH:-}"; then
    LAUNCH_TOOLKIT=false
  else
    rc=$?
    case "${rc}" in
      1) ;;
      2) fatal "ST_TOOLKIT_NO_LAUNCH 只能为 1/0、true/false、yes/no、on/off。" ;;
    esac
  fi
}

validate_ref() {
  [[ -n "${TOOLKIT_REF}" ]] || fatal "TOOLKIT_REF 不能为空。"
  ((${#TOOLKIT_REF} <= 128)) || fatal "TOOLKIT_REF 长度不能超过 128。"

  [[ "${TOOLKIT_REF}" =~ ^[A-Za-z0-9._/-]+$ ]] || fatal "TOOLKIT_REF 只能包含 A-Z、a-z、0-9、.、_、-、/。"

  case "${TOOLKIT_REF}" in
    -*|/*|*..*|*//*|*"?*"|*"#"*|*"@{"*|*.lock|./*|*/.*)
      fatal "TOOLKIT_REF 格式不安全: ${TOOLKIT_REF}"
      ;;
  esac

  if is_full_commit_ref; then
    return 0
  fi

  if command -v git &>/dev/null; then
    git check-ref-format --allow-onelevel "${TOOLKIT_REF}" &>/dev/null || fatal "TOOLKIT_REF 不是合法的 git ref: ${TOOLKIT_REF}"
  fi
}

validate_checksums_url() {
  [[ -z "${CHECKSUMS_URL}" || "${CHECKSUMS_URL}" =~ ^https:// ]] || fatal "ST_TOOLKIT_CHECKSUMS_URL 必须使用 HTTPS。"
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

  if [[ ! -t 0 || ! -t 1 || ! -r /dev/tty ]]; then
    fatal "当前环境非交互。请传入 --yes 或设置 ST_TOOLKIT_YES=1 接受代理下载风险。"
  fi

  local answer=""
  read -r -p "是否继续通过 ghfast.top 下载？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*) return 0 ;;
    *) fatal "已取消安装。" ;;
  esac
}

verify_checksums_manifest() {
  local root_dir="$1"
  local manifest_file="$2"
  shift 2
  local expected_files=("$@")

  [[ -n "${CHECKSUMS_URL}" ]] || return 0
  command -v sha256sum &>/dev/null || fatal "启用 checksum 校验需要 sha256sum。"

  msg_warn "checksum 仅校验下载后的工具箱文件，不保护当前已执行的 bootstrap installer。"

  local line hash path actual found
  for line in "${expected_files[@]}"; do
    found=false
    while read -r hash path _ || [[ -n "${hash:-}${path:-}" ]]; do
      [[ -n "${hash:-}" ]] || continue
      [[ "${hash}" == \#* ]] && continue
      [[ "${hash}" =~ ^[0-9A-Fa-f]{64}$ ]] || fatal "checksum manifest hash 格式错误: ${hash}"
      [[ -n "${path:-}" ]] || fatal "checksum manifest 格式错误。"
      path="${path#\*}"
      [[ "${path}" != /* && "${path}" != *".."* ]] || fatal "checksum manifest 包含不安全路径: ${path}"
      if [[ "${path}" == "${line}" ]]; then
        found=true
        [[ -f "${root_dir}/${path}" ]] || fatal "checksum 目标文件不存在: ${path}"
        actual="$(sha256sum "${root_dir}/${path}" | awk '{print $1}')"
        [[ "${actual}" == "${hash}" ]] || fatal "checksum 不匹配: ${path}"
      fi
    done <"${manifest_file}"
    [[ "${found}" == "true" ]] || fatal "checksum manifest 缺失条目: ${line}"
  done

  msg_ok "工具箱文件 checksum 校验通过。"
}

atomic_replace_dir() {
  local src_dir="$1"
  local dst_dir="$2"
  local target_parent target_name staging_dir backup_dir ts n

  target_parent="$(dirname "${dst_dir}")"
  target_name="$(basename "${dst_dir}")"
  if ! mkdir -p "${target_parent}"; then
    fatal "创建工具箱目录父目录失败: ${target_parent}"
  fi
  staging_dir="$(mktemp -d "${target_parent}/.${target_name}.tmp.XXXXXX")"
  rmdir "${staging_dir}"

  if ! mv "${src_dir}" "${staging_dir}"; then
    rm -rf "${staging_dir}" 2>/dev/null || true
    fatal "准备工具箱临时目录失败。"
  fi

  if [[ -e "${dst_dir}" ]]; then
    ts="$(date +%Y%m%d_%H%M%S)"
    backup_dir="${dst_dir}.bak_${ts}"
    n=0
    while [[ -e "${backup_dir}" ]]; do
      n=$((n + 1))
      backup_dir="${dst_dir}.bak_${ts}.${n}"
    done
    msg_warn "检测到已存在的工具箱目录，将备份为: ${backup_dir}"
    if ! mv "${dst_dir}" "${backup_dir}"; then
      rm -rf "${staging_dir}" 2>/dev/null || true
      fatal "备份现有工具箱目录失败。"
    fi
  fi

  if mv "${staging_dir}" "${dst_dir}"; then
    return 0
  fi

  rm -rf "${staging_dir}" 2>/dev/null || true
  if [[ -n "${backup_dir:-}" && -e "${backup_dir}" && ! -e "${dst_dir}" ]]; then
    mv "${backup_dir}" "${dst_dir}" || true
  fi
  fatal "替换工具箱目录失败。"
}

install_from_proxy() {
  (
    install_dependency "curl"
    confirm_proxy_download

    local proxy_url base_url temp_dir manifest_file
    proxy_url="https://ghfast.top"
    base_url="${proxy_url}/https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${TOOLKIT_REF}/${REPO_PATH}"
    temp_dir="$(mktemp -d)"
    manifest_file=""

    cleanup_proxy_tmp() {
      rm -rf "${temp_dir}" 2>/dev/null || true
    }
    trap cleanup_proxy_tmp EXIT

    local files=(
      "install.sh"
      "st-toolkit.sh"
      "scripts/common.sh"
      "scripts/docker.sh"
      "scripts/health.sh"
      "scripts/sillytavern.sh"
      "scripts/sources.sh"
      "scripts/lib/logging.sh"
      "scripts/lib/input.sh"
      "scripts/lib/network.sh"
      "scripts/lib/os.sh"
      "scripts/lib/apt.sh"
      "scripts/lib/packages.sh"
      "scripts/lib/compose.sh"
      "scripts/docker/install.sh"
      "scripts/docker/mirror.sh"
      "scripts/docker/compose.sh"
      "scripts/docker/status.sh"
      "scripts/sillytavern/config.sh"
      "scripts/sillytavern/compose.sh"
      "scripts/sillytavern/access.sh"
      "scripts/sillytavern/lifecycle.sh"
      "scripts/sillytavern/status.sh"
    )

    local file parent_dir
    for file in "${files[@]}"; do
      parent_dir="$(dirname "${file}")"
      [[ "${parent_dir}" == "." ]] || mkdir -p "${temp_dir}/${parent_dir}"
      msg_info "下载: ${file}"
      curl -fsSL --connect-timeout 10 --max-time 180 --retry 3 --retry-delay 1 \
        "${base_url}/${file}" -o "${temp_dir}/${file}"
    done

    if [[ -n "${CHECKSUMS_URL}" ]]; then
      manifest_file="${temp_dir}/.checksums.sha256"
      curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 1 \
        "${CHECKSUMS_URL}" -o "${manifest_file}"
      verify_checksums_manifest "${temp_dir}" "${manifest_file}" "${files[@]}"
    fi

    atomic_replace_dir "${temp_dir}" "${TOOLKIT_DIR}"
    temp_dir=""
  )
}

install_from_git() {
  (
    install_dependency "git"

    local temp_dir repo_git_url prepared_dir
    temp_dir="$(mktemp -d)"
    repo_git_url="https://github.com/${REPO_USER}/${REPO_NAME}.git"
    prepared_dir=""

    cleanup_git_tmp() {
      [[ -n "${temp_dir:-}" && -d "${temp_dir}" ]] && rm -rf "${temp_dir}"
    }
    trap cleanup_git_tmp EXIT

    msg_info "正在从 GitHub 克隆仓库..."
    if is_full_commit_ref; then
      git init "${temp_dir}"
      git -C "${temp_dir}" remote add origin "${repo_git_url}"
      git -C "${temp_dir}" fetch --depth 1 origin "${TOOLKIT_REF}"
      git -C "${temp_dir}" checkout --detach FETCH_HEAD
    else
      git clone --depth 1 --branch "${TOOLKIT_REF}" "${repo_git_url}" "${temp_dir}"
    fi

    [[ -d "${temp_dir}/${REPO_PATH}" ]] || fatal "仓库中未找到 ${REPO_PATH}。"
    prepared_dir="${temp_dir}/${REPO_PATH}"
    atomic_replace_dir "${prepared_dir}" "${TOOLKIT_DIR}"
    prepared_dir=""
  )
}

main() {
  parse_args "$@"
  init_env_options
  validate_ref
  validate_checksums_url

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
  find "${TOOLKIT_DIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

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
