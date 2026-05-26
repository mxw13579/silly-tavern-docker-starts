#!/usr/bin/env bash

list_docker_images() {
  command -v docker &>/dev/null || fatal "Docker 未安装，无法查看镜像。"
  "${SUDO[@]}" docker images
}

status_docker() {
  echo -n "   Docker 环境: "
  if ! command -v docker &>/dev/null; then
    echo -e "${C_RED}未安装${C_RESET}"
    return 0
  fi

  local version=""
  version="$(docker -v 2>/dev/null | awk '{print $3}' | sed 's/,//' || true)"

  if "${SUDO[@]}" docker info &>/dev/null; then
    echo -e "${C_GREEN}已安装 (v${version:-未知}) 且正在运行${C_RESET}"
  else
    echo -e "${C_YELLOW}已安装 (v${version:-未知}) 但未运行或当前用户无权限${C_RESET}"
  fi

  if detect_compose_cmd; then
    echo -e "     └─ Compose: ${C_GREEN}${COMPOSE_CMD[*]}${C_RESET}"
  else
    echo -e "     └─ Compose: ${C_YELLOW}未检测到${C_RESET}"
  fi

  if [[ -f /etc/docker/daemon.json ]] && grep -q "registry-mirrors" /etc/docker/daemon.json; then
    echo -e "     └─ 镜像加速: ${C_GREEN}已配置${C_RESET}"
  else
    echo -e "     └─ 镜像加速: ${C_YELLOW}未配置${C_RESET}"
  fi
}
