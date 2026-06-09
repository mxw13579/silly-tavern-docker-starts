#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

validation_file="sillytavern-toolkit/scripts/sillytavern/validation.sh"
cli_file="sillytavern-toolkit/scripts/sillytavern.sh"
lifecycle_file="sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"
access_file="sillytavern-toolkit/scripts/sillytavern/access.sh"

[[ -f "${validation_file}" ]]

grep -F -- "validate_sillytavern_compose()" "${validation_file}" >/dev/null
grep -F -- '--skip-docker-check' "${validation_file}" >/dev/null
grep -F -- "config -q" "${validation_file}" >/dev/null
grep -F -- 'problem:' "${validation_file}" >/dev/null
grep -F -- 'impact:' "${validation_file}" >/dev/null
grep -F -- 'fix:' "${validation_file}" >/dev/null
grep -F -- '"${SUDO[@]}" sha256sum' "${validation_file}" >/dev/null
grep -F -- '"${SUDO[@]}" shasum -a 256' "${validation_file}" >/dev/null
grep -F -- "当前 Compose 文件不适合应用" "${validation_file}" >/dev/null

if grep -F -- "compose/config 组合" "${validation_file}" >/dev/null; then
  echo "validate compose failure text must not imply config.yaml content parsing" >&2
  exit 1
fi

validation_problem_body="$(
  awk '
    /^print_validation_problem\(\) \{/ {in_body=1}
    in_body {print}
    in_body && /^}/ {exit}
  ' "${validation_file}"
)"

for label in problem impact fix; do
  if ! grep -E -- "ERROR:[[:space:]]+${label}:.*(>&2|1>&2)" <<<"${validation_problem_body}" >/dev/null; then
    echo "print_validation_problem must send ${label} to stderr" >&2
    exit 1
  fi
done

grep -F -- '. "${__st_scripts_dir}/sillytavern/validation.sh"' "${cli_file}" >/dev/null
grep -F -- "validate         校验 SillyTavern Compose 配置并检查 config 文件存在" "${cli_file}" >/dev/null
grep -F -- "validate)" "${cli_file}" >/dev/null
grep -F -- "validate_sillytavern_compose" "${lifecycle_file}" >/dev/null
grep -F -- "validate_sillytavern_compose --skip-docker-check" "${lifecycle_file}" >/dev/null
grep -F -- '--skip-validation' "${lifecycle_file}" >/dev/null
grep -F -- "validate_sillytavern_compose" "${access_file}" >/dev/null
grep -F -- "apply_compose_changes_st" "${access_file}" >/dev/null

if grep -F -- "validate         校验 SillyTavern compose/config" "${cli_file}" >/dev/null; then
  echo "validate usage text must not imply config.yaml content parsing" >&2
  exit 1
fi

if grep -F -- "hash_compose" "${cli_file}" >/dev/null || grep -F -- "hash_config" "${cli_file}" >/dev/null; then
  echo "hash helpers must not be exposed as sillytavern.sh CLI commands" >&2
  exit 1
fi

if grep -F -- "restart_st" "${access_file}" | grep -F -- "restore_access_st" >/dev/null; then
  echo "restore_access_st should not call restart_st" >&2
  exit 1
fi

access_restore_body="$(
  awk '
    /^restore_access_st\(\) \{/ {in_body=1}
    in_body {print}
    in_body && /^}/ {exit}
  ' "${access_file}"
)"

grep -F -- "validate_sillytavern_compose" <<<"${access_restore_body}" >/dev/null
grep -F -- "apply_compose_changes_st --skip-validation" <<<"${access_restore_body}" >/dev/null

if grep -F -- "restart_st" <<<"${access_restore_body}" >/dev/null; then
  echo "restore_access_st body must not call restart_st" >&2
  exit 1
fi
