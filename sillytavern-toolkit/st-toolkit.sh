#!/usr/bin/env bash

# SillyTavern Toolkit 主菜单。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

ST_TOOLKIT_REQUIRE_SUDO=0
ST_TOOLKIT_SKIP_COUNTRY=1

# shellcheck source=sillytavern-toolkit/scripts/common.sh
. "${SCRIPT_DIR}/scripts/common.sh"
set +e

STATUS_CACHE=""
STATUS_CACHE_SECONDS=0
STATUS_CACHE_TTL=15

render_status_header() {
  toolkit_status_header
  "${SCRIPT_DIR}/scripts/sources.sh" status </dev/null
  "${SCRIPT_DIR}/scripts/docker.sh" status </dev/null
  "${SCRIPT_DIR}/scripts/sillytavern.sh" status </dev/null
}

refresh_status_cache() {
  STATUS_CACHE="$(render_status_header 2>&1)"
  STATUS_CACHE_SECONDS=${SECONDS}
}

invalidate_status_cache() {
  STATUS_CACHE=""
  STATUS_CACHE_SECONDS=0
}

show_header() {
  local force_refresh="${1:-0}"
  local cache_age=$((SECONDS - STATUS_CACHE_SECONDS))

  clear || true
  echo "=========================================================="
  echo "======          SillyTavern Docker 工具箱           ======"
  echo "======          FuFu API (群1019836466) 提供         ======"
  echo "=========================================================="
  echo
  echo "--- 系统环境状态 ---"
  if [[ -z "${STATUS_CACHE}" || "${force_refresh}" == "1" || ${cache_age} -ge ${STATUS_CACHE_TTL} ]]; then
    refresh_status_cache
  fi
  printf '%s\n' "${STATUS_CACHE}"
  echo "----------------------------------------------------------"
  echo
}

run_action() {
  local pause_on_success=0
  if [[ "${1:-}" == "--pause-on-success" ]]; then
    pause_on_success=1
    shift
  fi

  "$@"
  local code=$?
  invalidate_status_cache
  if [[ ${code} -ne 0 ]]; then
    msg_error "命令执行失败，退出码: ${code}"
    pause_to_continue
    return "${code}"
  fi

  if ((pause_on_success)); then
    pause_to_continue
  else
    msg_ok "操作完成，返回菜单..."
    sleep 0.8
  fi

  return 0
}

handle_empty_choice() {
  msg_warn "请输入菜单编号。"
  sleep 0.8
}

read_menu_choice() {
  local result_var="$1"
  local prompt="$2"
  local choice=""

  if ! read -r -p "${prompt}" choice; then
    echo
    return 1
  fi

  choice="${choice%$'\r'}"
  if [[ -z "${choice}" ]]; then
    handle_empty_choice
    return 2
  fi

  printf -v "${result_var}" '%s' "${choice}"
  return 0
}

sources_menu() {
  local choice=""
  local read_code=0

  while true; do
    clear || true
    echo "--- 软件源管理 ---"
    echo "Debian/Ubuntu/Arch/Alpine 支持自动切换；RedHat/SUSE 为避免破坏企业源，仅显示状态。"
    echo "---------------------------------------------------"
    "${SCRIPT_DIR}/scripts/sources.sh" status
    echo "---------------------------------------------------"
    echo "   1. 切换为 [阿里云] 软件源"
    echo "   2. 切换为 [腾讯云] 软件源"
    echo "   3. 切换为 [华为云] 软件源"
    echo "   4. 恢复最近一次备份的软件源"
    echo "   0. 返回主菜单"
    echo "---------------------------------------------------"
    read_menu_choice choice "请输入选项 [0-4]: "
    read_code=$?
    if ((read_code != 0)); then
      if ((read_code == 2)); then
        continue
      fi
      msg_warn "未读取到输入，返回主菜单。"
      break
    fi

    case "${choice}" in
      1) run_action "${SCRIPT_DIR}/scripts/sources.sh" set aliyun ;;
      2) run_action "${SCRIPT_DIR}/scripts/sources.sh" set tencent ;;
      3) run_action "${SCRIPT_DIR}/scripts/sources.sh" set huawei ;;
      4) run_action "${SCRIPT_DIR}/scripts/sources.sh" restore ;;
      0) break ;;
      *) msg_error "无效选项"; pause_to_continue ;;
    esac
  done
}

docker_menu() {
  local choice=""
  local read_code=0

  while true; do
    clear || true
    echo "--- Docker 环境管理 ---"
    echo "安装逻辑已同步新版部署脚本，支持 Debian/Ubuntu/RedHat/Arch/Alpine/SUSE。"
    echo "---------------------------------------------------"
    "${SCRIPT_DIR}/scripts/docker.sh" status
    echo "---------------------------------------------------"
    echo "   1. 安装或修复 Docker 与 Compose"
    echo "   2. 单独检查/安装 Docker Compose"
    echo "   3. Docker 镜像加速器管理"
    echo "   4. 重启 Docker 服务"
    echo "   5. 查看已下载的 Docker 镜像"
    echo "   6. 恢复最近一次 daemon.json 备份"
    echo "   0. 返回主菜单"
    echo "---------------------------------------------------"
    read_menu_choice choice "请输入选项 [0-6]: "
    read_code=$?
    if ((read_code != 0)); then
      if ((read_code == 2)); then
        continue
      fi
      msg_warn "未读取到输入，返回主菜单。"
      break
    fi

    case "${choice}" in
      1) run_action "${SCRIPT_DIR}/scripts/docker.sh" install ;;
      2) run_action "${SCRIPT_DIR}/scripts/docker.sh" compose ;;
      3) run_action --pause-on-success bash "${SCRIPT_DIR}/scripts/docker.sh" mirror_menu ;;
      4) run_action "${SCRIPT_DIR}/scripts/docker.sh" restart_service ;;
      5) run_action --pause-on-success "${SCRIPT_DIR}/scripts/docker.sh" list_images ;;
      6) run_action "${SCRIPT_DIR}/scripts/docker.sh" restore_daemon ;;
      0) break ;;
      *) msg_error "无效选项"; pause_to_continue ;;
    esac
  done
}

sillytavern_menu() {
  local choice=""
  local read_code=0

  while true; do
    clear || true
    echo "--- SillyTavern 应用管理 ---"
    echo "全新安装会询问本地/外网访问、Basic Auth 和 Watchtower 风险选项。"
    echo "---------------------------------------------------"
    "${SCRIPT_DIR}/scripts/sillytavern.sh" status
    echo "---------------------------------------------------"
    echo "   1. 全新安装 SillyTavern"
    echo "   2. 启动 SillyTavern"
    echo "   3. 停止 SillyTavern"
    echo "   4. 重启 SillyTavern"
    echo "   5. 更新 SillyTavern 镜像并重启"
    echo "   6. 查看 SillyTavern 实时日志"
    echo "   7. 备份 SillyTavern 数据"
    echo "   8. 修改访问模式/用户名密码/Watchtower"
    echo "   9. 恢复上一次访问配置"
    echo "  10. 运行健康检查"
    echo "  11. 显示部署信息"
    echo "   0. 返回主菜单"
    echo "---------------------------------------------------"
    read_menu_choice choice "请输入选项 [0-11]: "
    read_code=$?
    if ((read_code != 0)); then
      if ((read_code == 2)); then
        continue
      fi
      msg_warn "未读取到输入，返回主菜单。"
      break
    fi

    case "${choice}" in
      1) run_action --pause-on-success "${SCRIPT_DIR}/scripts/sillytavern.sh" install ;;
      2) run_action "${SCRIPT_DIR}/scripts/sillytavern.sh" start ;;
      3) run_action "${SCRIPT_DIR}/scripts/sillytavern.sh" stop ;;
      4) run_action "${SCRIPT_DIR}/scripts/sillytavern.sh" restart ;;
      5) run_action "${SCRIPT_DIR}/scripts/sillytavern.sh" update ;;
      6) run_action --pause-on-success "${SCRIPT_DIR}/scripts/sillytavern.sh" logs ;;
      7) run_action --pause-on-success "${SCRIPT_DIR}/scripts/sillytavern.sh" backup ;;
      8) run_action --pause-on-success "${SCRIPT_DIR}/scripts/sillytavern.sh" change_access ;;
      9) run_action "${SCRIPT_DIR}/scripts/sillytavern.sh" restore_access ;;
      10) run_action --pause-on-success bash "${SCRIPT_DIR}/scripts/health.sh" ;;
      11) run_action --pause-on-success "${SCRIPT_DIR}/scripts/sillytavern.sh" info ;;
      0) break ;;
      *) msg_error "无效选项"; pause_to_continue ;;
    esac
  done
}

main() {
  local choice=""
  local refresh_status=1
  local read_code=0

  while true; do
    show_header "${refresh_status}"
    refresh_status=0
    echo "--- 主菜单 ---"
    echo "   推荐新手按 1 -> 2 -> 3 的顺序操作"
    echo
    echo "   1. 软件源管理"
    echo "   2. Docker 环境管理"
    echo "   3. SillyTavern 应用管理"
    echo
    echo "   0. 退出脚本"
    echo "----------------------------------------------------------"
    read_menu_choice choice "请输入选项 [0-3]: "
    read_code=$?
    if ((read_code != 0)); then
      if ((read_code == 2)); then
        continue
      fi
      msg_warn "未读取到输入，退出脚本。"
      exit 0
    fi

    case "${choice}" in
      1) sources_menu; refresh_status=1 ;;
      2) docker_menu; refresh_status=1 ;;
      3) sillytavern_menu; refresh_status=1 ;;
      0)
        echo "感谢使用，再见。"
        exit 0
        ;;
      *)
        msg_error "无效的主菜单选项，请输入 0-3 之间的数字。"
        pause_to_continue
        ;;
    esac
  done
}

main "$@"
