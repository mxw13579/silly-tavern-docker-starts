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
