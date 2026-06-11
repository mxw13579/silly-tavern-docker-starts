#!/usr/bin/env bats
# shellcheck disable=SC2016

load "../helpers/stubs.bash"

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export USER="doctorOsUserOne"
  export DOCTOR_DOCKER_CALLS="${BATS_TEST_TMPDIR}/docker_calls"
  export DOCTOR_NETWORK_CALLS="${BATS_TEST_TMPDIR}/network_calls"
  export DOCTOR_SUDO_CALLS="${BATS_TEST_TMPDIR}/sudo_calls"
  export DOCTOR_STUB_DIR="${BATS_TEST_TMPDIR}/stubs"

  mkdir -p "${APP_DIR}/config" "${HOME}" "${DOCTOR_STUB_DIR}"
  printf 'services:\n  sillytavern:\n    image: ghcr.io/sillytavern/sillytavern:latest\n  watchtower:\n    image: containrrr/watchtower:latest\n' >"${APP_DIR}/docker-compose.yaml"
  printf 'listen: true\nport: 8000\nbasicAuthMode: true\nbasicAuthUser:\n  username: "doctorBasicUserOne"\n  password: "doctorBasicPassOne"\n' >"${APP_DIR}/config/config.yaml"
  : >"${DOCTOR_DOCKER_CALLS}"
  : >"${DOCTOR_NETWORK_CALLS}"
  : >"${DOCTOR_SUDO_CALLS}"

  write_exe "${DOCTOR_STUB_DIR}/docker" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${DOCTOR_DOCKER_CALLS}"' \
    'case "$*" in' \
    '  "--version") printf "Docker version 27.0.0\n"; exit 0 ;;' \
    '  "info") exit 0 ;;' \
    '  "compose version") printf "Docker Compose version v2.29.0\n"; exit 0 ;;' \
    '  "compose config -q") exit 0 ;;' \
    '  "compose config") printf "LEAK_FULL_COMPOSE_CONFIG doctorFullConfigSecret\n"; exit 0 ;;' \
    '  "compose ps"*) printf "NAME STATUS\nsillytavern running\nwatchtower running\n"; exit 0 ;;' \
    '  "compose logs"*) printf "stub log Authorization: Bearer doctorLogBearerOne token=doctorLogTokenOne\n"; exit 0 ;;' \
    '  inspect*) printf "container image doctorImageTokenOne\n"; exit 0 ;;' \
    'esac' \
    'exit 0'
  write_exe "${DOCTOR_STUB_DIR}/curl" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${DOCTOR_NETWORK_CALLS}"' \
    'exit 97'
  write_exe "${DOCTOR_STUB_DIR}/wget" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${DOCTOR_NETWORK_CALLS}"' \
    'exit 98'
  write_exe "${DOCTOR_STUB_DIR}/sudo" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${DOCTOR_SUDO_CALLS}"' \
    'exit 99'
  prepend_path "${DOCTOR_STUB_DIR}"
}

run_doctor() {
  run env \
    APP_DIR="${APP_DIR}" \
    HOME="${HOME}" \
    USER="${USER}" \
    ST_AUTH_USER="doctorEnvUserOne" \
    ST_AUTH_PASS="doctorEnvPassOne" \
    DOCTOR_DOCKER_CALLS="${DOCTOR_DOCKER_CALLS}" \
    DOCTOR_NETWORK_CALLS="${DOCTOR_NETWORK_CALLS}" \
    DOCTOR_SUDO_CALLS="${DOCTOR_SUDO_CALLS}" \
    bash "${REPO_ROOT}/sillytavern-toolkit/scripts/sillytavern.sh" "$@"
}

assert_no_default_report_file() {
  ! compgen -G "${HOME}/sillytavern_doctor_report_*.md" >/dev/null
}

assert_no_probe_calls() {
  [[ ! -s "${DOCTOR_SUDO_CALLS}" ]]
  [[ ! -s "${DOCTOR_NETWORK_CALLS}" ]]
  ! grep -E '^compose|^info$|^inspect' "${DOCTOR_DOCKER_CALLS}" >/dev/null
}

assert_section_order() {
  local report="$1"
  printf '%s\n' "${report}" >"${BATS_TEST_TMPDIR}/report.md"
  awk '
    /^## Summary$/ {seen=1}
    /^## Environment$/ {if (seen != 1) exit 10; seen=2}
    /^## Toolkit Self-check$/ {if (seen != 2) exit 11; seen=3}
    /^## Docker Compose$/ {if (seen != 3) exit 12; seen=4}
    /^## SillyTavern Status$/ {if (seen != 4) exit 13; seen=5}
    /^## Access Config$/ {if (seen != 5) exit 14; seen=6}
    /^## Mirror Config$/ {if (seen != 6) exit 15; seen=7}
    /^## Compose Validation$/ {if (seen != 7) exit 16; seen=8}
    /^## Command Evidence$/ {if (seen != 8) exit 17; seen=9}
    /^## Recent Logs$/ {if (seen != 9) exit 18; seen=10}
    /^## Recommendations$/ {if (seen != 10) exit 19; seen=11}
    END {exit seen == 11 ? 0 : 20}
  ' "${BATS_TEST_TMPDIR}/report.md"
}

# doctor-report and doctor help return before Docker sudo country and APP_DIR checks
function doctor_report_and_doctor_help_return_before_checks { #@test
  rm -rf "${APP_DIR}"

  run_doctor doctor-report --help
  assert_status_eq 0
  assert_output_contains "doctor-report"
  assert_output_contains "--stdout"
  assert_output_contains "--output"
  assert_no_probe_calls

  : >"${DOCTOR_DOCKER_CALLS}"
  : >"${DOCTOR_NETWORK_CALLS}"
  : >"${DOCTOR_SUDO_CALLS}"

  run_doctor doctor --help
  assert_status_eq 0
  assert_output_contains "doctor-report"
  assert_no_probe_calls
}

# doctor-report rejects option errors before writing or probing
function doctor_report_rejects_option_errors_before_writing_or_probing { #@test
  for args in \
    "doctor-report --unknown" \
    "doctor-report --output" \
    "doctor-report --since" \
    "doctor-report --service" \
    "doctor-report --lines" \
    "doctor-report --lines 0" \
    "doctor-report --lines abc" \
    "doctor-report --lines 5001" \
    "doctor-report --stdout --output ${BATS_TEST_TMPDIR}/report.md" \
    "doctor-report --service sillytavern --all-services"
  do
    : >"${DOCTOR_DOCKER_CALLS}"
    run_doctor ${args}
    [[ "${status}" -ne 0 ]]
    assert_no_default_report_file
    [[ ! -e "${BATS_TEST_TMPDIR}/report.md" ]]
    [[ ! -s "${DOCTOR_DOCKER_CALLS}" ]]
  done
}

# doctor-report stdout prints ordered markdown and does not write a file
function doctor_report_stdout_prints_ordered_markdown_and_does_not_write_file { #@test
  run_doctor doctor-report --stdout --lines 2

  assert_status_eq 0
  assert_section_order "${output}"
  assert_output_contains "sensitive values were redacted"
  assert_output_contains "Command Evidence"
  assert_output_contains "config -q"
  [[ "${output}" != *"doctorBasicPassOne"* ]]
  [[ "${output}" != *"doctorEnvPassOne"* ]]
  [[ "${output}" != *"doctorLogBearerOne"* ]]
  [[ "${output}" != *"LEAK_FULL_COMPOSE_CONFIG"* ]]
  assert_no_default_report_file
}

# doctor-report default output writes private HOME timestamped markdown report
function doctor_report_default_output_writes_private_home_report { #@test
  run_doctor doctor-report --no-logs

  assert_status_eq 0
  assert_output_contains "${HOME}/sillytavern_doctor_report_"

  local report_file
  report_file="$(find "${HOME}" -maxdepth 1 -type f -name 'sillytavern_doctor_report_*.md' | head -n1)"
  [[ -n "${report_file}" ]]
  [[ -f "${report_file}" ]]
  assert_section_order "$(cat "${report_file}")"
  [[ "$(cat "${report_file}")" != *"stub log Authorization"* ]]

  local mode
  mode="$(stat -c '%a' "${report_file}" 2>/dev/null || stat -f '%Lp' "${report_file}")"
  [[ "${mode}" == "600" || "${mode}" == "400" ]]
}

# doctor-report output path writes chosen file while stdout writes no file
function doctor_report_output_path_writes_chosen_file_without_stdout_file { #@test
  local report_file="${BATS_TEST_TMPDIR}/chosen-doctor.md"

  run_doctor doctor-report --output "${report_file}" --no-logs

  assert_status_eq 0
  assert_output_contains "${report_file}"
  [[ -f "${report_file}" ]]
  assert_section_order "$(cat "${report_file}")"
  assert_no_default_report_file

  rm -f "${report_file}"
  run_doctor doctor-report --stdout --no-logs

  assert_status_eq 0
  [[ ! -e "${report_file}" ]]
  assert_no_default_report_file
}

# doctor-report composes logs and service options without hard-coded update or info behavior
function doctor_report_composes_logs_and_service_options_only { #@test
  run_doctor doctor-report --stdout --service watchtower --lines 3 --since 30m

  assert_status_eq 0
  grep -F -- "compose logs" "${DOCTOR_DOCKER_CALLS}" | grep -F -- "watchtower"
  grep -F -- "compose logs" "${DOCTOR_DOCKER_CALLS}" | grep -F -- "--tail 3"
  grep -F -- "compose logs" "${DOCTOR_DOCKER_CALLS}" | grep -F -- "--since 30m"
  grep -Fx -- "compose config -q" "${DOCTOR_DOCKER_CALLS}"
  ! grep -Fx -- "compose config" "${DOCTOR_DOCKER_CALLS}"
  ! grep -F -- "update" "${DOCTOR_DOCKER_CALLS}"
  [[ "${output}" != *"ipinfo.io"* ]]
  [[ "${output}" != *"print_final_info"* ]]
}

# doctor-report no-logs prevents log collection and full compose config leakage
function doctor_report_no_logs_prevents_log_collection_and_config_leakage { #@test
  run_doctor doctor-report --stdout --no-logs --all-services

  assert_status_eq 0
  ! grep -E '^compose logs' "${DOCTOR_DOCKER_CALLS}" >/dev/null
  grep -Fx -- "compose config -q" "${DOCTOR_DOCKER_CALLS}"
  ! grep -Fx -- "compose config" "${DOCTOR_DOCKER_CALLS}"
  [[ "${output}" != *"doctorFullConfigSecret"* ]]
  [[ "${output}" != *"doctorLogBearerOne"* ]]
}
