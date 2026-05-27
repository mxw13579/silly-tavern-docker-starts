#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  ST_TOOLKIT_REQUIRE_SUDO=0
  ST_TOOLKIT_SKIP_COUNTRY=1
fi

__st_sources_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || {
  printf '[ERROR] 无法定位软件源脚本目录。\n' >&2
  exit 1
}
ST_SOURCES_ENTRYPOINT="${BASH_SOURCE[0]}"

# shellcheck source=sillytavern-toolkit/scripts/common.sh
. "${__st_sources_dir}/common.sh"

APT_SWITCH_BACKUP_DIR=""

require_sources_module() {
  local module="$1"
  local path="${__st_sources_dir}/sources/${module}"

  [[ -f "${path}" ]] || fatal "缺少软件源模块: ${path}"
  # shellcheck source=/dev/null
  . "${path}"
}

# shellcheck source=sillytavern-toolkit/scripts/sources/precheck.sh
require_sources_module "precheck.sh"
# shellcheck source=sillytavern-toolkit/scripts/sources/backup.sh
require_sources_module "backup.sh"
# shellcheck source=sillytavern-toolkit/scripts/sources/providers.sh
require_sources_module "providers.sh"
# shellcheck source=sillytavern-toolkit/scripts/sources/status.sh
require_sources_module "status.sh"

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
