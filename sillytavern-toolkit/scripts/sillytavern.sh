#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  ST_TOOLKIT_REQUIRE_SUDO=0
  ST_TOOLKIT_SKIP_COUNTRY=1
fi

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ENABLE_EXTERNAL_ACCESS="n"
ENABLE_WATCHTOWER="n"
username=""
password=""

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

compose_in_app() {
  local title="$1"
  shift

  (cd "${APP_DIR}" && compose_quiet "${title}" "$@")
}

prepare_app_dirs() {
  "${SUDO[@]}" mkdir -p \
    "${APP_DIR}/plugins" \
    "${APP_DIR}/config" \
    "${APP_DIR}/data" \
    "${APP_DIR}/extensions"

  "${SUDO[@]}" chown -R 1000:1000 \
    "${APP_DIR}/plugins" \
    "${APP_DIR}/config" \
    "${APP_DIR}/data" \
    "${APP_DIR}/extensions" || true
}

write_sillytavern_config() {
  local enable_external_access="$1"
  local config_username="${2:-}"
  local config_password="${3:-}"

  if [[ "${enable_external_access}" == "y" ]]; then
    validate_credential "${config_username}" || fatal "用户名格式非法。"
    validate_credential "${config_password}" || fatal "密码格式非法。"
  fi

  "${SUDO[@]}" mkdir -p "${APP_DIR}/config"

  if [[ "${enable_external_access}" == "y" ]]; then
    cat <<EOF | "${SUDO[@]}" tee "${ST_CONFIG_FILE}" >/dev/null
dataRoot: ./data
cardsCacheCapacity: 100
listen: true
protocol:
  ipv4: true
  ipv6: false
dnsPreferIPv6: false
autorunHostname: auto
port: 8000
autorunPortOverride: -1
whitelistMode: false
enableForwardedWhitelist: true
whitelist:
  - ::1
  - 127.0.0.1
basicAuthMode: true
basicAuthUser:
  username: "${config_username}"
  password: "${config_password}"
EOF
  else
    cat <<'EOF' | "${SUDO[@]}" tee "${ST_CONFIG_FILE}" >/dev/null
dataRoot: ./data
cardsCacheCapacity: 100
listen: true
protocol:
  ipv4: true
  ipv6: false
dnsPreferIPv6: false
autorunHostname: auto
port: 8000
autorunPortOverride: -1
whitelistMode: false
enableForwardedWhitelist: false
whitelist:
  - ::1
  - 127.0.0.1
basicAuthMode: false
basicAuthUser:
  username: ""
  password: ""
EOF
  fi

  "${SUDO[@]}" chown -R 1000:1000 "${APP_DIR}/config" || true
}

generate_compose_file() {
  local enable_external_access="$1"
  local enable_watchtower="${2:-n}"
  local bind_host="127.0.0.1"

  if [[ "${enable_external_access}" == "y" ]]; then
    bind_host="0.0.0.0"
  fi

  local sillytavern_image="ghcr.io/sillytavern/sillytavern:latest"
  local watchtower_image="containrrr/watchtower"

  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    sillytavern_image="ghcr.nju.edu.cn/sillytavern/sillytavern:latest"
  fi

  prepare_app_dirs

  cat <<EOF | "${SUDO[@]}" tee "${ST_COMPOSE_FILE}" >/dev/null
services:
  sillytavern:
    image: ${sillytavern_image}
    ports:
      - "${bind_host}:8000:8000"
    volumes:
      - ./plugins:/home/node/app/plugins:rw
      - ./config:/home/node/app/config:rw
      - ./data:/home/node/app/data:rw
      - ./extensions:/home/node/app/public/scripts/extensions/third-party:rw
    restart: always
EOF

  if [[ "${enable_watchtower}" == "y" ]]; then
    cat <<EOF | "${SUDO[@]}" tee -a "${ST_COMPOSE_FILE}" >/dev/null
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  watchtower:
    image: ${watchtower_image}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400 --cleanup --label-enable
    restart: always
EOF
  fi

  msg_ok "docker-compose.yaml 已生成。"
  msg_info "SillyTavern 镜像: ${sillytavern_image}"

  if [[ "${enable_watchtower}" == "y" ]]; then
    msg_warn "Watchtower 已启用，将挂载 /var/run/docker.sock。"
  else
    msg_info "Watchtower 未启用。"
  fi
}

read_safe_username() {
  local input=""

  while true; do
    read -r -p "请输入用户名，仅允许 A-Z、a-z、0-9、.、_、@、-，不能为纯数字: " input </dev/tty
    if validate_credential "${input}"; then
      username="${input}"
      return 0
    fi
    msg_warn "用户名格式错误，长度 3-64 位，且不能为纯数字。"
  done
}

read_safe_password() {
  local input=""

  while true; do
    read -r -s -p "请输入密码，仅允许 A-Z、a-z、0-9、.、_、@、-，不能为纯数字: " input </dev/tty
    printf '\n'
    if validate_credential "${input}"; then
      password="${input}"
      return 0
    fi
    msg_warn "密码格式错误，长度 3-64 位，且不能为纯数字。"
  done
}

confirm_watchtower() {
  ENABLE_WATCHTOWER="n"

  log "--------------------------------------------------"
  msg_warn "Watchtower 可自动更新容器，但需要挂载 /var/run/docker.sock。"
  msg_warn "Docker socket 权限很高，容器一旦被攻击可能影响宿主机 Docker 环境。"
  msg_info "默认建议不启用，除非你明确接受该风险。"
  read_yes_no "是否启用 Watchtower 自动更新？(y/n): " ENABLE_WATCHTOWER
}

configure_sillytavern_interactive() {
  ensure_interactive_tty

  msg_info "配置 SillyTavern..."
  log "不开启外网访问时仅监听 127.0.0.1:8000。"
  log "开启外网访问时监听 0.0.0.0:8000，并强制配置用户名密码。"

  ENABLE_EXTERNAL_ACCESS="n"
  read_yes_no "是否开启外网访问？(y/n): " ENABLE_EXTERNAL_ACCESS

  username=""
  password=""

  confirm_watchtower
  generate_compose_file "${ENABLE_EXTERNAL_ACCESS}" "${ENABLE_WATCHTOWER}"

  if [[ "${ENABLE_EXTERNAL_ACCESS}" == "y" ]]; then
    log "请选择用户名密码生成方式:"
    log "1. 随机生成"
    log "2. 手动输入"

    local choice=""
    while true; do
      read -r -p "请输入选择 (1/2): " choice </dev/tty
      case "${choice}" in
        1)
          username="$(generate_random_string 16)"
          password="$(generate_random_string 20)"
          msg_ok "已生成随机用户名: ${username}"
          msg_ok "已生成随机密码: ${password}"
          break
          ;;
        2)
          read_safe_username
          read_safe_password
          break
          ;;
        *)
          msg_warn "请输入 1 或 2。"
          ;;
      esac
    done

    write_sillytavern_config "y" "${username}" "${password}"
    msg_ok "已开启外网访问并配置 Basic Auth。"
  else
    write_sillytavern_config "n"
    msg_ok "未开启外网访问，仅允许本机访问端口。"
  fi

  prepare_app_dirs
}

install_st() {
  check_docker_env || return 1

  if [[ -f "${ST_COMPOSE_FILE}" ]]; then
    msg_warn "检测到 SillyTavern 已安装: ${APP_DIR}"
    msg_warn "如需重新安装，请先备份数据并手动处理该目录。"
    return 0
  fi

  configure_sillytavern_interactive
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
  configure_sillytavern_interactive
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

get_public_ip() {
  local public_ip=""
  public_ip="$(fetch_url_quiet "https://ipinfo.io/ip" 2>/dev/null | tr -d '\r\n' || true)"
  [[ -n "${public_ip}" ]] || public_ip="<你的服务器公网IP>"
  printf '%s' "${public_ip}"
}

print_final_info() {
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "SillyTavern 尚未安装，无法显示部署信息。"
  [[ -f "${ST_CONFIG_FILE}" ]] || fatal "未找到配置文件: ${ST_CONFIG_FILE}"

  local public_ip ssh_user auth_user
  public_ip="$(get_public_ip)"
  ssh_user="${SUDO_USER:-${USER:-root}}"

  log "--------------------------------------------------"
  msg_ok "SillyTavern 部署信息"
  log "--------------------------------------------------"

  if grep -q "basicAuthMode: true" "${ST_CONFIG_FILE}" 2>/dev/null; then
    auth_user="$(grep -m1 "username:" "${ST_CONFIG_FILE}" | sed 's/^[[:space:]]*username:[[:space:]]*//; s/"//g' || true)"
    log "访问地址: http://${public_ip}:8000"
    log "用户名: ${auth_user:-未知}"
    log "密码: 已隐藏；如需重置，请使用菜单“修改访问模式/用户名密码”。"
  else
    log "本机访问地址: http://127.0.0.1:8000"
    log "外网访问未开启。"
    log "如需远程访问，可使用 SSH 隧道："
    log "ssh -L 8000:127.0.0.1:8000 ${ssh_user}@${public_ip}"
    log "然后在本地浏览器打开: http://127.0.0.1:8000"
  fi

  if grep -q "watchtower:" "${ST_COMPOSE_FILE}" 2>/dev/null; then
    log "Watchtower 自动更新: 已启用"
  else
    log "Watchtower 自动更新: 未启用"
  fi

  log "部署目录: ${APP_DIR}"
  log "Compose 文件: ${ST_COMPOSE_FILE}"
  log "--------------------------------------------------"
}

status_st() {
  echo -n "   SillyTavern: "

  if [[ ! -f "${ST_COMPOSE_FILE}" ]]; then
    echo -e "${C_RED}未安装${C_RESET}"
    return 0
  fi

  if ! command -v docker &>/dev/null || ! detect_compose_cmd; then
    echo -e "${C_YELLOW}已生成配置，但 Docker/Compose 不可用${C_RESET}"
    return 0
  fi

  local container_id container_status
  container_id="$(cd "${APP_DIR}" && "${SUDO[@]}" "${COMPOSE_CMD[@]}" ps -q sillytavern 2>/dev/null || true)"

  if [[ -n "${container_id}" ]]; then
    container_status="$("${SUDO[@]}" docker inspect --format '{{.State.Status}}' "${container_id}" 2>/dev/null || true)"
    if [[ "${container_status}" == "running" ]]; then
      echo -e "${C_GREEN}已安装且正在运行${C_RESET}"
    else
      echo -e "${C_YELLOW}已安装但处于 ${container_status:-未知} 状态${C_RESET}"
    fi
  else
    echo -e "${C_YELLOW}已安装但容器未运行${C_RESET}"
  fi

  if [[ -f "${ST_CONFIG_FILE}" ]] && grep -q "basicAuthMode: true" "${ST_CONFIG_FILE}"; then
    local user
    user="$(grep -m1 "username:" "${ST_CONFIG_FILE}" | sed 's/^[[:space:]]*username:[[:space:]]*//; s/"//g' || true)"
    echo -e "     └─ 访问认证: ${C_GREEN}已开启${C_RESET} (${user:-未知用户})"
  else
    echo -e "     └─ 访问认证: ${C_YELLOW}未开启，本地访问模式${C_RESET}"
  fi

  if grep -q "127.0.0.1:8000:8000" "${ST_COMPOSE_FILE}" 2>/dev/null; then
    echo "     └─ 监听地址: http://127.0.0.1:8000"
  else
    echo "     └─ 监听地址: http://<你的服务器公网IP>:8000"
  fi
}

usage() {
  msg_error "用法: $0 {install|start|stop|restart|update|logs|backup|change_access|change_password|restore_access|status|info}"
}

case "${1:-}" in
  install) install_st ;;
  start) start_st ;;
  stop) stop_st ;;
  restart) restart_st ;;
  update) update_st ;;
  logs) logs_st ;;
  backup) backup_st ;;
  change_access|change_password) change_access_st ;;
  restore_access) restore_access_st ;;
  status) status_st ;;
  info) print_final_info ;;
  *)
    usage
    exit 1
    ;;
esac
