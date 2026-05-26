#!/usr/bin/env bash

setup_docker_compose() {
  msg_info "检查 Docker Compose..."

  if detect_compose_cmd; then
    msg_ok "Compose 命令: ${COMPOSE_CMD[*]}"
    return 0
  fi

  msg_warn "未检测到 Docker Compose，尝试安装..."

  case "${OS_FAMILY}" in
    debian)
      ensure_apt_ready_debian
      if ! run_quiet "安装 Docker Compose 插件" "${SUDO[@]}" apt-get install -y docker-compose-plugin; then
        run_quiet "安装 docker-compose" "${SUDO[@]}" apt-get install -y docker-compose
      fi
      ;;
    redhat)
      run_quiet "安装 Docker Compose 插件" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker-compose-plugin
      ;;
    arch)
      run_quiet "安装 Docker Compose" "${SUDO[@]}" pacman -S --noconfirm docker-compose
      ;;
    alpine)
      if ! run_quiet "安装 Docker Compose" "${SUDO[@]}" apk add --no-cache docker-cli-compose; then
        run_quiet "安装 Docker Compose" "${SUDO[@]}" apk add --no-cache docker-compose
      fi
      ;;
    suse)
      run_quiet "安装 Docker Compose" "${SUDO[@]}" zypper --non-interactive install docker-compose
      ;;
  esac

  detect_compose_cmd || fatal "Docker Compose 安装失败。"
  msg_ok "Compose 命令: ${COMPOSE_CMD[*]}"
}
