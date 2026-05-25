#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  ST_TOOLKIT_REQUIRE_SUDO=0
  ST_TOOLKIT_SKIP_COUNTRY=1
fi

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

install_docker_debian_fallback() {
  msg_warn "尝试使用系统源安装 Docker 作为兜底方案..."
  "${SUDO[@]}" rm -f /etc/apt/sources.list.d/docker.list || true
  ensure_apt_ready_debian

  if run_quiet "安装系统源 Docker" "${SUDO[@]}" apt-get install -y docker.io docker-compose-plugin; then
    return 0
  fi

  if run_quiet "安装系统源 Docker 与 docker-compose" "${SUDO[@]}" apt-get install -y docker.io docker-compose; then
    return 0
  fi

  fatal "Docker 官方源和系统源安装均失败。"
}

install_docker_debian() {
  msg_info "安装 Docker..."
  install_base_packages

  local docker_repo_url="https://download.docker.com"
  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    docker_repo_url="https://mirrors.cloud.tencent.com/docker-ce"
  fi

  run_quiet "移除旧 Docker 包" "${SUDO[@]}" apt-get remove -y docker docker-engine docker.io containerd runc || true

  "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
  "${SUDO[@]}" rm -f /etc/apt/keyrings/docker.gpg

  local tmp_gpg codename
  tmp_gpg="$(mktemp)"

  if ! fetch_url_quiet "${docker_repo_url}/linux/${DOCKER_REPO_OS}/gpg" >"${tmp_gpg}"; then
    rm -f "${tmp_gpg}"
    install_docker_debian_fallback
    return 0
  fi

  if ! "${SUDO[@]}" gpg --dearmor -o /etc/apt/keyrings/docker.gpg "${tmp_gpg}" >/dev/null 2>&1; then
    rm -f "${tmp_gpg}"
    install_docker_debian_fallback
    return 0
  fi

  rm -f "${tmp_gpg}"
  "${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.gpg

  codename="$(get_docker_apt_codename)"
  [[ -n "${codename}" ]] || {
    install_docker_debian_fallback
    return 0
  }

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${docker_repo_url}/linux/${DOCKER_REPO_OS} ${codename} stable" \
    | "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null

  if ! run_quiet "刷新 Docker APT 源" "${SUDO[@]}" apt-get update -o Acquire::Retries=3; then
    install_docker_debian_fallback
    return 0
  fi

  if ! run_quiet "安装 Docker" "${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    install_docker_debian_fallback
    return 0
  fi
}

install_docker_redhat_fallback() {
  msg_warn "尝试使用系统源安装 Docker 作为兜底方案..."
  "${SUDO[@]}" rm -f /etc/yum.repos.d/docker-ce.repo || true
  run_quiet "刷新软件源缓存" "${SUDO[@]}" "${PKG_MANAGER}" makecache || true

  if run_quiet "安装系统源 Docker" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker docker-compose-plugin; then
    return 0
  fi

  if run_quiet "安装系统源 Docker 与 docker-compose" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker docker-compose; then
    return 0
  fi

  fatal "Docker 官方源和系统源安装均失败。"
}

install_docker_redhat() {
  msg_info "安装 Docker..."
  install_base_packages

  local repo_url=""
  case "${OS}" in
    fedora)
      repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
      [[ "${USE_CHINA_MIRROR}" == "true" ]] && repo_url="https://mirrors.cloud.tencent.com/docker-ce/linux/fedora/docker-ce.repo"
      ;;
    *)
      repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
      [[ "${USE_CHINA_MIRROR}" == "true" ]] && repo_url="https://mirrors.cloud.tencent.com/docker-ce/linux/centos/docker-ce.repo"
      ;;
  esac

  run_quiet "移除旧 Docker 包" "${SUDO[@]}" "${PKG_MANAGER}" remove -y \
    docker docker-client docker-client-latest docker-common docker-latest \
    docker-latest-logrotate docker-logrotate docker-engine || true

  local tmp_repo
  tmp_repo="$(mktemp)"

  if ! safe_curl_download -o "${tmp_repo}" "${repo_url}"; then
    rm -f "${tmp_repo}"
    install_docker_redhat_fallback
    return 0
  fi

  "${SUDO[@]}" mkdir -p /etc/yum.repos.d
  "${SUDO[@]}" cp "${tmp_repo}" /etc/yum.repos.d/docker-ce.repo
  rm -f "${tmp_repo}"

  if ! run_quiet "刷新 Docker 软件源缓存" "${SUDO[@]}" "${PKG_MANAGER}" makecache; then
    install_docker_redhat_fallback
    return 0
  fi

  if ! run_quiet "安装 Docker" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    install_docker_redhat_fallback
    return 0
  fi
}

install_docker_arch() {
  install_base_packages
  run_quiet "安装 Docker" "${SUDO[@]}" pacman -S --noconfirm docker docker-compose
}

install_docker_alpine() {
  install_base_packages

  if ! run_quiet "安装 Docker" "${SUDO[@]}" apk add --no-cache docker docker-cli-compose; then
    run_quiet "安装 Docker" "${SUDO[@]}" apk add --no-cache docker docker-compose
  fi
}

install_docker_suse() {
  install_base_packages
  run_quiet "安装 Docker" "${SUDO[@]}" zypper --non-interactive install docker docker-compose
}

ensure_docker_running() {
  if "${SUDO[@]}" docker info &>/dev/null; then
    return 0
  fi

  case "${INIT_SYSTEM}" in
    systemd)
      run_quiet "启动 Docker 服务" "${SUDO[@]}" systemctl enable --now docker || fatal "Docker 启动失败。"
      ;;
    openrc)
      "${SUDO[@]}" rc-update add docker boot || true
      run_quiet "启动 Docker 服务" "${SUDO[@]}" rc-service docker start || fatal "Docker 启动失败。"
      ;;
    *)
      fatal "当前环境没有 systemd/openrc，且 Docker 未运行。请手动启动 Docker 后重试。"
      ;;
  esac

  "${SUDO[@]}" docker info &>/dev/null || fatal "Docker 未正常运行。"
}

restart_docker_service() {
  command -v docker &>/dev/null || fatal "Docker 未安装，无法重启。"

  case "${INIT_SYSTEM}" in
    systemd)
      "${SUDO[@]}" systemctl daemon-reload || true
      run_quiet "重启 Docker 服务" "${SUDO[@]}" systemctl restart docker
      ;;
    openrc)
      run_quiet "重启 Docker 服务" "${SUDO[@]}" rc-service docker restart
      ;;
    *)
      fatal "当前环境没有 systemd/openrc，请手动重启 Docker。"
      ;;
  esac
}

configure_docker_mirror_safe() {
  if [[ "${USE_CHINA_MIRROR}" != "true" ]]; then
    msg_warn "非中国大陆服务器或地区检测失败，跳过 Docker 镜像加速配置。"
    return 0
  fi

  if [[ -f /etc/docker/daemon.json ]] && grep -q '"registry-mirrors"' /etc/docker/daemon.json; then
    msg_ok "Docker 镜像加速已配置，跳过修改。"
    return 0
  fi

  msg_info "配置 Docker 国内镜像加速..."
  "${SUDO[@]}" mkdir -p /etc/docker

  if [[ -f /etc/docker/daemon.json ]]; then
    "${SUDO[@]}" cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%F_%H%M%S)" || true
  fi

  if command -v python3 &>/dev/null; then
    "${SUDO[@]}" python3 <<'PY'
import json
from datetime import datetime
from pathlib import Path

path = Path("/etc/docker/daemon.json")
mirror = "https://mirror.ccs.tencentyun.com"
data = {}

if path.exists() and path.read_text().strip():
    try:
        data = json.loads(path.read_text())
    except Exception:
        backup = path.with_name(f"daemon.json.invalid.{datetime.now().strftime('%Y-%m-%d_%H%M%S')}")
        backup.write_text(path.read_text())
        data = {}

mirrors = data.get("registry-mirrors", [])
if not isinstance(mirrors, list):
    mirrors = []

if mirror not in mirrors:
    mirrors.insert(0, mirror)

data["registry-mirrors"] = mirrors
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
  else
    if [[ ! -s /etc/docker/daemon.json ]]; then
      cat <<'EOF' | "${SUDO[@]}" tee /etc/docker/daemon.json >/dev/null
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com"
  ]
}
EOF
    else
      msg_warn "python3 不存在且 daemon.json 已存在，为避免覆盖，跳过 Docker 镜像加速自动合并。"
      return 0
    fi
  fi

  restart_docker_service
  msg_ok "Docker 镜像加速配置完成。"
}

install_or_verify_docker() {
  msg_info "检查 Docker..."

  if ! command -v docker &>/dev/null; then
    case "${OS_FAMILY}" in
      debian) install_docker_debian ;;
      redhat) install_docker_redhat ;;
      arch) install_docker_arch ;;
      alpine) install_docker_alpine ;;
      suse) install_docker_suse ;;
      *) fatal "不支持的系统系列: ${OS_FAMILY}" ;;
    esac
  else
    msg_ok "Docker 已安装，跳过安装。"
  fi

  command -v docker &>/dev/null || fatal "Docker 安装失败。"
  ensure_docker_running
  configure_docker_mirror_safe
  ensure_docker_running
}

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

usage() {
  msg_error "用法: $0 {install|compose|config_mirror|restart_service|list_images|status}"
}

case "${1:-}" in
  install)
    install_or_verify_docker
    setup_docker_compose
    ;;
  compose)
    setup_docker_compose
    ;;
  config_mirror)
    configure_docker_mirror_safe
    ;;
  restart_service)
    restart_docker_service
    ;;
  list_images)
    list_docker_images
    ;;
  status)
    status_docker
    ;;
  *)
    usage
    exit 1
    ;;
esac
