arch_mirror_server() {
  local provider="$1"

  case "${provider}" in
    aliyun) echo "https://mirrors.aliyun.com/archlinux" ;;
    tencent) echo "https://mirrors.cloud.tencent.com/archlinux" ;;
    huawei) echo "https://repo.huaweicloud.com/archlinux" ;;
    *) return 1 ;;
  esac
}

arch_mirror_precheck_url() {
  local provider="$1"
  local server=""

  server="$(arch_mirror_server "${provider}")" || return 1
  printf '%s\n' "${server}/lastsync"
}

alpine_mirror_precheck_url() {
  local host="$1"
  local apk_arch="x86_64"

  if command -v apk &>/dev/null; then
    apk_arch="$(apk --print-arch 2>/dev/null || true)"
  fi

  [[ -n "${apk_arch}" ]] || apk_arch="x86_64"
  printf '%s\n' "${host}/alpine/latest-stable/main/${apk_arch}/APKINDEX.tar.gz"
}

set_debian_or_ubuntu_mirror() {
  local provider="$1"

  if [[ "${OS}" != "debian" && "${OS}" != "ubuntu" ]]; then
    msg_warn "检测到 Debian/Ubuntu 衍生系统 ${OS}，为避免误改系统源，跳过系统源替换。"
    return 0
  fi

  local codename base_url components
  codename="$(get_apt_codename)"
  [[ -n "${codename}" ]] || fatal "无法获取系统代号 VERSION_CODENAME。"

  if [[ "${OS}" == "debian" ]]; then
    components="$(debian_components)"
    base_url="$(mirror_host_for_provider "${provider}" "debian")" || fatal "不支持的镜像源: ${provider}"

    local security_url="${base_url}-security"
    if [[ "${provider}" == "aliyun" ]]; then
      security_url="http://mirrors.aliyun.com/debian-security"
    fi

    precheck_apt_mirror "${base_url}" "${codename}" "${security_url}"
    backup_apt_sources_for_user_switch
    write_debian_sources "${codename}" "${components}" "${base_url}" "${security_url}"
  else
    base_url="$(mirror_host_for_provider "${provider}" "ubuntu")" || fatal "不支持的镜像源: ${provider}"
    precheck_apt_mirror "${base_url}" "${codename}" "${base_url}"
    backup_apt_sources_for_user_switch
    write_ubuntu_sources "${codename}" "${base_url}"
  fi

  "${SUDO[@]}" rm -rf /var/lib/apt/lists/*
  if ! run_quiet "刷新 APT 镜像索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3; then
    warn_refresh_failed_with_backup "APT" "${APT_SWITCH_BACKUP_DIR}"
    fatal "APT 索引刷新失败。请先回滚或修复软件源后再继续安装。"
  fi
}

set_arch_mirror() {
  local provider="$1"
  local backup_path=""
  local backup_candidate=""
  local server_url=""
  local precheck_url=""

  precheck_url="$(arch_mirror_precheck_url "${provider}")" || fatal "不支持的镜像源: ${provider}"
  server_url="$(arch_mirror_server "${provider}")" || fatal "不支持的镜像源: ${provider}"
  precheck_mirror_url "Arch 镜像" "${precheck_url}"

  if ! grep -Fq "${server_url#https://}" /etc/pacman.d/mirrorlist 2>/dev/null; then
    backup_candidate="/etc/pacman.d/mirrorlist.bak.$(date +%F_%H%M%S)"
    try_backup_source_file backup_path /etc/pacman.d/mirrorlist "${backup_candidate}" || true
    "${SUDO[@]}" sed -i "1s|^|Server = ${server_url}/\$repo/os/\$arch\\n|" /etc/pacman.d/mirrorlist
  fi

  if ! run_quiet "刷新 Pacman 镜像索引" "${SUDO[@]}" pacman -Syy --noconfirm; then
    warn_refresh_failed_with_backup "Pacman" "${backup_path}"
    fatal "Pacman 索引刷新失败。请先回滚或修复软件源后再继续安装。"
  fi
}

set_alpine_mirror() {
  local provider="$1"
  local host=""
  local backup_candidate="/etc/apk/repositories.bak.$(date +%F_%H%M%S)"
  local backup_path=""

  case "${provider}" in
    aliyun) host="https://mirrors.aliyun.com" ;;
    tencent) host="https://mirrors.cloud.tencent.com" ;;
    huawei) host="https://repo.huaweicloud.com" ;;
    *) fatal "不支持的镜像源: ${provider}" ;;
  esac

  precheck_mirror_url "Alpine 镜像" "$(alpine_mirror_precheck_url "${host}")"

  try_backup_source_file backup_path /etc/apk/repositories "${backup_candidate}" || true
  "${SUDO[@]}" sed -i "s|https://dl-cdn.alpinelinux.org|${host}|g; s|http://dl-cdn.alpinelinux.org|${host}|g" /etc/apk/repositories
  if ! run_quiet "刷新 APK 镜像索引" "${SUDO[@]}" apk update; then
    warn_refresh_failed_with_backup "APK" "${backup_path}"
    fatal "APK 索引刷新失败。请先回滚或修复软件源后再继续安装。"
  fi
}

set_mirror() {
  local provider="${1:-}"
  [[ "${provider}" =~ ^(aliyun|tencent|huawei)$ ]] || fatal "镜像源必须是 aliyun、tencent 或 huawei。"

  msg_info "准备切换到 ${provider} 源..."

  case "${OS_FAMILY}" in
    debian)
      set_debian_or_ubuntu_mirror "${provider}"
      ;;
    arch)
      set_arch_mirror "${provider}"
      ;;
    alpine)
      set_alpine_mirror "${provider}"
      ;;
    redhat|suse)
      msg_warn "为避免破坏企业源，${OS} 暂不自动替换系统源。Docker 源会在 Docker 安装时按地区选择。"
      ;;
    *)
      fatal "当前操作系统 ${OS} 的自动切换源功能暂不支持。"
      ;;
  esac

  msg_ok "软件源处理完成。"
}
