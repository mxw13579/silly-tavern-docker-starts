confirm_proxy_download() {
  if [[ "${ASSUME_YES}" == "true" ]]; then
    return 0
  fi

  msg_warn "中国区安装将通过第三方代理 ghfast.top 下载脚本文件。"
  msg_warn "该方式可改善 GitHub 访问，但存在代理服务可用性和供应链信任风险。"

  if [[ ! -t 0 || ! -t 1 || ! -r /dev/tty ]]; then
    fatal "当前环境非交互。请传入 --yes 或设置 ST_TOOLKIT_YES=1 接受代理下载风险。"
  fi

  local answer=""
  read -r -p "是否继续通过 ghfast.top 下载？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*) return 0 ;;
    *) fatal "已取消安装。" ;;
  esac
}

install_from_proxy() {
  (
    install_dependency "curl"
    confirm_proxy_download

    local proxy_url base_url temp_dir manifest_file
    proxy_url="https://ghfast.top"
    base_url="${proxy_url}/https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${TOOLKIT_REF}/${REPO_PATH}"
    temp_dir="$(mktemp -d)"
    manifest_file=""

    cleanup_proxy_tmp() {
      rm -rf "${temp_dir}" 2>/dev/null || true
    }
    trap cleanup_proxy_tmp EXIT

    local files=(
      "install.sh"
      "install/logging.sh"
      "install/options.sh"
      "install/os.sh"
      "install/checksum.sh"
      "install/filesystem.sh"
      "install/installers.sh"
      "st-toolkit.sh"
      "scripts/common.sh"
      "scripts/docker.sh"
      "scripts/health.sh"
      "scripts/sillytavern.sh"
      "scripts/sources.sh"
      "scripts/sources/precheck.sh"
      "scripts/sources/backup.sh"
      "scripts/sources/providers.sh"
      "scripts/sources/status.sh"
      "scripts/lib/logging.sh"
      "scripts/lib/input.sh"
      "scripts/lib/network.sh"
      "scripts/lib/os.sh"
      "scripts/lib/apt.sh"
      "scripts/lib/packages.sh"
      "scripts/lib/compose.sh"
      "scripts/docker/install.sh"
      "scripts/docker/mirror.sh"
      "scripts/docker/mirror/probe.sh"
      "scripts/docker/mirror/config.sh"
      "scripts/docker/mirror/restore.sh"
      "scripts/docker/mirror/menu.sh"
      "scripts/docker/compose.sh"
      "scripts/docker/status.sh"
      "scripts/sillytavern/config.sh"
      "scripts/sillytavern/compose.sh"
      "scripts/sillytavern/access.sh"
      "scripts/sillytavern/lifecycle.sh"
      "scripts/sillytavern/status.sh"
    )

    local file parent_dir
    for file in "${files[@]}"; do
      parent_dir="$(dirname "${file}")"
      [[ "${parent_dir}" == "." ]] || mkdir -p "${temp_dir}/${parent_dir}"
      msg_info "下载: ${file}"
      curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 180 --retry 3 --retry-delay 1 \
        "${base_url}/${file}" -o "${temp_dir}/${file}"
    done

    if [[ -n "${CHECKSUMS_URL}" ]]; then
      manifest_file="${temp_dir}/.checksums.sha256"
      curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 1 \
        "${CHECKSUMS_URL}" -o "${manifest_file}"
      verify_checksums_manifest "${temp_dir}" "${manifest_file}" "${files[@]}"
    fi

    atomic_replace_dir "${temp_dir}" "${TOOLKIT_DIR}"
    temp_dir=""
  )
}

install_from_git() {
  (
    install_dependency "git"

    local temp_dir repo_git_url prepared_dir
    temp_dir="$(mktemp -d)"
    repo_git_url="https://github.com/${REPO_USER}/${REPO_NAME}.git"
    prepared_dir=""

    cleanup_git_tmp() {
      [[ -n "${temp_dir:-}" && -d "${temp_dir}" ]] && rm -rf "${temp_dir}"
    }
    trap cleanup_git_tmp EXIT

    msg_info "正在从 GitHub 克隆仓库..."
    if is_full_commit_ref; then
      git init "${temp_dir}"
      git -C "${temp_dir}" remote add origin "${repo_git_url}"
      git -C "${temp_dir}" fetch --depth 1 origin "${TOOLKIT_REF}"
      git -C "${temp_dir}" checkout --detach FETCH_HEAD
    else
      git clone --depth 1 --branch "${TOOLKIT_REF}" "${repo_git_url}" "${temp_dir}"
    fi

    [[ -d "${temp_dir}/${REPO_PATH}" ]] || fatal "仓库中未找到 ${REPO_PATH}。"
    prepared_dir="${temp_dir}/${REPO_PATH}"
    atomic_replace_dir "${prepared_dir}" "${TOOLKIT_DIR}"
    prepared_dir=""
  )
}
