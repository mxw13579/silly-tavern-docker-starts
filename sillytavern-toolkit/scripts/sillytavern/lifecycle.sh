#!/usr/bin/env bash

# 说明：
# - 本文件会被 sillytavern.sh 作为子模块 source。
# - 依赖 common.sh 提供的工具函数与变量（如 msg_error/detect_compose_cmd/COMPOSE_CMD 等）。

check_docker_env() {
  if ! command -v docker &>/dev/null; then
    msg_error "Docker 未安装。请先从主菜单选择 Docker 环境管理 -> 安装 Docker。"
    return 1
  fi

  if ! "${SUDO[@]}" docker info &>/dev/null; then
    msg_error "Docker 未运行或当前用户无权限访问 Docker。请先启动 Docker。"
    return 1
  fi

  if ! detect_compose_cmd; then
    msg_error "未检测到 docker compose 或 docker-compose。请先安装 Docker Compose。"
    return 1
  fi
}

install_st() {
  check_docker_env || return 1

  if [[ -f "${ST_COMPOSE_FILE}" ]]; then
    msg_warn "检测到 SillyTavern 已安装: ${APP_DIR}"
    msg_warn "如需重新安装，请先备份数据并手动处理该目录。"
    return 0
  fi

  if [[ "${NON_INTERACTIVE}" == "1" ]]; then
    configure_sillytavern_non_interactive
  else
    configure_sillytavern_interactive
  fi
  compose_in_app "拉取 Docker 镜像" pull
  compose_in_app "启动 SillyTavern 服务" up -d
  print_final_info
}

start_st() {
  check_docker_env || return 1
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "未找到 SillyTavern 安装，请先全新安装。"
  compose_in_app "启动 SillyTavern 服务" up -d
  msg_ok "SillyTavern 已启动。"
}

stop_st() {
  check_docker_env || return 1
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "未找到 SillyTavern 安装。"
  compose_in_app "停止 SillyTavern 服务" down
  msg_ok "SillyTavern 已停止。"
}

restart_st() {
  check_docker_env || return 1
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "未找到 SillyTavern 安装。"
  compose_in_app "重启 SillyTavern 服务" restart
  msg_ok "SillyTavern 已重启。"
}

update_st() {
  check_docker_env || return 1
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "未找到 SillyTavern 安装。"
  compose_in_app "拉取最新镜像" pull
  compose_in_app "使用新镜像启动服务" up -d
  msg_ok "SillyTavern 更新并重启完成。"
}

logs_st() {
  check_docker_env || return 1
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "未找到 SillyTavern 安装。"
  msg_info "正在显示 SillyTavern 实时日志，按 Ctrl+C 退出。"
  (cd "${APP_DIR}" && "${SUDO[@]}" "${COMPOSE_CMD[@]}" logs -f sillytavern)
}

backup_st() {
  [[ -d "${APP_DIR}" ]] || fatal "SillyTavern 目录不存在，无法备份。"

  local backup_file owner
  backup_file="${HOME}/sillytavern_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
  owner="${SUDO_USER:-${USER:-}}"

  msg_info "正在将 ${APP_DIR} 备份到 ${backup_file} ..."
  "${SUDO[@]}" tar -czf "${backup_file}" -C "$(dirname "${APP_DIR}")" "$(basename "${APP_DIR}")"

  if [[ -n "${owner}" ]]; then
    "${SUDO[@]}" chown "${owner}:${owner}" "${backup_file}" 2>/dev/null || true
  fi

  msg_ok "备份成功: ${backup_file}"
}
