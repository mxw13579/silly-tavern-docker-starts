#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

load "../helpers/stubs.bash"

setup() {
  export ST_TOOLKIT_TEST_MODE=1
  export ST_TOOLKIT_REQUIRE_SUDO=0
  export ST_TOOLKIT_SKIP_COUNTRY=1
  export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
  export DOCKER_CALLS="${BATS_TEST_TMPDIR}/docker_calls"
  export REPO_ROOT
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  mkdir -p "${APP_DIR}/config"
  printf 'services: {}\n' >"${APP_DIR}/docker-compose.yaml"
  printf 'listen: true\n' >"${APP_DIR}/config/config.yaml"
  : >"${DOCKER_CALLS}"

  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${DOCKER_CALLS}"' \
    'case "$*" in' \
    '  "info") exit 0 ;;' \
    '  "compose version") exit 0 ;;' \
    '  compose\ logs*) printf "stub log line\n"; exit 0 ;;' \
    'esac' \
    'exit 42'
  prepend_path "${stub_dir}"
}

run_logs() {
  env \
    ST_TOOLKIT_TEST_MODE="${ST_TOOLKIT_TEST_MODE}" \
    ST_TOOLKIT_REQUIRE_SUDO="${ST_TOOLKIT_REQUIRE_SUDO}" \
    ST_TOOLKIT_SKIP_COUNTRY="${ST_TOOLKIT_SKIP_COUNTRY}" \
    APP_DIR="${APP_DIR}" \
    DOCKER_CALLS="${DOCKER_CALLS}" \
    REPO_ROOT="${REPO_ROOT}" \
    bash -c '. "${REPO_ROOT}/sillytavern-toolkit/scripts/common.sh"; . "${REPO_ROOT}/sillytavern-toolkit/scripts/sillytavern/compose.sh"; . "${REPO_ROOT}/sillytavern-toolkit/scripts/sillytavern/logs.sh"; logs_st "$@"' _ "$@"
}

assert_compose_call() {
  local expected="$1"
  grep -Fx -- "${expected}" "${DOCKER_CALLS}"
}

assert_no_compose_logs_call() {
  ! grep -E '^compose logs' "${DOCKER_CALLS}" >/dev/null
}

function logs_default_prints_bounded_tail_of_200_lines { #@test
  run run_logs

  assert_status_eq 0
  assert_compose_call "compose logs --tail 200 sillytavern"
}

function logs_tail_accepts_lines_alias_and_service_default { #@test
  run run_logs tail --lines 50

  assert_status_eq 0
  assert_compose_call "compose logs --tail 50 sillytavern"
}

function logs_follow_is_explicit_bounded_and_prints_exit_guidance { #@test
  run run_logs follow

  assert_status_eq 0
  assert_output_contains "Ctrl+C"
  assert_output_contains "logs save --output"
  assert_compose_call "compose logs --follow --tail 100 sillytavern"
}

function logs_since_defaults_to_bounded_output { #@test
  run run_logs since 30m

  assert_status_eq 0
  assert_compose_call "compose logs --since 30m --tail 1000 sillytavern"
}

function logs_since_all_omits_tail_cap { #@test
  run run_logs since 30m --all

  assert_status_eq 0
  assert_output_contains "may be large"
  assert_compose_call "compose logs --since 30m sillytavern"
}

function logs_save_writes_through_temp_file_then_creates_output { #@test
  local output_file="${BATS_TEST_TMPDIR}/saved.log"

  run run_logs save --output "${output_file}" --lines 20

  assert_status_eq 0
  assert_output_contains "${output_file}"
  assert_compose_call "compose logs --tail 20 sillytavern"
  [[ "$(cat "${output_file}")" == "stub log line" ]]
}

function logs_save_rejects_existing_output_directory_before_compose_logs { #@test
  local output_dir="${BATS_TEST_TMPDIR}/saved-dir"
  mkdir -p "${output_dir}"

  run run_logs save --output "${output_dir}" --lines 20

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ERROR: problem:"
  assert_output_contains "output path is a directory"
  assert_no_compose_logs_call
}

function logs_save_reports_final_move_failure_and_removes_temp_file { #@test
  local stub_dir output_file
  stub_dir="$(make_stub_dir)"
  output_file="${BATS_TEST_TMPDIR}/move-fails.log"
  write_exe "${stub_dir}/mv" \
    '#!/usr/bin/env bash' \
    'exit 77'

  run run_logs save --output "${output_file}" --lines 20

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ERROR: problem:"
  assert_output_contains "failed to finalize log file"
  [[ "${output}" != *"Logs saved"* ]]
  [[ ! -e "${output_file}" ]]
  ! compgen -G "${BATS_TEST_TMPDIR}/.sillytavern_logs.*" >/dev/null
}

function logs_rejects_invalid_line_counts_before_compose_logs { #@test
  run run_logs tail --lines 0

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ERROR: problem:"
  assert_no_compose_logs_call
}

function logs_rejects_unknown_options_before_compose_logs { #@test
  run run_logs tail --unknown

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ERROR: problem:"
  assert_no_compose_logs_call
}

function logs_since_requires_a_value_before_compose_logs { #@test
  run run_logs since

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ERROR: problem:"
  assert_no_compose_logs_call
}

function logs_rejects_missing_save_output_value_before_compose_logs { #@test
  run run_logs save --output

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ERROR: problem:"
  assert_no_compose_logs_call
}

function logs_help_does_not_require_docker_or_install_state { #@test
  rm -f "${APP_DIR}/docker-compose.yaml"
  : >"${DOCKER_CALLS}"

  run run_logs --help

  assert_status_eq 0
  assert_output_contains "Usage: sillytavern.sh logs"
  [[ ! -s "${DOCKER_CALLS}" ]]
}

function logs_all_services_omits_service_argument { #@test
  run run_logs tail --lines 25 --all-services

  assert_status_eq 0
  assert_compose_call "compose logs --tail 25"
}

function logs_service_appends_the_selected_service { #@test
  run run_logs tail --lines 25 --service watchtower

  assert_status_eq 0
  assert_compose_call "compose logs --tail 25 watchtower"
}

function logs_rejects_option_shaped_service_before_compose_logs { #@test
  run run_logs tail --lines 25 --service --tail

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ERROR: problem:"
  assert_output_contains "invalid --service value"
  assert_no_compose_logs_call
}
