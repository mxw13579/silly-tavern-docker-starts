backup_existing_toolkit() {
  [[ -e "${TOOLKIT_DIR}" ]] || return 0

  local backup_dir
  backup_dir="${TOOLKIT_DIR}.bak_$(date +%Y%m%d_%H%M%S)"
  msg_warn "检测到已存在的工具箱目录，将备份为: ${backup_dir}"
  mv "${TOOLKIT_DIR}" "${backup_dir}"
}

atomic_replace_dir() {
  local src_dir="$1"
  local dst_dir="$2"
  local target_parent target_name staging_dir backup_dir ts n

  target_parent="$(dirname "${dst_dir}")"
  target_name="$(basename "${dst_dir}")"
  if ! mkdir -p "${target_parent}"; then
    fatal "创建工具箱目录父目录失败: ${target_parent}"
  fi
  staging_dir="$(mktemp -d "${target_parent}/.${target_name}.tmp.XXXXXX")"
  rmdir "${staging_dir}"

  if ! mv "${src_dir}" "${staging_dir}"; then
    rm -rf "${staging_dir}" 2>/dev/null || true
    fatal "准备工具箱临时目录失败。"
  fi

  if [[ -e "${dst_dir}" ]]; then
    ts="$(date +%Y%m%d_%H%M%S)"
    backup_dir="${dst_dir}.bak_${ts}"
    n=0
    while [[ -e "${backup_dir}" ]]; do
      n=$((n + 1))
      backup_dir="${dst_dir}.bak_${ts}.${n}"
    done
    msg_warn "检测到已存在的工具箱目录，将备份为: ${backup_dir}"
    if ! mv "${dst_dir}" "${backup_dir}"; then
      rm -rf "${staging_dir}" 2>/dev/null || true
      fatal "备份现有工具箱目录失败。"
    fi
  fi

  if mv "${staging_dir}" "${dst_dir}"; then
    return 0
  fi

  rm -rf "${staging_dir}" 2>/dev/null || true
  if [[ -n "${backup_dir:-}" && -e "${backup_dir}" && ! -e "${dst_dir}" ]]; then
    mv "${backup_dir}" "${dst_dir}" || true
  fi
  fatal "替换工具箱目录失败。"
}
