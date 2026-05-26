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

@test "toolkit menu uses shared brand and separator helpers" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -Eq "^(function[[:space:]]+)?(print|render|show)_(brand|toolkit)_(header|banner)[[:space:]]*(\\(\\))?[[:space:]]*\\{" "${f}" >/dev/null
    grep -Eq "^(function[[:space:]]+)?print_sep[[:space:]]*(\\(\\))?[[:space:]]*\\{" "${f}" >/dev/null
    grep -F "SillyTavern Docker 工具箱 | FuFu API | 群 1019836466" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "toolkit home menu groups system component and suggested workflow copy" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -F "[系统]" "${f}" >/dev/null
    grep -F "[组件]" "${f}" >/dev/null
    grep -Eq "建议流程|推荐流程|下一步建议|建议操作" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "toolkit submenus use shared title and description rendering" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    if ! grep -Eq "^(function[[:space:]]+)?(print|render|show)_((sub)?menu_)?(header|title|intro|description|desc)[[:space:]]*(\\(\\))?[[:space:]]*\\{" "${f}" &&
       ! grep -Eq "(print|render|show)_((sub)?menu_)?(header|title|intro|description|desc)[[:space:]]+\"[^\"]+\"([[:space:]]+\"[^\"]+\")?" "${f}"; then
      exit 1
    fi
  '

  assert_status_eq 0
}

@test "toolkit read_menu_choice writes selected value to caller variable" {
  run bash -c '
    set -euo pipefail
    fn="$(sed -n "/^handle_empty_choice()/,/^sources_menu()/p" "sillytavern-toolkit/st-toolkit.sh" | sed '$d')"
    eval "${fn}"
    msg_warn() { printf "%s\n" "$*"; }
    selected=""
    read_menu_choice selected "prompt: " <<< $'"'"'1\r\n'"'"'
    [[ "${selected}" == "1" ]]
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
