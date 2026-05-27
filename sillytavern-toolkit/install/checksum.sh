verify_checksums_manifest() {
  local root_dir="$1"
  local manifest_file="$2"
  shift 2
  local expected_files=("$@")

  [[ -n "${CHECKSUMS_URL}" ]] || return 0
  command -v sha256sum &>/dev/null || fatal "启用 checksum 校验需要 sha256sum。"

  msg_warn "checksum 仅校验下载后的工具箱文件，不保护当前已执行的 bootstrap installer。"

  local line hash path actual found
  for line in "${expected_files[@]}"; do
    found=false
    while read -r hash path _ || [[ -n "${hash:-}${path:-}" ]]; do
      [[ -n "${hash:-}" ]] || continue
      [[ "${hash}" == \#* ]] && continue
      [[ "${hash}" =~ ^[0-9A-Fa-f]{64}$ ]] || fatal "checksum manifest hash 格式错误: ${hash}"
      [[ -n "${path:-}" ]] || fatal "checksum manifest 格式错误。"
      path="${path#\*}"
      [[ "${path}" != /* && "${path}" != *".."* ]] || fatal "checksum manifest 包含不安全路径: ${path}"
      if [[ "${path}" == "${line}" ]]; then
        found=true
        [[ -f "${root_dir}/${path}" ]] || fatal "checksum 目标文件不存在: ${path}"
        actual="$(sha256sum "${root_dir}/${path}" | awk '{print $1}')"
        [[ "${actual}" == "${hash}" ]] || fatal "checksum 不匹配: ${path}"
      fi
    done <"${manifest_file}"
    [[ "${found}" == "true" ]] || fatal "checksum manifest 缺失条目: ${line}"
  done

  msg_ok "工具箱文件 checksum 校验通过。"
}
