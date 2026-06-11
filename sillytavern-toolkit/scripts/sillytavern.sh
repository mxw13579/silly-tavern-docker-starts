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

__st_scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "self-check" || "${1:-}" == "check" ]]; then
  shift
  exec bash "${__st_scripts_dir}/toolkit/self_check.sh" "$@"
fi

if [[ "${1:-}" == "doctor-report" || "${1:-}" == "doctor" ]] && [[ "${2:-}" == "--help" ]]; then
  shift
  # shellcheck source=sillytavern-toolkit/scripts/doctor_report.sh
  # shellcheck disable=SC1091
  . "${__st_scripts_dir}/doctor_report.sh"
  doctor_report_main "$@"
  exit $?
fi

if [[ "${1:-}" == "status" || "${1:-}" == "doctor-report" || "${1:-}" == "doctor" ]]; then
  export ST_TOOLKIT_REQUIRE_SUDO=0
  export ST_TOOLKIT_SKIP_COUNTRY=1
fi

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
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/logs.sh
# shellcheck disable=SC1091
. "${__st_scripts_dir}/sillytavern/logs.sh"
# shellcheck source=sillytavern-toolkit/scripts/sillytavern/status.sh
# shellcheck disable=SC1091
. "${__st_scripts_dir}/sillytavern/status.sh"
# shellcheck source=sillytavern-toolkit/scripts/doctor_report.sh
# shellcheck disable=SC1091
. "${__st_scripts_dir}/doctor_report.sh"

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
  logs             查看、跟随、按时间筛选或导出日志
  backup           备份数据目录
  change_access    修改访问模式/用户名密码/Watchtower
  restore_access   恢复上一次访问配置
  info             显示部署信息
  status           显示状态
  doctor-report    生成只读诊断报告
  doctor           doctor-report 的别名
  self-check       只读自检工具箱文件、依赖和本机运行环境
  check            self-check 的别名

日志子命令:
  logs tail --lines 200
  logs follow --lines 100
  logs since 30m --lines 1000
  logs save --output /path/to/sillytavern.log

self-check 选项:
  --strict          将 WARN 视为非零结果
  --quiet           隐藏 PASS 明细，只输出 WARN/FAIL/summary

doctor-report 选项:
  --output PATH     写入指定 Markdown 文件
  --stdout          输出到标准输出，不创建文件
  --no-logs         跳过 Docker Compose 日志
  --lines N         捕获日志行数，默认 200，最大 5000
  --since VALUE     透传 Docker Compose logs --since
  --service NAME    捕获单个 Compose 服务日志，默认 sillytavern
  --all-services    捕获全部 Compose 服务日志

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
    shift
    logs_st "$@"
    ;;
  self-check|check)
    shift
    bash "${__st_scripts_dir}/toolkit/self_check.sh" "$@"
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
  doctor-report|doctor)
    shift
    # doctor_report.sh is sourced above so common.sh source-time setup only runs once.
    doctor_report_main "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
