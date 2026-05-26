#!/usr/bin/env bash
set -euo pipefail

NON_INTERACTIVE=0

while (($# > 0)); do
  case "$1" in
    --non-interactive|-n)
      NON_INTERACTIVE=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [[ "${1:-}" == "status" ]]; then
  export ST_TOOLKIT_REQUIRE_SUDO=0
  export ST_TOOLKIT_SKIP_COUNTRY=1
fi

__st_scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sillytavern-toolkit/scripts/common.sh
. "${__st_scripts_dir}/common.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/compose.sh
. "${__st_scripts_dir}/sillytavern/compose.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/config.sh
. "${__st_scripts_dir}/sillytavern/config.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/access.sh
. "${__st_scripts_dir}/sillytavern/access.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/lifecycle.sh
. "${__st_scripts_dir}/sillytavern/lifecycle.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/status.sh
. "${__st_scripts_dir}/sillytavern/status.sh"

parse_bool_env() {
  local name="$1"
  local value="${!name:-}"

  [[ -n "${value}" ]] || return 1
  case "${value}" in
    1|true|TRUE|yes|YES|y|Y|on|ON)
      return 0
      ;;
    0|false|FALSE|no|NO|n|N|off|OFF)
      return 1
      ;;
    *)
      fatal "${name} 只能为 1/0、true/false、yes/no、on/off。"
      ;;
  esac
}

if parse_bool_env ST_NON_INTERACTIVE; then
  NON_INTERACTIVE=1
fi

usage() {
  cat <<'EOF'
用法: sillytavern.sh [--non-interactive|-n] <命令>

命令:
  install          全新安装 SillyTavern
  start            启动
  stop             停止
  restart          重启
  update           更新镜像并重启
  logs             查看实时日志
  backup           备份数据目录
  change_access    修改访问模式/用户名密码/Watchtower
  restore_access   恢复上一次访问配置
  info             显示部署信息
  status           显示状态

非交互环境变量:
  ST_NON_INTERACTIVE=1
  ST_ACCESS_MODE=local|public
  ST_AUTH_USER=<username>      public 模式必填
  ST_AUTH_PASS=<password>      public 模式必填
  ST_ENABLE_WATCHTOWER=1|0
EOF
}

case "${1:-}" in
  install)
    install_st
    ;;
  start)
    start_st
    ;;
  stop)
    stop_st
    ;;
  restart)
    restart_st
    ;;
  update)
    update_st
    ;;
  logs)
    logs_st
    ;;
  backup)
    backup_st
    ;;
  change_access|change_password)
    change_access_st
    ;;
  restore_access)
    restore_access_st
    ;;
  info)
    print_final_info
    ;;
  status)
    status_st
    ;;
  *)
    usage
    exit 1
    ;;
esac
