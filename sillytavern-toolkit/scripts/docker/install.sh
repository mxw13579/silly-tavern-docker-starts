#!/usr/bin/env bash

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

confirm_enterprise_docker_repo() {
  case "${OS}" in
    rhel|ol|oracle)
      ;;
    *)
      return 0
      ;;
  esac

  if [[ ! -r /dev/tty ]]; then
    fatal "当前环境没有可交互 TTY，无法确认添加 Docker repo 文件 /etc/yum.repos.d/docker-ce.repo。请在交互终端运行或手动配置 Docker 源。"
  fi

  local answer=""
  msg_warn "检测到企业发行版 ${OS}。继续安装会添加 Docker repo 文件 /etc/yum.repos.d/docker-ce.repo。"
  read -r -p "是否继续添加 Docker repo 文件？(y/n): " answer </dev/tty

  case "${answer}" in
    [Yy]*) return 0 ;;
    *) fatal "已取消添加 Docker repo 文件。" ;;
  esac
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

  confirm_enterprise_docker_repo

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

restart_docker_service_restore() {
  # restore 流程专用：不调用 fatal/exit，保证调用方可以先回滚再报错。
  if ! command -v docker &>/dev/null; then
    msg_error "Docker 未安装，无法重启。"
    return 1
  fi

  case "${INIT_SYSTEM}" in
    systemd)
      "${SUDO[@]}" systemctl daemon-reload || true
      if run_quiet "重启 Docker 服务" "${SUDO[@]}" systemctl restart docker; then
        return 0
      fi
      return 1
      ;;
    openrc)
      if run_quiet "重启 Docker 服务" "${SUDO[@]}" rc-service docker restart; then
        return 0
      fi
      return 1
      ;;
    *)
      msg_error "当前环境没有 systemd/openrc，请手动重启 Docker。"
      return 1
      ;;
  esac
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
