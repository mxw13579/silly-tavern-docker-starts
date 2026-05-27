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

SUDO=()
OS=""
OS_FAMILY=""
PKG_MANAGER=""
USE_CHINA_MIRROR=false

INSTALLER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

print_usage() {
  cat <<EOF
用法: $0 [--no-launch] [--yes] [--ref <ref>]

环境变量:
  ST_TOOLKIT_REF=<ref>              指定下载分支、标签或 commit
  ST_TOOLKIT_YES=1                  非交互接受代理下载风险
  ST_TOOLKIT_NO_LAUNCH=1            安装后不自动启动菜单
  ST_TOOLKIT_CHECKSUMS_URL=<url>    可选 checksum manifest URL
EOF
}

for __arg in "$@"; do
  case "${__arg}" in
    -h|--help)
      print_usage
      exit 0
      ;;
  esac
done
unset __arg

require_installer_module() {
  local module="$1"
  local path="${INSTALLER_DIR}/${module}"

  if [[ ! -f "${path}" ]]; then
    if [[ -n "${C_RED:-}" && -n "${C_RESET:-}" ]]; then
      printf '%b[ERROR]%b 缺少安装器模块: %s\n' "${C_RED}" "${C_RESET}" "${path}" >&2
      printf '%b[ERROR]%b 请使用完整仓库目录运行 install.sh。\n' "${C_RED}" "${C_RESET}" >&2
    else
      printf '[ERROR] 缺少安装器模块: %s\n' "${path}" >&2
      printf '[ERROR] 请使用完整仓库目录运行 install.sh。\n' >&2
    fi
    exit 1
  fi

  # shellcheck source=/dev/null
  . "${path}"
}

require_installer_module "install/logging.sh"
require_installer_module "install/options.sh"
require_installer_module "install/os.sh"
require_installer_module "install/checksum.sh"
require_installer_module "install/filesystem.sh"
require_installer_module "install/installers.sh"

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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
