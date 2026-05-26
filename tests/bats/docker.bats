#!/usr/bin/env bats

load "../helpers/stubs.bash"

@test "docker.sh normalize_mirror_url trims and rejects invalid urls" {
  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source \"sillytavern-toolkit/scripts/common.sh\"
    source \"sillytavern-toolkit/scripts/docker/mirror.sh\"
    out=\"\$(normalize_mirror_url \$'  https://example.com/foo/\\n')\"
    [[ \"\${out}\" == 'https://example.com/foo' ]]
    ! normalize_mirror_url 'http://example.com'
    ! normalize_mirror_url 'https://exa mple.com'
  "
  assert_status_eq 0
}

@test "docker.sh measure_mirror prints exactly one line per call and caches" {
  local stub_dir
  stub_dir="$(make_stub_dir)"

  write_exe "${stub_dir}/curl" \
    '#!/usr/bin/env bash' \
    'printf "%s" "401 0.123"'
  prepend_path "${stub_dir}"

  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source \"sillytavern-toolkit/scripts/common.sh\"
    source \"sillytavern-toolkit/scripts/docker/mirror.sh\"
    export XDG_CACHE_HOME='${BATS_TEST_TMPDIR}/xdgcache'
    mirror='https://mirror.example.com'
    a=\"\$(measure_mirror \"\${mirror}\")\"
    b=\"\$(measure_mirror \"\${mirror}\")\"
    # both should be one line; cached path must not introduce extra newlines.
    [[ \"\${a}\" == \$'0.123\\t401\\thttps://mirror.example.com' ]]
    [[ \"\${b}\" == \$'0.123\\t401\\thttps://mirror.example.com' ]]
  "
  assert_status_eq 0
}

@test "docker.sh restore_daemon CLI dispatch exists (usage + case branch)" {
  run bash -c "
    set -euo pipefail
    f='sillytavern-toolkit/scripts/docker.sh'
    grep -n 'restore_daemon' \"\${f}\" >/dev/null
    grep -nE '^[[:space:]]*restore_daemon\\)' \"\${f}\" >/dev/null
  "
  assert_status_eq 0
}

@test "docker.sh facade smoke: status in test mode does not sudo/network and finishes quickly" {
  local stub_dir
  stub_dir="$(make_stub_dir)"

  # Hard-fail if sudo/network is touched.
  write_exe "${stub_dir}/sudo" \
    '#!/usr/bin/env bash' \
    'echo "unexpected sudo" >&2' \
    'exit 99'
  write_exe "${stub_dir}/curl" \
    '#!/usr/bin/env bash' \
    'echo "unexpected curl" >&2' \
    'exit 99'
  write_exe "${stub_dir}/wget" \
    '#!/usr/bin/env bash' \
    'echo "unexpected wget" >&2' \
    'exit 99'

  # Minimal docker/compose stubs for status_docker + detect_compose_cmd.
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case "${1:-}" in' \
    '  -v|--version|version) echo "Docker version 25.0.0, build deadbeef"; exit 0 ;;' \
    '  info) exit 0 ;;' \
    '  compose)' \
    '    if [[ "${2:-}" == "version" ]]; then echo "Docker Compose version v2.24.0"; exit 0; fi' \
    '    ;;' \
    'esac' \
    'exit 0'
  write_exe "${stub_dir}/docker-compose" \
    '#!/usr/bin/env bash' \
    'exit 0'

  prepend_path "${stub_dir}"

  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    bash "sillytavern-toolkit/scripts/docker.sh" status
  '

  assert_status_eq 0
}

@test "mirror.sh does not use ls -1t for daemon.json backup selection" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/scripts/docker/mirror.sh"
    ! grep -nE "^[[:space:]]*ls[[:space:]]+-1t[[:space:]]+/etc/docker/daemon\\.json\\.bak\\.\\*" "${f}" >/dev/null
    grep -n "find_latest_daemon_json_backup" "${f}" >/dev/null
    grep -nE "find[[:space:]].*/etc/docker[[:space:]].*-name[[:space:]]+'daemon\\.json\\.bak\\.\\*'" "${f}" >/dev/null
    grep -nE "stat[[:space:]]+-c[[:space:]]+'%Y %n'|stat[[:space:]]+-f[[:space:]]+'%m %N'" "${f}" >/dev/null
  '
  assert_status_eq 0
}

@test "mirror.sh tests native Docker Hub when no registry mirror is configured" {
  local stub_dir
  stub_dir="$(make_stub_dir)"

  write_exe "${stub_dir}/curl" \
    '#!/usr/bin/env bash' \
    'printf "%s" "401 0.456"'
  prepend_path "${stub_dir}"

  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/docker/mirror.sh"
    get_current_docker_mirrors() { return 0; }
    out="$(speed_test_current_mirrors)"
    grep -F "当前未配置 Docker 镜像加速器，将测试原生 Docker Hub 访问。" <<<"${out}" >/dev/null
    grep -F "Docker Hub 原生 (https://registry-1.docker.io)" <<<"${out}" >/dev/null
    grep -F "0.456s" <<<"${out}" >/dev/null
  '

  assert_status_eq 0
}

@test "mirror.sh mirror selection separates unavailable candidates from selectable recommendations" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/scripts/docker/mirror.sh"
    grep -F "不可用候选（本次不推荐）" "${f}" >/dev/null
    grep -F "本次未发现测速成功的候选镜像，可选择自定义输入。" "${f}" >/dev/null
    ! grep -F "腾讯云（推荐）" "${f}" >/dev/null
    grep -F "腾讯云（默认）" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "mirror.sh print_mirror_http_hint outputs 401 explanation" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/docker/mirror.sh"
    print_mirror_http_hint
  '

  assert_status_eq 0
  [[ "${output}" == *"HTTP 401 表示 Docker Registry /v2/ 可达但未认证"* ]]
}

@test "mirror.sh mirror_probe_failed classifies registry probe results" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/docker/mirror.sh"
    ! mirror_probe_failed "0.123" "200"
    ! mirror_probe_failed "0.123" "401"
    mirror_probe_failed "9999.999" "000"
    mirror_probe_failed "0.123" "000"
    mirror_probe_failed "0.123" "404"
    mirror_probe_failed "0.123" "500"
    mirror_probe_failed "0.123" ""
    mirror_probe_failed "0.123"
    mirror_probe_failed "9999.999" "401"
  '

  assert_status_eq 0
}
