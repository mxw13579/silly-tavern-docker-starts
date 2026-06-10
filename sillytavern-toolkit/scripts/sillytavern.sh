#!/usr/bin/env bash
set -euo pipefail

NON_INTERACTIVE=0

while (($# > 0)); do
  case "$1" in
    --non-interactive|-n)
      # shellcheck disable=SC2034
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
# shellcheck disable=SC1091
. "${__st_scripts_dir}/common.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/compose.sh
# shellcheck disable=SC1091
. "${__st_scripts_dir}/sillytavern/compose.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/validation.sh
# shellcheck disable=SC1091
. "${__st_scripts_dir}/sillytavern/validation.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/config.sh
# shellcheck disable=SC1091
. "${__st_scripts_dir}/sillytavern/config.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/access.sh
# shellcheck disable=SC1091
. "${__st_scripts_dir}/sillytavern/access.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/lifecycle.sh
# shellcheck disable=SC1091
. "${__st_scripts_dir}/sillytavern/lifecycle.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/status.sh
# shellcheck disable=SC1091
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
  # shellcheck disable=SC2034
  NON_INTERACTIVE=1
fi

usage() {
  cat <<'EOF'
用法: sillytavern.sh [--non-interactive|-n] <命令>

命令:
  install          全新安装 SillyTavern
  validate         校验 SillyTavern Compose 配置并检查 config 文件存在
  start            启动 SillyTavern 服务
  stop             停止容器，不删除 Compose 项目
  down             停止并移除 Compose 容器/网络，保留应用目录和绑定挂载数据
  apply            校验并应用 Compose 配置变更，移除孤儿容器
  restart          重启现有容器，不应用 Compose 配置变更
  update           校验配置、拉取镜像并运行 up -d
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
  validate)
    validate_sillytavern_compose
    ;;
  start)
    start_st
    ;;
  stop)
    shift
    if (($# > 0)); then
      fatal "stop 不接受额外参数。"
    fi
    stop_st
    ;;
  down)
    shift
    down_st "$@"
    ;;
  apply)
    shift
    apply_compose_changes_st "$@"
    ;;
  restart)
    shift
    if (($# > 0)); then
      fatal "restart 不接受额外参数。"
    fi
    restart_st
    ;;
  update)
    shift
    if (($# > 0)); then
      fatal "update 不接受额外参数。"
    fi
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
