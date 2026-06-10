#!/usr/bin/env bash
set -euo pipefail

logs_file="sillytavern-toolkit/scripts/sillytavern/logs.sh"
lifecycle_file="sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"

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

[[ -f "${logs_file}" ]] || fail "logs module must exist"
[[ -f "${lifecycle_file}" ]] || fail "lifecycle module must exist"

bash -n "${logs_file}"

assert_file_contains "${logs_file}" "logs_st()" "logs module must expose logs_st"
assert_file_contains "${logs_file}" "DEFAULT_LOG_TAIL_LINES=200" "logs default must be 200 lines"
assert_file_contains "${logs_file}" "DEFAULT_LOG_FOLLOW_LINES=100" "follow default must start at 100 lines"
assert_file_contains "${logs_file}" "DEFAULT_LOG_SINCE_LINES=1000" "since default must be bounded"
assert_file_contains "${logs_file}" "MAX_LOG_LINES=5000" "logs must cap accepted line counts"
assert_file_contains "${logs_file}" "--follow" "follow subcommand must be explicit"
assert_file_contains "${logs_file}" "mktemp" "save must write through a temporary file"
assert_file_contains "${logs_file}" "mv -f" "save must move temp file into place after compose succeeds"
assert_file_contains "${logs_file}" 'ERROR: problem:' "errors must include problem guidance"
assert_file_contains "${logs_file}" 'ERROR: impact:' "errors must include impact guidance"
assert_file_contains "${logs_file}" 'ERROR: fix:' "errors must include fix guidance"

if grep -F -- "logs -f sillytavern" "${lifecycle_file}" >/dev/null; then
  fail "lifecycle logs_st must not keep infinite logs -f implementation"
fi

if grep -E -- 'logs[[:space:]]+-f|logs[[:space:]]+--follow' "${lifecycle_file}" >/dev/null; then
  fail "lifecycle must delegate logs behavior instead of owning follow semantics"
fi
