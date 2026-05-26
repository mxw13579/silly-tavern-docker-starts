#!/usr/bin/env bash

# 说明：
# - 本文件会被 sillytavern.sh 作为子模块 source。
# - 依赖 common.sh 提供的工具函数与变量（如 msg_info/fatal/validate_credential 等）。

bool_to_yn() {
  local value="${1:-}"
  local default="${2:-n}"

  if [[ -z "${value}" ]]; then
    printf '%s' "${default}"
    return 0
  fi

  case "${value}" in
    1|y|Y|yes|YES|true|TRUE|on|ON) printf 'y' ;;
    0|n|N|no|NO|false|FALSE|off|OFF) printf 'n' ;;
    *) return 1 ;;
  esac
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

  "${SUDO[@]}" chmod 600 "${ST_CONFIG_FILE}" || true
  "${SUDO[@]}" chown -R 1000:1000 "${APP_DIR}/config" || true
}

read_safe_username() {
  local input=""

  while true; do
    read -r -p "请输入用户名，仅允许 A-Z、a-z、0-9、.、_、@、-，且不能为纯数字: " input </dev/tty
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
    read -r -s -p "请输入密码，仅允许 A-Z、a-z、0-9、.、_、@、-，且不能为纯数字: " input </dev/tty
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

configure_sillytavern_non_interactive() {
  msg_info "配置 SillyTavern（非交互模式）..."

  local access_mode auth_user auth_pass
  access_mode="${ST_ACCESS_MODE:-}"
  if [[ -z "${access_mode}" ]]; then
    fatal "非交互模式下必须设置 ST_ACCESS_MODE=local 或 ST_ACCESS_MODE=public。"
  fi

  case "${access_mode}" in
    local) ENABLE_EXTERNAL_ACCESS="n" ;;
    public) ENABLE_EXTERNAL_ACCESS="y" ;;
    *) fatal "ST_ACCESS_MODE 值非法: ${access_mode}（仅支持 local/public）" ;;
  esac

  if ! ENABLE_WATCHTOWER="$(bool_to_yn "${ST_ENABLE_WATCHTOWER:-}" "n")"; then
    fatal "ST_ENABLE_WATCHTOWER 值非法: ${ST_ENABLE_WATCHTOWER}（支持 1/0, y/n, true/false, on/off）"
  fi

  if [[ "${ENABLE_EXTERNAL_ACCESS}" == "y" ]]; then
    auth_user="${ST_AUTH_USER:-}"
    auth_pass="${ST_AUTH_PASS:-}"

    [[ -n "${auth_user}" ]] || fatal "非交互模式下 ST_ACCESS_MODE=public 时必须设置 ST_AUTH_USER。"
    [[ -n "${auth_pass}" ]] || fatal "非交互模式下 ST_ACCESS_MODE=public 时必须设置 ST_AUTH_PASS。"

    # 关键要求：public 模式必须先校验凭证，再写 compose/config
    validate_credential "${auth_user}" || fatal "用户名格式非法。"
    validate_credential "${auth_pass}" || fatal "密码格式非法。"

    generate_compose_file "${ENABLE_EXTERNAL_ACCESS}" "${ENABLE_WATCHTOWER}"
    write_sillytavern_config "y" "${auth_user}" "${auth_pass}"
    msg_ok "已开启外网访问并配置 Basic Auth（非交互）。"
  else
    generate_compose_file "${ENABLE_EXTERNAL_ACCESS}" "${ENABLE_WATCHTOWER}"
    write_sillytavern_config "n"
    msg_ok "未开启外网访问，仅允许本机访问端口（非交互）。"
  fi

  prepare_app_dirs
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

    validate_credential "${username}" || fatal "用户名格式非法。"
    validate_credential "${password}" || fatal "密码格式非法。"
    generate_compose_file "${ENABLE_EXTERNAL_ACCESS}" "${ENABLE_WATCHTOWER}"
    write_sillytavern_config "y" "${username}" "${password}"
    msg_ok "已开启外网访问并配置 Basic Auth。"
  else
    generate_compose_file "${ENABLE_EXTERNAL_ACCESS}" "${ENABLE_WATCHTOWER}"
    write_sillytavern_config "n"
    msg_ok "未开启外网访问，仅允许本机访问端口。"
  fi

  prepare_app_dirs
}
