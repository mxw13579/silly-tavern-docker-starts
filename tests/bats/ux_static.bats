#!/usr/bin/env bats

load "../helpers/stubs.bash"

@test "changed shell scripts keep valid bash syntax" {
  run bash -c '
    set -euo pipefail
    bash -n sillytavern-toolkit/scripts/docker/mirror.sh
    bash -n sillytavern-toolkit/scripts/health.sh
    bash -n sillytavern-toolkit/scripts/lib/logging.sh
    bash -n sillytavern-toolkit/scripts/sources.sh
    bash -n sillytavern-toolkit/st-toolkit.sh
  '

  assert_status_eq 0
}

@test "sources.sh prechecks mirrors and shows rollback guidance on refresh failure" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/scripts/sources.sh"
    grep -F "precheck_mirror_url()" "${f}" >/dev/null
    grep -F "try_backup_source_file()" "${f}" >/dev/null
    grep -F "APT 主源" "${f}" >/dev/null
    grep -F "如需回滚，可运行:" "${f}" >/dev/null
    grep -F "fatal_restore_refresh_failed()" "${f}" >/dev/null
    grep -F "请检查网络、DNS、代理或镜像站状态" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "toolkit menu caches status and does not pause every successful action" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -F "STATUS_CACHE_TTL" "${f}" >/dev/null
    grep -F "render_status_header()" "${f}" >/dev/null
    grep -F "invalidate_status_cache()" "${f}" >/dev/null
    grep -F "read_menu_choice()" "${f}" >/dev/null
    grep -F "handle_empty_choice()" "${f}" >/dev/null
    grep -F -- "--pause-on-success" "${f}" >/dev/null
    grep -F "操作完成，返回菜单" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "logging and health output include progress context and a final summary" {
  run bash -c '
    set -euo pipefail
    logging="sillytavern-toolkit/scripts/lib/logging.sh"
    health="sillytavern-toolkit/scripts/health.sh"
    grep -F "过程日志:" "${logging}" >/dev/null
    grep -F "已运行 %ss" "${logging}" >/dev/null
    grep -F "HEALTH_OK_COUNT" "${health}" >/dev/null
    grep -F "== 检查汇总 ==" "${health}" >/dev/null
    grep -F "下一步建议" "${health}" >/dev/null
  '

  assert_status_eq 0
}
