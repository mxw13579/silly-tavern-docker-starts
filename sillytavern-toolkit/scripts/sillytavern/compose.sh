#!/usr/bin/env bash

# 说明：
# - 本文件会被 sillytavern.sh 作为子模块 source。
# - 依赖 common.sh 提供的工具函数与变量（如 msg_ok/compose_quiet/detect_compose_cmd 等）。

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
