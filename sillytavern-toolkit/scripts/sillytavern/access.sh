#!/usr/bin/env bash

# 说明：
# - 本文件会被 sillytavern.sh 作为子模块 source。
# - 依赖 common.sh 与其他 sillytavern 子模块提供的函数（如 configure_sillytavern_* / apply_compose_changes_st）。

backup_access_config() {
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "未找到 Compose 文件，无法创建访问配置备份。"
  [[ -f "${ST_CONFIG_FILE}" ]] || fatal "未找到配置文件，无法创建访问配置备份。"

  local backup_dir
  LAST_ACCESS_BACKUP_DIR=""
  backup_dir="${APP_DIR}/backups/config/$(date +%Y%m%d_%H%M%S)"

  "${SUDO[@]}" mkdir -p "${backup_dir}" || fatal "访问配置备份失败：无法创建备份目录。"
  "${SUDO[@]}" cp -a "${ST_COMPOSE_FILE}" "${backup_dir}/docker-compose.yaml" || fatal "访问配置备份失败：无法备份 docker-compose.yaml。"
  "${SUDO[@]}" cp -a "${ST_CONFIG_FILE}" "${backup_dir}/config.yaml" || fatal "访问配置备份失败：无法备份 config.yaml。"

  msg_ok "访问配置已备份到: ${backup_dir}"
  LAST_ACCESS_BACKUP_DIR="${backup_dir}"
}

find_latest_access_backup() {
  local backup_root="${APP_DIR}/backups/config"
  [[ -d "${backup_root}" ]] || return 1

  "${SUDO[@]}" find "${backup_root}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1
}

restore_access_files_from_backup() {
  local backup_dir="$1"

  [[ -n "${backup_dir}" ]] || fatal "访问配置回滚失败：备份目录为空。"
  [[ -f "${backup_dir}/docker-compose.yaml" ]] || fatal "访问配置回滚失败：备份缺少 docker-compose.yaml: ${backup_dir}"
  [[ -f "${backup_dir}/config.yaml" ]] || fatal "访问配置回滚失败：备份缺少 config.yaml: ${backup_dir}"

  "${SUDO[@]}" cp -a "${backup_dir}/docker-compose.yaml" "${ST_COMPOSE_FILE}" || fatal "访问配置回滚失败：无法恢复 docker-compose.yaml。"
  "${SUDO[@]}" cp -a "${backup_dir}/config.yaml" "${ST_CONFIG_FILE}" || fatal "访问配置回滚失败：无法恢复 config.yaml。"
}

apply_restored_access_config() {
  local backup_dir="$1"

  msg_warn "Compose 变更应用失败，正在恢复上一次访问配置..."
  restore_access_files_from_backup "${backup_dir}"

  if apply_compose_changes_st; then
    fatal "访问配置应用失败；本次修改未生效，已恢复并重新应用上一次 compose/config。备份目录: ${backup_dir}"
  fi

  fatal "访问配置应用失败；已恢复上一次 compose/config 文件，但恢复后的 Compose 配置也未能重新应用 (rollback apply failed)。备份目录: ${backup_dir}"
}

restore_after_access_config_failure() {
  local backup_dir="$1"

  msg_warn "访问配置生成失败，正在恢复上一次访问配置..."
  restore_access_files_from_backup "${backup_dir}"

  if apply_compose_changes_st; then
    fatal "访问配置生成失败；本次修改未生效，已恢复并重新应用上一次 compose/config。备份目录: ${backup_dir}"
  fi

  fatal "访问配置生成失败；已恢复上一次 compose/config 文件，但恢复后的 Compose 配置也未能重新应用 (rollback apply failed)。备份目录: ${backup_dir}"
}

run_access_configure() (
  set -e
  if [[ "${NON_INTERACTIVE}" == "1" ]]; then
    configure_sillytavern_non_interactive
  else
    configure_sillytavern_interactive
  fi
)

change_access_st() {
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "SillyTavern 尚未安装，无法修改访问配置。"

  local access_backup_dir configure_status had_errexit=0
  backup_access_config
  access_backup_dir="${LAST_ACCESS_BACKUP_DIR:-}"
  [[ -n "${access_backup_dir}" ]] || fatal "访问配置备份失败，无法安全修改访问配置。"

  [[ $- == *e* ]] && had_errexit=1
  set +e
  run_access_configure
  configure_status=$?
  if [[ "${had_errexit}" == "1" ]]; then
    set -e
  else
    set +e
  fi

  if [[ "${configure_status}" -ne 0 ]]; then
    restore_after_access_config_failure "${access_backup_dir}"
  fi

  msg_info "配置已更新，正在应用 SillyTavern Compose 变更..."
  if ! apply_compose_changes_st; then
    apply_restored_access_config "${access_backup_dir}"
  fi
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
