#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  ST_TOOLKIT_REQUIRE_SUDO=0
  ST_TOOLKIT_SKIP_COUNTRY=1
fi

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

APT_SWITCH_BACKUP_DIR=""

mirror_url_reachable() {
  local url="$1"

  if command -v curl &>/dev/null; then
    curl -fsL --connect-timeout 3 --max-time 8 -o /dev/null "${url}" &>/dev/null
    return $?
  fi

  if command -v wget &>/dev/null; then
    wget -q --spider --timeout=8 "${url}" &>/dev/null
    return $?
  fi

  return 2
}

precheck_mirror_url() {
  local label="$1"
  local url="$2"
  local rc

  msg_info "预检${label}: ${url}"
  if mirror_url_reachable "${url}"; then
    msg_ok "${label}可访问，继续切换。"
    return 0
  fi

  rc=$?
  if (( rc == 2 )); then
    msg_warn "未检测到 curl/wget，跳过${label}连通性预检。"
  else
    msg_warn "${label}预检未通过，后续刷新索引可能较慢或失败。"
  fi

  return 0
}

precheck_apt_mirror() {
  local base_url="$1"
  local codename="$2"
  local security_url="$3"

  precheck_mirror_url "APT 主源" "${base_url}/dists/${codename}/Release"
  precheck_mirror_url "APT 安全源" "${security_url}/dists/${codename}-security/Release"
}

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

warn_refresh_failed_with_backup() {
  local manager="$1"
  local backup_path="$2"

  msg_warn "${manager} 镜像索引刷新失败，源配置可能已写入但尚未验证可用。"
  if [[ -n "${backup_path}" ]]; then
    msg_warn "本次切换前备份: ${backup_path}"
  else
    msg_warn "本次未生成新的切换备份；如存在历史备份，仍可尝试恢复最近备份。"
  fi
  msg_warn "如需回滚，可运行: ${BASH_SOURCE[0]} restore"
}

fatal_restore_refresh_failed() {
  local manager="$1"

  msg_warn "${manager} 源已从最近备份恢复，但刷新索引仍失败。"
  msg_warn "请检查网络、DNS、代理或镜像站状态；必要时手动查看包管理器日志。"
  fatal "恢复后的源尚未通过刷新验证，请处理网络或源配置后重试。"
}

try_backup_source_file() {
  local result_var="$1"
  local src="$2"
  local dst="$3"

  printf -v "${result_var}" '%s' ""
  if "${SUDO[@]}" cp -a "${src}" "${dst}"; then
    printf -v "${result_var}" '%s' "${dst}"
    return 0
  fi

  msg_warn "未能备份 ${src}，继续切换但无法自动回滚本次变更。"
  return 1
}

backup_apt_sources_for_user_switch() {
  local ts backup_dir
  ts="$(date +%F_%H%M%S)"
  backup_dir="/etc/apt/sources.switch-backup.${ts}"
  APT_SWITCH_BACKUP_DIR="${backup_dir}"

  "${SUDO[@]}" mkdir -p "${backup_dir}/sources.list.d"

  if [[ -f /etc/apt/sources.list ]]; then
    "${SUDO[@]}" cp -a /etc/apt/sources.list "${backup_dir}/sources.list"
  fi

  shopt -s nullglob
  local f base
  for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    base="$(basename "${f}")"

    case "${base}" in
      docker.list|docker.sources)
        continue
        ;;
    esac

    "${SUDO[@]}" mv -f "${f}" "${backup_dir}/sources.list.d/"
  done
  shopt -u nullglob

  msg_ok "APT 源已备份到: ${backup_dir}"
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

find_latest_backup_path() {
  local pattern="$1"
  local dir name latest

  dir="$(dirname -- "${pattern}")"
  name="$(basename -- "${pattern}")"
  latest=""

  if stat -c '%Y %n' /dev/null >/dev/null 2>&1; then
    latest="$(
      find "${dir}" -maxdepth 1 -type f -name "${name}" -exec stat -c '%Y %n' {} \; 2>/dev/null |
        sort -nr |
        awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
    )"
  elif stat -f '%m %N' /dev/null >/dev/null 2>&1; then
    latest="$(
      find "${dir}" -maxdepth 1 -type f -name "${name}" -exec stat -f '%m %N' {} \; 2>/dev/null |
        sort -nr |
        awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
    )"
  else
    latest="$(
      find "${dir}" -maxdepth 1 -type f -name "${name}" -print 2>/dev/null |
        sort -r |
        awk 'NR == 1 { print; exit }'
    )"
  fi

  printf '%s\n' "${latest}"
}

find_latest_backup_dir() {
  local pattern="$1"
  local dir name latest

  dir="$(dirname -- "${pattern}")"
  name="$(basename -- "${pattern}")"
  latest=""

  if stat -c '%Y %n' /dev/null >/dev/null 2>&1; then
    latest="$(
      find "${dir}" -maxdepth 1 -type d -name "${name}" -exec stat -c '%Y %n' {} \; 2>/dev/null |
        sort -nr |
        awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
    )"
  elif stat -f '%m %N' /dev/null >/dev/null 2>&1; then
    latest="$(
      find "${dir}" -maxdepth 1 -type d -name "${name}" -exec stat -f '%m %N' {} \; 2>/dev/null |
        sort -nr |
        awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }'
    )"
  else
    latest="$(
      find "${dir}" -maxdepth 1 -type d -name "${name}" -print 2>/dev/null |
        sort -r |
        awk 'NR == 1 { print; exit }'
    )"
  fi

  printf '%s\n' "${latest}"
}

restore_latest_file_backup() {
  local target="$1"
  local pattern="$2"
  local latest=""

  latest="$(find_latest_backup_path "${pattern}")"
  [[ -n "${latest}" ]] || return 1

  "${SUDO[@]}" cp -a "${latest}" "${target}"
  msg_ok "已从 ${latest} 恢复到 ${target}"
}

restore_latest_apt_switch_backup() {
  local latest=""
  latest="$(find_latest_backup_dir "/etc/apt/sources.switch-backup.*")"
  [[ -n "${latest}" ]] || return 1

  if [[ -f "${latest}/sources.list" ]]; then
    "${SUDO[@]}" cp -a "${latest}/sources.list" /etc/apt/sources.list
  fi

  "${SUDO[@]}" mkdir -p /etc/apt/sources.list.d

  shopt -s nullglob
  local f
  for f in "${latest}"/sources.list.d/*.list "${latest}"/sources.list.d/*.sources; do
    "${SUDO[@]}" cp -a "${f}" /etc/apt/sources.list.d/
  done
  shopt -u nullglob

  msg_ok "已从 ${latest} 恢复 APT 源。"
}

restore_sources() {
  msg_info "正在恢复最近一次备份源..."

  case "${OS_FAMILY}" in
    debian)
      if restore_latest_apt_switch_backup || restore_latest_file_backup "/etc/apt/sources.list" "/etc/apt/sources.list.bak.*"; then
        if ! run_quiet "刷新 APT 索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3; then
          fatal_restore_refresh_failed "APT"
        fi
      else
        msg_warn "未找到 /etc/apt/sources.switch-backup.* 或 /etc/apt/sources.list.bak.* 备份。"
      fi
      ;;
    arch)
      if restore_latest_file_backup "/etc/pacman.d/mirrorlist" "/etc/pacman.d/mirrorlist.bak.*"; then
        if ! run_quiet "刷新 Pacman 索引" "${SUDO[@]}" pacman -Syy --noconfirm; then
          fatal_restore_refresh_failed "Pacman"
        fi
      else
        msg_warn "未找到 /etc/pacman.d/mirrorlist.bak.* 备份。"
      fi
      ;;
    alpine)
      if restore_latest_file_backup "/etc/apk/repositories" "/etc/apk/repositories.bak.*"; then
        if ! run_quiet "刷新 APK 索引" "${SUDO[@]}" apk update; then
          fatal_restore_refresh_failed "APK"
        fi
      else
        msg_warn "未找到 /etc/apk/repositories.bak.* 备份。"
      fi
      ;;
    *)
      msg_warn "当前系统 ${OS} 未实现通用恢复逻辑。"
      ;;
  esac
}

status_sources() {
  echo -n "   软件源: "

  case "${OS_FAMILY}" in
    debian)
      local source_text=""
      source_text="$(grep -RhsE "debian|ubuntu|aliyun|tencent|huawei|tuna|ustc" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | head -n 20 || true)"
      if grep -qi "aliyun" <<<"${source_text}"; then
        echo -e "${C_CYAN}阿里云${C_RESET}"
      elif grep -qi "tencent" <<<"${source_text}"; then
        echo -e "${C_CYAN}腾讯云${C_RESET}"
      elif grep -qi "huawei" <<<"${source_text}"; then
        echo -e "${C_CYAN}华为云${C_RESET}"
      elif grep -qiE "debian.org|ubuntu.com" <<<"${source_text}"; then
        echo -e "${C_CYAN}官方源${C_RESET}"
      else
        echo -e "${C_YELLOW}未知${C_RESET}"
      fi
      ;;
    arch)
      if grep -qE "aliyun|tencent|huawei|tuna|ustc" /etc/pacman.d/mirrorlist 2>/dev/null; then
        echo -e "${C_CYAN}国内镜像${C_RESET}"
      else
        echo -e "${C_CYAN}默认/未知${C_RESET}"
      fi
      ;;
    alpine)
      if grep -qE "aliyun|tencent|huawei|tuna|ustc" /etc/apk/repositories 2>/dev/null; then
        echo -e "${C_CYAN}国内镜像${C_RESET}"
      else
        echo -e "${C_CYAN}默认/未知${C_RESET}"
      fi
      ;;
    redhat|suse)
      echo -e "${C_YELLOW}未自动管理，避免破坏企业源${C_RESET}"
      ;;
    *)
      echo -e "${C_YELLOW}未知${C_RESET}"
      ;;
  esac
}

usage() {
  msg_error "用法: $0 {set <aliyun|tencent|huawei>|restore|status}"
}

case "${1:-}" in
  set)
    set_mirror "${2:-}"
    ;;
  restore)
    restore_sources
    ;;
  status)
    status_sources
    ;;
  *)
    usage
    exit 1
    ;;
esac
