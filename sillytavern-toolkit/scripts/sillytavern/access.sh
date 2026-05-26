#!/usr/bin/env bash

# 说明：
# - 本文件会被 sillytavern.sh 作为子模块 source。
# - 依赖 common.sh 与其他 sillytavern 子模块提供的函数（如 configure_sillytavern_* / restart_st）。

backup_access_config() {
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "未找到 Compose 文件，无法创建访问配置备份。"
  [[ -f "${ST_CONFIG_FILE}" ]] || fatal "未找到配置文件，无法创建访问配置备份。"

  local backup_dir
  backup_dir="${APP_DIR}/backups/config/$(date +%Y%m%d_%H%M%S)"

  "${SUDO[@]}" mkdir -p "${backup_dir}"
  "${SUDO[@]}" cp -a "${ST_COMPOSE_FILE}" "${backup_dir}/docker-compose.yaml"
  "${SUDO[@]}" cp -a "${ST_CONFIG_FILE}" "${backup_dir}/config.yaml"

  msg_ok "访问配置已备份到: ${backup_dir}"
}

find_latest_access_backup() {
  local backup_root="${APP_DIR}/backups/config"
  [[ -d "${backup_root}" ]] || return 1

  "${SUDO[@]}" find "${backup_root}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1
}

change_access_st() {
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "SillyTavern 尚未安装，无法修改访问配置。"

  backup_access_config
  if [[ "${NON_INTERACTIVE}" == "1" ]]; then
    configure_sillytavern_non_interactive
  else
    configure_sillytavern_interactive
  fi
  msg_info "配置已更新，正在重启 SillyTavern..."
  restart_st
}

restore_access_st() {
  ensure_interactive_tty

  local backup_dir answer restart_answer
  backup_dir="$(find_latest_access_backup || true)"
  [[ -n "${backup_dir}" ]] || fatal "未找到访问配置备份: ${APP_DIR}/backups/config"
  [[ -f "${backup_dir}/docker-compose.yaml" ]] || fatal "备份缺少 docker-compose.yaml: ${backup_dir}"
  [[ -f "${backup_dir}/config.yaml" ]] || fatal "备份缺少 config.yaml: ${backup_dir}"

  msg_info "最近的访问配置备份: ${backup_dir}"
  read_yes_no "确认恢复该备份并覆盖当前 compose/config？(y/n): " answer
  if [[ "${answer}" != "y" ]]; then
    msg_warn "已取消恢复。"
    return 0
  fi

  "${SUDO[@]}" mkdir -p "${APP_DIR}/config"
  "${SUDO[@]}" cp -a "${backup_dir}/docker-compose.yaml" "${ST_COMPOSE_FILE}"
  "${SUDO[@]}" cp -a "${backup_dir}/config.yaml" "${ST_CONFIG_FILE}"

  msg_ok "访问配置已恢复。"
  read_yes_no "是否现在重启 SillyTavern 使配置生效？(y/n): " restart_answer
  if [[ "${restart_answer}" == "y" ]]; then
    restart_st
  else
    msg_warn "已跳过重启，请稍后手动重启 SillyTavern。"
  fi
}
