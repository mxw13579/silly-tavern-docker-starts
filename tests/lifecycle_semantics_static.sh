#!/usr/bin/env bash
set -euo pipefail

cli_file="sillytavern-toolkit/scripts/sillytavern.sh"
lifecycle_file="sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"
access_file="sillytavern-toolkit/scripts/sillytavern/access.sh"
menu_file="sillytavern-toolkit/st-toolkit.sh"

extract_function() {
  local name="$1"
  local file="$2"

  awk -v name="${name}" '
    BEGIN {
      plain = "^[[:space:]]*" name "\\(\\)[[:space:]]*\\{"
      func_plain = "^[[:space:]]*function[[:space:]]+" name "[[:space:]]*\\{"
      func_paren = "^[[:space:]]*function[[:space:]]+" name "\\(\\)[[:space:]]*\\{"
    }
    !in_body && ($0 ~ plain || $0 ~ func_plain || $0 ~ func_paren) {in_body=1}
    in_body {print}
    in_body && /^}/ {exit}
  ' "${file}"
}

fail() {
  echo "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  grep -F -- "${needle}" <<<"${haystack}" >/dev/null || fail "${message}"
}

assert_matches() {
  local haystack="$1"
  local pattern="$2"
  local message="$3"

  grep -E -- "${pattern}" <<<"${haystack}" >/dev/null || fail "${message}"
}

[[ -f "${cli_file}" ]]
[[ -f "${lifecycle_file}" ]]
[[ -f "${access_file}" ]]
[[ -f "${menu_file}" ]]

stop_body="$(extract_function stop_st "${lifecycle_file}")"
down_body="$(extract_function down_st "${lifecycle_file}")"
apply_body="$(extract_function apply_compose_changes_st "${lifecycle_file}")"
apply_without_validation_body="$(extract_function apply_compose_changes_without_validation_st "${lifecycle_file}")"
apply_impl_body="$(extract_function _apply_compose_changes_st_impl "${lifecycle_file}")"
restart_body="$(extract_function restart_st "${lifecycle_file}")"
update_body="$(extract_function update_st "${lifecycle_file}")"
access_restore_body="$(extract_function restore_access_st "${access_file}")"

assert_contains "${stop_body}" "compose_in_app" "stop_st must call compose_in_app"
assert_contains "${stop_body}" " stop" "stop_st must call plain compose stop"
if grep -E -- '(^|[[:space:]])down([[:space:]]|$)|down_st' <<<"${stop_body}" >/dev/null; then
  fail "stop_st must not map to down"
fi

assert_contains "${down_body}" "compose_in_app" "down_st must call compose_in_app"
if grep -F -- "compose_args=(down)" <<<"${down_body}" >/dev/null; then
  # shellcheck disable=SC2016
  assert_contains "${down_body}" '"${compose_args[@]}"' "down_st compose_args must be passed to compose_in_app"
  if grep -E -- 'compose_args\+=' <<<"${down_body}" >/dev/null; then
    fail "down_st must call plain down only"
  fi
else
  assert_matches "${down_body}" 'compose_in_app .*([[:space:]]|")down"?[[:space:]]*(\|\||$)' \
    "down_st must call plain compose down"
fi
if grep -E -- 'compose(_args|\+\=|_in_app).*(--volumes|--rmi)|(^|[;&|[:space:]])rm[[:space:]]+-rf' <<<"${down_body}" >/dev/null; then
  fail "down_st must not support destructive flags or delete files"
fi

if grep -F -- 'down [--volumes]' "${cli_file}" >/dev/null || grep -F -- '--rmi' "${cli_file}" >/dev/null; then
  fail "sillytavern.sh usage must not expose destructive down flags"
fi

assert_contains "${apply_impl_body}" "up -d --remove-orphans" \
  "_apply_compose_changes_st_impl must apply with up -d --remove-orphans"
assert_contains "${apply_body}" 'if (($# > 0))' \
  "apply_compose_changes_st must reject extra arguments"
assert_contains "${apply_body}" "_apply_compose_changes_st_impl 0" \
  "apply_compose_changes_st must call _apply_compose_changes_st_impl with validation enabled"
assert_contains "${apply_without_validation_body}" 'if (($# > 0))' \
  "apply_compose_changes_without_validation_st must reject extra arguments"
assert_contains "${apply_without_validation_body}" "_apply_compose_changes_st_impl" \
  "apply_compose_changes_without_validation_st must call the private implementation"
assert_matches "${apply_without_validation_body}" '_apply_compose_changes_st_impl[[:space:]]+1' \
  "apply_compose_changes_without_validation_st must disable validation through the private implementation"

assert_contains "${access_restore_body}" "apply_compose_changes_without_validation_st" \
  "restore_access_st must apply validated restores through the public no-validation wrapper"
if grep -F -- "_apply_compose_changes_st_impl" <<<"${access_restore_body}" >/dev/null; then
  fail "restore_access_st must not depend on the private compose apply implementation"
fi

assert_contains "${restart_body}" "restart" "restart_st must call compose restart"
if grep -E -- 'up -d|apply_compose_changes_st|validate_sillytavern_compose' <<<"${restart_body}" >/dev/null; then
  fail "restart_st must not validate, apply, or call up"
fi

validate_line="$(grep -nF -- "validate_sillytavern_compose" <<<"${update_body}" | head -n1 | cut -d: -f1)"
pull_line="$(grep -nF -- " pull" <<<"${update_body}" | head -n1 | cut -d: -f1)"
up_line="$(grep -nF -- " up -d" <<<"${update_body}" | head -n1 | cut -d: -f1)"
[[ -n "${validate_line}" ]] || fail "update_st must validate before pulling"
[[ -n "${pull_line}" ]] || fail "update_st must pull images"
[[ -n "${up_line}" ]] || fail "update_st must run plain up -d"
if ! ((validate_line < pull_line && pull_line < up_line)); then
  fail "update_st must keep validate -> pull -> up -d order"
fi
if grep -E -- 'apply_compose_changes_st|--remove-orphans' <<<"${update_body}" >/dev/null; then
  fail "update_st must not call apply_compose_changes_st or use --remove-orphans"
fi

if grep -E -- 'safe_update|rollback|doctor|backup_st|backup_manager' <<<"${update_body}" >/dev/null; then
  fail "update_st must not become safe update in lifecycle-semantics"
fi

for command in stop down apply restart update; do
  grep -F -- "${command})" "${cli_file}" >/dev/null || fail "sillytavern.sh must dispatch ${command}"
  grep -F -- "\"\${SCRIPT_DIR}/scripts/sillytavern.sh\" ${command}" "${menu_file}" >/dev/null ||
    fail "st-toolkit.sh menu must dispatch ${command}"
done

if grep -E -- '"\$\{SCRIPT_DIR\}/scripts/sillytavern\.sh" stop[[:space:]].*down|"\$\{SCRIPT_DIR\}/scripts/sillytavern\.sh" down[[:space:]].*stop' "${menu_file}" >/dev/null; then
  fail "SillyTavern menu must not cross-map stop and down"
fi

if grep -E -- '--volumes|--rmi|rm -rf' "${menu_file}" >/dev/null; then
  fail "SillyTavern menu must not expose destructive down flags"
fi
