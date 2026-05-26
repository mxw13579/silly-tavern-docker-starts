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

@test "toolkit menu caches status and pauses after successful actions" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -F "STATUS_CACHE_TTL" "${f}" >/dev/null
    grep -F "render_status_header()" "${f}" >/dev/null
    grep -F "invalidate_status_cache()" "${f}" >/dev/null
    grep -F "read_menu_choice()" "${f}" >/dev/null
    grep -F "handle_empty_choice()" "${f}" >/dev/null
    grep -A20 "run_action()" "${f}" | grep -F "pause_to_continue" >/dev/null
  '

  assert_status_eq 0
}

@test "toolkit menu uses shared brand and separator helpers" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -Eq "^(function[[:space:]]+)?(print|render|show)_(home_)?(brand|toolkit)_(header|banner)[[:space:]]*(\\(\\))?[[:space:]]*\\{" "${f}" >/dev/null
    grep -Eq "^(function[[:space:]]+)?print_sep[[:space:]]*(\\(\\))?[[:space:]]*\\{" "${f}" >/dev/null
    grep -F "SillyTavern Docker 工具箱" "${f}" >/dev/null
    grep -F "FuFu API | 群 1019836466" "${f}" >/dev/null
    grep -F "==========================================================" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "toolkit submenus keep compact brand header" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -F "SillyTavern Docker 工具箱 | FuFu API | 群 1019836466" "${f}" >/dev/null
    grep -A8 "print_menu_header()" "${f}" | grep -F "print_sep" >/dev/null
    grep -A8 "print_menu_header()" "${f}" | grep -F "print_compact_brand_header" >/dev/null
  '

  assert_status_eq 0
}

@test "docker mirror submenu keeps compact brand header" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/scripts/docker/mirror.sh"
    grep -F "print_docker_mirror_menu_header()" "${f}" >/dev/null
    grep -F "SillyTavern Docker 工具箱 | FuFu API | 群 1019836466" "${f}" >/dev/null
    grep -F "DOCKER_MIRROR_MENU_SEP" "${f}" >/dev/null
    grep -F "print_docker_mirror_menu_header \"选择 Docker Hub 镜像加速器\"" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "source mirror changes pause so users can read the result" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -F "run_action --pause-on-success \"\${SCRIPT_DIR}/scripts/sources.sh\" set aliyun" "${f}" >/dev/null
    grep -F "run_action --pause-on-success \"\${SCRIPT_DIR}/scripts/sources.sh\" set tencent" "${f}" >/dev/null
    grep -F "run_action --pause-on-success \"\${SCRIPT_DIR}/scripts/sources.sh\" set huawei" "${f}" >/dev/null
    grep -F "run_action --pause-on-success \"\${SCRIPT_DIR}/scripts/sources.sh\" restore" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "toolkit home status uses stable field labels" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -F "系统环境 :" "${f}" >/dev/null
    grep -F "服务管理 :" "${f}" >/dev/null
    grep -F "包管理器 :" "${f}" >/dev/null
    grep -F "国内镜像 :" "${f}" >/dev/null
    grep -F "软件源   :" "${f}" >/dev/null
    grep -F "Docker   :" "${f}" >/dev/null
    grep -F "应用     :" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "toolkit home menu keeps workflow descriptions" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/st-toolkit.sh"
    grep -F "切换/恢复系统软件源" "${f}" >/dev/null
    grep -F "安装 Docker、Compose、镜像加速" "${f}" >/dev/null
    grep -F "安装、启动、备份、访问配置" "${f}" >/dev/null
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
