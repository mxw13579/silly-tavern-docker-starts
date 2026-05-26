#!/usr/bin/env bash

# 说明：
# - 本文件会被 sillytavern.sh 作为子模块 source。
# - 依赖 common.sh 提供的工具函数与变量（如 fetch_url_quiet/detect_compose_cmd 等）。

get_public_ip() {
  local public_ip=""
  public_ip="$(fetch_url_quiet "https://ipinfo.io/ip" 2>/dev/null | tr -d '\r\n' || true)"
  [[ -n "${public_ip}" ]] || public_ip="<你的服务器公网IP>"
  printf '%s' "${public_ip}"
}

read_st_config_file() {
  [[ -f "${ST_CONFIG_FILE}" ]] || return 1

  if [[ -r "${ST_CONFIG_FILE}" ]]; then
    cat "${ST_CONFIG_FILE}"
    return 0
  fi

  if declare -p SUDO >/dev/null 2>&1 && ((${#SUDO[@]} > 0)); then
    "${SUDO[@]}" cat "${ST_CONFIG_FILE}" 2>/dev/null
    return
  fi

  return 1
}

print_final_info() {
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "SillyTavern 尚未安装，无法显示部署信息。"
  [[ -f "${ST_CONFIG_FILE}" ]] || fatal "未找到配置文件: ${ST_CONFIG_FILE}"

  local config_content public_ip ssh_user auth_user
  config_content="$(read_st_config_file)" || fatal "配置文件不可读，无法显示部署信息: ${ST_CONFIG_FILE}"
  public_ip="$(get_public_ip)"
  ssh_user="${SUDO_USER:-${USER:-root}}"

  log "--------------------------------------------------"
  msg_ok "SillyTavern 部署信息"
  log "--------------------------------------------------"

  if grep -q "basicAuthMode: true" <<<"${config_content}"; then
    auth_user="$(grep -m1 "username:" <<<"${config_content}" | sed 's/^[[:space:]]*username:[[:space:]]*//; s/\"//g' || true)"
    log "访问地址: http://${public_ip}:8000"
    log "用户名: ${auth_user:-未知}"
    log "密码: 已隐藏；如需重置，请使用菜单'修改访问模式/用户名密码'。"
  else
    log "本机访问地址: http://127.0.0.1:8000"
    log "外网访问未开启。"
    log "如需远程访问，可使用 SSH 隧道:"
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

print_auth_status() {
  local config_content user

  if [[ ! -f "${ST_CONFIG_FILE}" ]]; then
    echo -e "     - 访问认证: ${C_YELLOW}配置文件不存在${C_RESET}"
    return 0
  fi

  if ! config_content="$(read_st_config_file)"; then
    echo -e "     - 访问认证: ${C_YELLOW}配置文件不可读，无法判断${C_RESET}"
    return 0
  fi

  if grep -q "basicAuthMode: true" <<<"${config_content}"; then
    user="$(grep -m1 "username:" <<<"${config_content}" | sed 's/^[[:space:]]*username:[[:space:]]*//; s/\"//g' || true)"
    echo -e "     - 访问认证: ${C_GREEN}已开启${C_RESET} (${user:-未知用户})"
  else
    echo -e "     - 访问认证: ${C_YELLOW}未开启，本地访问模式${C_RESET}"
  fi
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

  print_auth_status

  if grep -q "127.0.0.1:8000:8000" "${ST_COMPOSE_FILE}" 2>/dev/null; then
    echo "     - 监听地址: http://127.0.0.1:8000"
  else
    echo "     - 监听地址: http://<你的服务器公网IP>:8000"
  fi
}
