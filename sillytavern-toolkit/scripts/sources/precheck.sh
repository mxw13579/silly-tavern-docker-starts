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

warn_refresh_failed_with_backup() {
  local manager="$1"
  local backup_path="$2"

  msg_warn "${manager} 镜像索引刷新失败，源配置可能已写入但尚未验证可用。"
  if [[ -n "${backup_path}" ]]; then
    msg_warn "本次切换前备份: ${backup_path}"
  else
    msg_warn "本次未生成新的切换备份；如存在历史备份，仍可尝试恢复最近备份。"
  fi
  msg_warn "如需回滚，可运行: ${ST_SOURCES_ENTRYPOINT:-${BASH_SOURCE[0]}} restore"
}

fatal_restore_refresh_failed() {
  local manager="$1"

  msg_warn "${manager} 源已从最近备份恢复，但刷新索引仍失败。"
  msg_warn "请检查网络、DNS、代理或镜像站状态；必要时手动查看包管理器日志。"
  fatal "恢复后的源尚未通过刷新验证，请处理网络或源配置后重试。"
}
