#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

cli_file="sillytavern-toolkit/scripts/sillytavern.sh"
menu_file="sillytavern-toolkit/st-toolkit.sh"
doctor_file="sillytavern-toolkit/scripts/doctor_report.sh"

failures=0

fail() {
  echo "$*" >&2
  failures=$((failures + 1))
}

assert_file_exists() {
  local file="$1"
  local message="$2"

  [[ -f "${file}" ]] || fail "${message}"
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  grep -F -- "${needle}" "${file}" >/dev/null || fail "${message}"
}

assert_file_not_contains_re() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -E -- "${pattern}" "${file}" >/dev/null; then
    fail "${message}"
  fi
}

extract_case_block() {
  local file="$1"
  local case_pattern="$2"

  awk -v pattern="${case_pattern}" '
    /^case "\$\{1:-\}" in/ {in_case=1; next}
    in_case && $0 ~ pattern {in_block=1}
    in_block {print}
    in_block && /^[[:space:]]*;;[[:space:]]*$/ {exit}
  ' "${file}"
}

assert_file_exists "${cli_file}" "sillytavern.sh must exist"
assert_file_exists "${menu_file}" "st-toolkit.sh must exist"
assert_file_exists "${doctor_file}" "doctor_report.sh must exist"

bash -n "${cli_file}" || fail "sillytavern.sh must pass bash -n"
bash -n "${menu_file}" || fail "st-toolkit.sh must pass bash -n"
if [[ -f "${doctor_file}" ]]; then
  bash -n "${doctor_file}" || fail "doctor_report.sh must pass bash -n"
fi

assert_file_contains "${cli_file}" "doctor-report" \
  "sillytavern.sh help/dispatch must mention doctor-report"
assert_file_contains "${cli_file}" "doctor" \
  "sillytavern.sh help/dispatch must mention doctor alias"
assert_file_contains "${cli_file}" "ST_TOOLKIT_REQUIRE_SUDO=0" \
  "doctor dispatch must disable source-time sudo before common.sh"
assert_file_contains "${cli_file}" "ST_TOOLKIT_SKIP_COUNTRY=1" \
  "doctor dispatch must disable country detection before common.sh"

common_line="$(grep -nF -- '. "${__st_scripts_dir}/common.sh"' "${cli_file}" | head -n1 | cut -d: -f1 || true)"
require_sudo_line="$(grep -nF -- 'ST_TOOLKIT_REQUIRE_SUDO=0' "${cli_file}" | head -n1 | cut -d: -f1 || true)"
skip_country_line="$(grep -nF -- 'ST_TOOLKIT_SKIP_COUNTRY=1' "${cli_file}" | head -n1 | cut -d: -f1 || true)"
if [[ -z "${common_line}" || -z "${require_sudo_line}" || -z "${skip_country_line}" ]]; then
  fail "sillytavern.sh must contain common.sh source and doctor pre-source env assignments"
elif ! ((require_sudo_line < common_line && skip_country_line < common_line)); then
  fail "doctor env assignments must appear before common.sh is sourced"
fi

pre_common="$(
  awk '
    /\. "\$\{__st_scripts_dir\}\/common\.sh"/ {exit}
    {print}
  ' "${cli_file}"
)"
if ! grep -E -- 'doctor-report|doctor' <<<"${pre_common}" >/dev/null; then
  fail "doctor-report/doctor must be handled before common.sh source-time checks"
fi
if ! grep -F -- 'doctor_report.sh' <<<"${pre_common}" >/dev/null ||
  ! grep -F -- 'doctor_report_main "$@"' <<<"${pre_common}" >/dev/null; then
  fail "doctor-report/doctor --help must use doctor_report.sh before common.sh is sourced"
fi

doctor_case="$(extract_case_block "${cli_file}" 'doctor-report|doctor')"
if [[ -z "${doctor_case}" ]]; then
  fail "sillytavern.sh must dispatch doctor-report/doctor"
else
  grep -F -- "doctor_report.sh" <<<"${doctor_case}" >/dev/null ||
    fail "doctor case must call doctor_report.sh"
  grep -F -- "update_st" <<<"${doctor_case}" >/dev/null &&
    fail "doctor case must not call update_st"
  grep -F -- "print_final_info" <<<"${doctor_case}" >/dev/null &&
    fail "doctor case must not call print_final_info"
fi

if [[ -f "${doctor_file}" ]]; then
  assert_file_contains "${doctor_file}" "doctor_report_main" \
    "doctor_report.sh must expose doctor_report_main"
  assert_file_contains "${doctor_file}" "doctor_redact_stream" \
    "doctor_report.sh must expose doctor_redact_stream for fixture tests"
  assert_file_contains "${doctor_file}" "config -q" \
    "Compose Validation must use docker compose config -q only"
  assert_file_contains "${doctor_file}" "Command Evidence" \
    "report must include command evidence"
  assert_file_contains "${doctor_file}" "--stdout" \
    "doctor_report.sh must support --stdout"
  assert_file_contains "${doctor_file}" "--output" \
    "doctor_report.sh must support --output"
  assert_file_contains "${doctor_file}" "--no-logs" \
    "doctor_report.sh must support --no-logs"
  assert_file_contains "${doctor_file}" "--service" \
    "doctor_report.sh must support --service"
  assert_file_contains "${doctor_file}" "--all-services" \
    "doctor_report.sh must support --all-services"
  for section in \
    "## Summary" \
    "## Environment" \
    "## Toolkit Self-check" \
    "## Docker Compose" \
    "## SillyTavern Status" \
    "## Access Config" \
    "## Mirror Config" \
    "## Compose Validation" \
    "## Command Evidence" \
    "## Recent Logs" \
    "## Recommendations"
  do
    assert_file_contains "${doctor_file}" "${section}" \
      "doctor_report.sh must define required report section ${section}"
  done

  assert_file_not_contains_re "${doctor_file}" 'health\.sh|scripts/health|bash[[:space:]].*health' \
    "doctor report must not embed raw health.sh output"
  assert_file_not_contains_re "${doctor_file}" 'print_final_info|get_public_ip|sillytavern\.sh[[:space:]]+info' \
    "doctor report must not use info/final-info paths"
  assert_file_not_contains_re "${doctor_file}" 'detect_country|ipinfo\.io' \
    "doctor report must not trigger country or public IP probes"
  assert_file_not_contains_re "${doctor_file}" 'update_st|rollback|repair' \
    "doctor report must not connect update, rollback, or repair behavior"

  if grep -E -- 'compose(_in_app)?[[:space:]].*config([^[:alnum:]_-]|$)' "${doctor_file}" |
    grep -Fv -- 'config -q' >/dev/null; then
    fail "doctor report must not run full docker compose config without -q"
  fi
fi

assert_file_contains "${menu_file}" "doctor-report" \
  "toolkit menu must call scripts/sillytavern.sh doctor-report"

if ((failures > 0)); then
  echo "doctor_report_static: ${failures} failure(s)" >&2
  exit 1
fi

echo "doctor_report_static: ok"
