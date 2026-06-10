#!/usr/bin/env bash
# shellcheck disable=SC2016
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
assert_file_contains "${logs_file}" 'if ! mv -f "${tmp_file}" "${output_path}"; then' \
  "save must explicitly handle final mv failure"
assert_file_contains "${logs_file}" "failed to finalize log file" \
  "save must report final mv failure instead of success"
assert_file_contains "${logs_file}" "output path is a directory" \
  "save must reject an existing output directory"
assert_file_contains "${logs_file}" "invalid --service value" \
  "--service must reject option-shaped values"
assert_file_contains "${logs_file}" 'ERROR: problem:' "errors must include problem guidance"
assert_file_contains "${logs_file}" 'ERROR: impact:' "errors must include impact guidance"
assert_file_contains "${logs_file}" 'ERROR: fix:' "errors must include fix guidance"

help_line="$(grep -nF -- 'help|--help|-h)' "${logs_file}" | head -n1 | cut -d: -f1)"
docker_check_line="$(grep -nF -- 'check_docker_env || return 1' "${logs_file}" | head -n1 | cut -d: -f1)"
[[ -n "${help_line}" && -n "${docker_check_line}" ]] ||
  fail "logs dispatch must contain help handling and Docker check"
if ! ((help_line < docker_check_line)); then
  fail "logs --help must return before Docker/install state checks"
fi

if grep -F -- "logs -f sillytavern" "${lifecycle_file}" >/dev/null; then
  fail "lifecycle logs_st must not keep infinite logs -f implementation"
fi

if grep -E -- 'logs[[:space:]]+-f|logs[[:space:]]+--follow' "${lifecycle_file}" >/dev/null; then
  fail "lifecycle must delegate logs behavior instead of owning follow semantics"
fi
