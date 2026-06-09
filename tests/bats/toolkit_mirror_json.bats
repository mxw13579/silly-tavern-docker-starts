#!/usr/bin/env bats

load "../helpers/stubs.bash"

run_mirror_json_case() {
  local daemon_json="$1"
  local expect_status="$2"
  local expect_output="${3:-}"
  local daemon_path="${BATS_TEST_TMPDIR}/daemon.json"

  printf '%s\n' "${daemon_json}" >"${daemon_path}"

  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export DOCKER_DAEMON_JSON_PATH='${daemon_path}'
    set --
    source 'sillytavern-toolkit/scripts/common.sh'
    source 'sillytavern-toolkit/scripts/docker/mirror.sh'
    get_current_docker_mirrors
  "

  assert_status_eq "${expect_status}"
  [[ "${output}" == "${expect_output}" ]]
}

@test "registry-mirrors empty array is not configured" {
  run_mirror_json_case '{"registry-mirrors":[]}' 1 ''
}

@test "registry-mirrors string value is not configured" {
  run_mirror_json_case '{"registry-mirrors":"https://mirror.example.com"}' 1 ''
}

@test "invalid daemon.json is not configured" {
  run_mirror_json_case '{"registry-mirrors":["https://mirror.example.com"]' 1 ''
}

@test "registry-mirrors valid non-empty URL array is configured" {
  run_mirror_json_case '{"registry-mirrors":["https://mirror.example.com"]}' 0 'https://mirror.example.com'
}

@test "registry-mirrors array with invalid URL is not configured" {
  run_mirror_json_case '{"registry-mirrors":["https://mirror.example.com","not a url"]}' 1 ''
}

@test "registry-mirrors is not configured when no Python 3 JSON parser is available" {
  local daemon_path="${BATS_TEST_TMPDIR}/daemon.json"
  printf '%s\n' '{"registry-mirrors":["https://mirror.example.com"]}' >"${daemon_path}"

  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export DOCKER_DAEMON_JSON_PATH='${daemon_path}'
    set --
    source 'sillytavern-toolkit/scripts/common.sh'
    source 'sillytavern-toolkit/scripts/docker/mirror.sh'
    docker_json_python_cmd() { return 1; }
    docker_registry_mirrors_configured
  "

  [[ "${status}" -ne 0 ]]
  [[ "${output}" == "" ]]
}

@test "docker status falls back to not configured when mirror helper is not loaded" {
  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'case "$*" in' \
    '  "-v") echo "Docker version 27.0.0, build test"; exit 0 ;;' \
    '  "info") exit 0 ;;' \
    '  "compose version") echo "Docker Compose version v2.29.0"; exit 0 ;;' \
    'esac' \
    'exit 1'
  prepend_path "${stub_dir}"

  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source 'sillytavern-toolkit/scripts/common.sh'
    source 'sillytavern-toolkit/scripts/docker/status.sh'
    status_docker
  "

  assert_status_eq 0
  assert_output_contains "Docker"
  assert_output_contains "Compose"
}

@test "write_docker_mirrors rejects invalid custom mirror URL" {
  local daemon_path="${BATS_TEST_TMPDIR}/write-invalid/daemon.json"

  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export DOCKER_DAEMON_JSON_PATH='${daemon_path}'
    set --
    source 'sillytavern-toolkit/scripts/common.sh'
    source 'sillytavern-toolkit/scripts/docker/mirror.sh'
    write_docker_mirrors 'not a url'
  "

  assert_status_eq 1
  [[ ! -e "${daemon_path}" ]]
  assert_output_contains "Invalid Docker registry mirror URL"
}

@test "write_docker_mirrors accepts valid custom mirror URL" {
  local daemon_path="${BATS_TEST_TMPDIR}/write-valid/daemon.json"

  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export DOCKER_DAEMON_JSON_PATH='${daemon_path}'
    set --
    source 'sillytavern-toolkit/scripts/common.sh'
    source 'sillytavern-toolkit/scripts/docker/mirror.sh'
    write_docker_mirrors 'https://mirror.example.com'
    get_current_docker_mirrors
  "

  assert_status_eq 0
  [[ "${output}" == *"https://mirror.example.com"* ]]
}

@test "configure_docker_mirror_safe rejects invalid default mirror URL" {
  local daemon_path="${BATS_TEST_TMPDIR}/default-invalid/daemon.json"

  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export DOCKER_DAEMON_JSON_PATH='${daemon_path}'
    set --
    source 'sillytavern-toolkit/scripts/common.sh'
    source 'sillytavern-toolkit/scripts/docker/mirror.sh'
    DOCKER_DEFAULT_MIRROR='ftp://mirror.example.com'
    USE_CHINA_MIRROR=true
    restart_docker_service() { echo 'unexpected restart'; return 99; }
    configure_docker_mirror_safe
  "

  assert_status_eq 1
  [[ "${output}" != *"unexpected restart"* ]]
  assert_output_contains "Invalid Docker registry mirror URL"
}

@test "configure_docker_mirror_safe filters invalid existing mirror entries" {
  local daemon_path="${BATS_TEST_TMPDIR}/default-filter/daemon.json"
  mkdir -p "$(dirname "${daemon_path}")"
  printf '%s\n' '{"registry-mirrors":["not a url","https://old.example.com"]}' >"${daemon_path}"

  run bash -c "
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export DOCKER_DAEMON_JSON_PATH='${daemon_path}'
    set --
    source 'sillytavern-toolkit/scripts/common.sh'
    source 'sillytavern-toolkit/scripts/docker/mirror.sh'
    DOCKER_DEFAULT_MIRROR='https://mirror.example.com'
    USE_CHINA_MIRROR=true
    restart_docker_service() { return 0; }
    configure_docker_mirror_safe
    get_current_docker_mirrors
  "

  assert_status_eq 0
  [[ "${output}" == *"https://mirror.example.com"* ]]
  [[ "${output}" == *"https://old.example.com"* ]]
  [[ "${output}" != *"not a url"* ]]
}
