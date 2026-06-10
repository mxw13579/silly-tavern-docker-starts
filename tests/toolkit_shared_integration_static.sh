#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

cli_file="sillytavern-toolkit/scripts/sillytavern.sh"
menu_file="sillytavern-toolkit/st-toolkit.sh"
self_check_file="sillytavern-toolkit/scripts/toolkit/self_check.sh"
self_check_bats_file="tests/bats/toolkit_self_check.bats"

fail() {
  echo "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  grep -F -- "${needle}" "${file}" >/dev/null || fail "${message}"
}

[[ -f "${cli_file}" ]] || fail "sillytavern.sh must exist"
[[ -f "${menu_file}" ]] || fail "st-toolkit.sh must exist"
[[ -f "${self_check_file}" ]] || fail "self_check.sh must exist"
[[ -f "${self_check_bats_file}" ]] || fail "toolkit_self_check.bats must exist"

for syntax_file in "${cli_file}" "${menu_file}" "${self_check_file}" "${self_check_bats_file}"; do
  bash -n "${syntax_file}"
done

assert_file_contains "${cli_file}" '. "${__st_scripts_dir}/sillytavern/logs.sh"' \
  "sillytavern.sh must source the logs module directly"
assert_file_contains "${cli_file}" '"${1:-}" == "self-check"' \
  "sillytavern.sh self-check must skip source-time sudo checks"
assert_file_contains "${cli_file}" '"${1:-}" == "check"' \
  "sillytavern.sh check alias must skip source-time sudo checks"
assert_file_contains "${cli_file}" "logs tail --lines 200" \
  "sillytavern.sh help must show logs tail"
assert_file_contains "${cli_file}" "logs follow --lines 100" \
  "sillytavern.sh help must show logs follow"
assert_file_contains "${cli_file}" "logs since 30m --lines 1000" \
  "sillytavern.sh help must show logs since"
assert_file_contains "${cli_file}" "logs save --output /path/to/sillytavern.log" \
  "sillytavern.sh help must show logs save"
assert_file_contains "${cli_file}" "self-check|check)" \
  "sillytavern.sh must dispatch self-check and check alias"
assert_file_contains "${cli_file}" 'bash "${__st_scripts_dir}/toolkit/self_check.sh" "$@"' \
  "sillytavern.sh must execute toolkit self-check through bash"

if ! awk '/logs\)/{seen=1; next} seen && /shift/{shifted=1} seen && /logs_st "\$@"/{called=1; exit} END{exit !(shifted && called)}' "${cli_file}"; then
  fail "logs dispatch must shift command name and forward arguments to logs_st"
fi

assert_file_contains "${menu_file}" "日志查看/导出入口" \
  "menu option 8 must become the logs view/export entry"
assert_file_contains "${menu_file}" 'logs tail' \
  "menu logs entry must call logs tail"
assert_file_contains "${menu_file}" 'logs follow' \
  "menu logs entry must hint follow"
assert_file_contains "${menu_file}" 'logs save --output' \
  "menu logs entry must hint save"
assert_file_contains "${menu_file}" "工具箱自检" \
  "menu must expose toolkit self-check"
assert_file_contains "${menu_file}" '"${SCRIPT_DIR}/scripts/sillytavern.sh" self-check' \
  "menu self-check item must call sillytavern.sh self-check"

assert_file_contains "${self_check_file}" "scripts/sillytavern/logs.sh" \
  "self-check must include logs module in file/syntax checks"
assert_file_contains "${self_check_bats_file}" "scripts/sillytavern/logs.sh" \
  "self-check Bats healthy fixture must create logs.sh"
assert_file_contains "${self_check_bats_file}" "#@test" \
  "self-check Bats tests must use the project registration marker"

if grep -E -- '^function[[:space:]]+test_[^{]+[[:space:]]*\{' "${self_check_bats_file}" |
  grep -Fv -- '#@test' >/dev/null; then
  fail "self-check Bats test functions must be registered with #@test"
fi

if grep -E -- 'self-update|self_update|update_toolkit|download|git[[:space:]]+(pull|fetch|merge|checkout|reset)' "${self_check_file}" >/dev/null; then
  fail "self-check must not contain update, download, or git mutation behavior"
fi

if grep -E -- '(^|[[:space:]])(curl|wget)[[:space:]]+(-|https?://)' "${self_check_file}" >/dev/null; then
  fail "self-check must not execute curl or wget download/probe behavior"
fi

if grep -E -- 'docker[[:space:]]+(pull|up|down|restart|stop|rm|run)|docker[[:space:]]+compose[[:space:]]+(pull|up|down|restart|stop|rm|run)|docker-compose[[:space:]]+(pull|up|down|restart|stop|rm|run)|compose_in_app' "${self_check_file}" >/dev/null; then
  fail "self-check must not execute Docker lifecycle behavior"
fi
