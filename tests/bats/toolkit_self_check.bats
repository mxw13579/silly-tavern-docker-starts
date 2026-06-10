#!/usr/bin/env bats

load "../helpers/stubs.bash"

setup_self_check_fixture() {
  export ST_TOOLKIT_SELF_CHECK_ROOT="${BATS_TEST_TMPDIR}/toolkit"
  export APP_DIR="${BATS_TEST_TMPDIR}/app"
  export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
  export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
  mkdir -p \
    "${ST_TOOLKIT_SELF_CHECK_ROOT}/scripts/lib" \
    "${ST_TOOLKIT_SELF_CHECK_ROOT}/scripts/sillytavern" \
    "${ST_TOOLKIT_SELF_CHECK_ROOT}/scripts/docker" \
    "${ST_TOOLKIT_SELF_CHECK_ROOT}/scripts/sources" \
    "${ST_TOOLKIT_SELF_CHECK_ROOT}/scripts/toolkit" \
    "${APP_DIR}/config"

  for file in \
    st-toolkit.sh install.sh scripts/common.sh scripts/health.sh \
    scripts/sillytavern.sh scripts/docker.sh scripts/sources.sh \
    scripts/toolkit/self_check.sh \
    scripts/lib/compose.sh scripts/lib/logging.sh scripts/lib/input.sh \
    scripts/lib/network.sh scripts/lib/os.sh scripts/lib/apt.sh \
    scripts/lib/packages.sh scripts/sillytavern/compose.sh \
    scripts/sillytavern/validation.sh scripts/sillytavern/config.sh \
    scripts/sillytavern/access.sh scripts/sillytavern/lifecycle.sh \
    scripts/sillytavern/logs.sh scripts/sillytavern/status.sh scripts/docker/install.sh \
    scripts/docker/mirror.sh scripts/docker/compose.sh scripts/docker/status.sh \
    scripts/sources/precheck.sh scripts/sources/backup.sh \
    scripts/sources/providers.sh scripts/sources/status.sh
  do
    mkdir -p "$(dirname "${ST_TOOLKIT_SELF_CHECK_ROOT}/${file}")"
    printf '#!/usr/bin/env bash\n:\n' >"${ST_TOOLKIT_SELF_CHECK_ROOT}/${file}"
  done
}

run_self_check() {
  run env \
    ST_TOOLKIT_TEST_MODE=1 \
    ST_TOOLKIT_REQUIRE_SUDO=0 \
    ST_TOOLKIT_SKIP_COUNTRY=1 \
    ST_TOOLKIT_SELF_CHECK_ROOT="${ST_TOOLKIT_SELF_CHECK_ROOT}" \
    APP_DIR="${APP_DIR}" \
    ST_COMPOSE_FILE="${ST_COMPOSE_FILE}" \
    ST_CONFIG_FILE="${ST_CONFIG_FILE}" \
    bash sillytavern-toolkit/scripts/toolkit/self_check.sh "$@"
}

function test_healthy_fixture_contains_logs_module { #@test
  setup_self_check_fixture

  [[ -f "${ST_TOOLKIT_SELF_CHECK_ROOT}/scripts/sillytavern/logs.sh" ]]
}

function test_healthy_fixture_exits_0_and_prints_final_summary { #@test
  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'case "$*" in "compose version"|"info"|"--version") exit 0 ;; esac' \
    'exit 0'
  prepend_path "${stub_dir}"
  setup_self_check_fixture
  printf 'services: {}\n' >"${ST_COMPOSE_FILE}"
  printf 'listen: true\n' >"${ST_CONFIG_FILE}"

  run_self_check

  assert_status_eq 0
  assert_output_contains "summary:"
  assert_output_contains "PASS"
}

function test_missing_required_toolkit_file_exits_nonzero_with_problem_impact_and_fix { #@test
  setup_self_check_fixture
  rm -f "${ST_TOOLKIT_SELF_CHECK_ROOT}/scripts/common.sh"

  run_self_check

  [[ "${status}" -ne 0 ]]
  assert_output_contains "FAIL"
  assert_output_contains "problem:"
  assert_output_contains "impact:"
  assert_output_contains "fix:"
  assert_output_contains "scripts/common.sh"
}

function test_missing_optional_dependency_warns_and_exits_0_by_default { #@test
  setup_self_check_fixture
  mkdir -p "${BATS_TEST_TMPDIR}/minimal-bin"
  for cmd in bash find sed grep awk chmod mkdir cp rm; do
    ln -s "$(command -v "${cmd}")" "${BATS_TEST_TMPDIR}/minimal-bin/${cmd}"
  done
  export PATH="${BATS_TEST_TMPDIR}/minimal-bin"

  run_self_check

  assert_status_eq 0
  assert_output_contains "WARN"
  assert_output_contains "curl"
}

function test_strict_exits_nonzero_on_warnings { #@test
  setup_self_check_fixture
  mkdir -p "${BATS_TEST_TMPDIR}/minimal-bin"
  for cmd in bash find sed grep awk chmod mkdir cp rm; do
    ln -s "$(command -v "${cmd}")" "${BATS_TEST_TMPDIR}/minimal-bin/${cmd}"
  done
  export PATH="${BATS_TEST_TMPDIR}/minimal-bin"

  run_self_check --strict

  [[ "${status}" -ne 0 ]]
  assert_output_contains "summary:"
}

function test_quiet_mode_suppresses_passing_detail_but_keeps_summary_and_warnings { #@test
  setup_self_check_fixture
  mkdir -p "${BATS_TEST_TMPDIR}/minimal-bin"
  for cmd in bash find sed grep awk chmod mkdir cp rm; do
    ln -s "$(command -v "${cmd}")" "${BATS_TEST_TMPDIR}/minimal-bin/${cmd}"
  done
  export PATH="${BATS_TEST_TMPDIR}/minimal-bin"

  run_self_check --quiet

  assert_status_eq 0
  assert_output_contains "WARN"
  assert_output_contains "summary:"
  [[ "${output}" != *"PASS required command available: bash"* ]]
}

function test_docker_absent_is_warn_not_fail { #@test
  setup_self_check_fixture
  mkdir -p "${BATS_TEST_TMPDIR}/minimal-bin"
  for cmd in bash find sed grep awk chmod mkdir cp rm; do
    ln -s "$(command -v "${cmd}")" "${BATS_TEST_TMPDIR}/minimal-bin/${cmd}"
  done
  export PATH="${BATS_TEST_TMPDIR}/minimal-bin"

  run_self_check

  assert_status_eq 0
  assert_output_contains "WARN Docker CLI"
}

function test_compose_discovery_supports_docker_compose_stub { #@test
  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'case "$*" in "compose version"|"info"|"--version") exit 0 ;; esac' \
    'exit 7'
  prepend_path "${stub_dir}"
  setup_self_check_fixture

  run_self_check

  assert_status_eq 0
  assert_output_contains "docker compose"
}

function test_compose_discovery_supports_docker_compose_binary_stub { #@test
  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'case "$*" in "info"|"--version") exit 0 ;; esac' \
    'exit 7'
  write_exe "${stub_dir}/docker-compose" \
    '#!/usr/bin/env bash' \
    'exit 0'
  prepend_path "${stub_dir}"
  setup_self_check_fixture

  run_self_check

  assert_status_eq 0
  assert_output_contains "docker-compose"
}

function test_version_hint_uses_local_git_and_does_not_invoke_network_tools { #@test
  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_exe "${stub_dir}/git" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${GIT_CALLS}"' \
    'case "$*" in' \
    '  *"rev-parse --is-inside-work-tree"*) exit 0 ;;' \
    '  *"rev-parse --short HEAD"*) printf "abc1234\n"; exit 0 ;;' \
    '  *"branch --show-current"*) printf "main\n"; exit 0 ;;' \
    'esac' \
    'exit 9'
  write_exe "${stub_dir}/curl" '#!/usr/bin/env bash' 'exit 99'
  write_exe "${stub_dir}/wget" '#!/usr/bin/env bash' 'exit 99'
  prepend_path "${stub_dir}"
  export GIT_CALLS="${BATS_TEST_TMPDIR}/git_calls"
  setup_self_check_fixture

  run_self_check

  assert_status_eq 0
  assert_output_contains "abc1234"
  assert_output_contains "main"
  ! grep -E -- "pull|fetch|ls-remote|remote" "${GIT_CALLS}"
}
