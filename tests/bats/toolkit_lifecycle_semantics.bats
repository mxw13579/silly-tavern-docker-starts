#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2154

load "../helpers/stubs.bash"

setup() {
  export ST_TOOLKIT_TEST_MODE=1
  export ST_TOOLKIT_REQUIRE_SUDO=0
  export ST_TOOLKIT_SKIP_COUNTRY=1
  export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
  export DOCKER_CALLS="${BATS_TEST_TMPDIR}/docker_calls"

  mkdir -p "${APP_DIR}/config"
  printf 'services: {}\n' >"${APP_DIR}/docker-compose.yaml"
  printf 'listen: true\n' >"${APP_DIR}/config/config.yaml"
  : >"${DOCKER_CALLS}"

  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${DOCKER_CALLS}"' \
    'if [[ "${ST_DOCKER_FAIL:-}" == "$*" ]]; then exit 99; fi' \
    'case "$*" in' \
    '  "info") exit 0 ;;' \
    '  "compose version") exit 0 ;;' \
    '  "compose config -q") exit 0 ;;' \
    '  "compose stop") exit 0 ;;' \
    '  "compose down") exit 0 ;;' \
    '  "compose restart") exit 0 ;;' \
    '  "compose pull") exit 0 ;;' \
    '  "compose up -d") exit 0 ;;' \
    '  "compose up -d --remove-orphans") exit 0 ;;' \
    'esac' \
    'exit 42'
  prepend_path "${stub_dir}"
}

run_st() {
  env \
    ST_TOOLKIT_TEST_MODE="${ST_TOOLKIT_TEST_MODE}" \
    ST_TOOLKIT_REQUIRE_SUDO="${ST_TOOLKIT_REQUIRE_SUDO}" \
    ST_TOOLKIT_SKIP_COUNTRY="${ST_TOOLKIT_SKIP_COUNTRY}" \
    ST_FORCE_RECREATE="${ST_FORCE_RECREATE:-}" \
    ST_DOCKER_FAIL="${ST_DOCKER_FAIL:-}" \
    APP_DIR="${APP_DIR}" \
    DOCKER_CALLS="${DOCKER_CALLS}" \
    bash sillytavern-toolkit/scripts/sillytavern.sh "$@"
}

docker_calls() {
  cat "${DOCKER_CALLS}"
}

semantic_calls() {
  grep -E '^compose (config -q|pull|up -d|stop$|down|restart$)' "${DOCKER_CALLS}" || true
}

assert_no_call_matching() {
  local pattern="$1"

  if grep -E -- "${pattern}" "${DOCKER_CALLS}" >/dev/null; then
    return 1
  fi
}

assert_no_call_containing() {
  local needle="$1"

  if grep -F -- "${needle}" "${DOCKER_CALLS}" >/dev/null; then
    return 1
  fi
}

function cli_stop_calls_compose_stop_and_never_calls_down { #@test
  run run_st stop

  assert_status_eq 0
  grep -Fx -- "compose stop" "${DOCKER_CALLS}"
  assert_no_call_matching '^compose down'
}

function cli_stop_returns_non_zero_when_compose_stop_fails_without_success_message { #@test
  ST_DOCKER_FAIL="compose stop" run run_st stop

  [[ "${status}" -ne 0 ]]
  grep -Fx -- "compose stop" "${DOCKER_CALLS}"
  [[ "${output}" != *"已停止"* ]]
}

function cli_stop_rejects_extra_arguments_without_calling_compose_stop { #@test
  run run_st stop unexpected

  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"stop 不接受额外参数。"* ]]
  assert_no_call_matching '^compose stop$'
}

function cli_down_calls_plain_compose_down_without_destructive_flags { #@test
  run run_st down

  assert_status_eq 0
  grep -Fx -- "compose down" "${DOCKER_CALLS}"
  assert_no_call_containing "--volumes"
  assert_no_call_containing "--rmi"
}

function cli_down_rejects_volumes_instead_of_passing_it_to_compose { #@test
  run run_st down --volumes

  [[ "${status}" -ne 0 ]]
  assert_no_call_containing "compose down --volumes"
}

function cli_down_rejects_rmi_instead_of_passing_it_to_compose { #@test
  run run_st down --rmi all

  [[ "${status}" -ne 0 ]]
  assert_no_call_containing "compose down --rmi"
}

function cli_apply_validates_then_applies_up_with_remove_orphans { #@test
  run run_st apply

  assert_status_eq 0
  [[ "$(semantic_calls)" == $'compose config -q\ncompose up -d --remove-orphans' ]]
}

function cli_apply_rejects_extra_arguments { #@test
  run run_st apply unexpected

  [[ "${status}" -ne 0 ]]
  assert_no_call_matching '^compose up'
}

function cli_restart_calls_compose_restart_without_validate_or_up { #@test
  run run_st restart

  assert_status_eq 0
  grep -Fx -- "compose restart" "${DOCKER_CALLS}"
  assert_no_call_containing "compose config -q"
  assert_no_call_matching '^compose up'
  assert_no_call_matching '^compose down'
}

function cli_restart_returns_non_zero_when_compose_restart_fails_without_success_message { #@test
  ST_DOCKER_FAIL="compose restart" run run_st restart

  [[ "${status}" -ne 0 ]]
  grep -Fx -- "compose restart" "${DOCKER_CALLS}"
  [[ "${output}" != *"已重启"* ]]
}

function cli_restart_rejects_extra_arguments_without_calling_compose_restart { #@test
  run run_st restart unexpected

  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"restart 不接受额外参数。"* ]]
  assert_no_call_matching '^compose restart$'
}

function cli_update_keeps_validate_pull_up_order_and_is_not_safe_update { #@test
  run run_st update

  assert_status_eq 0
  [[ "$(semantic_calls)" == $'compose config -q\ncompose pull\ncompose up -d' ]]
  assert_no_call_containing "--remove-orphans"
  [[ "$(docker_calls)" != *"backup"* ]]
  [[ "$(docker_calls)" != *"doctor"* ]]
}

function cli_update_ignores_st_force_recreate_and_keeps_plain_up_order { #@test
  ST_FORCE_RECREATE=1 run run_st update

  assert_status_eq 0
  [[ "$(semantic_calls)" == $'compose config -q\ncompose pull\ncompose up -d' ]]
  assert_no_call_containing "--force-recreate"
  assert_no_call_containing "--remove-orphans"
}

function cli_update_rejects_extra_arguments_without_calling_compose_update_steps { #@test
  run run_st update unexpected

  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"update 不接受额外参数。"* ]]
  assert_no_call_matching '^compose config -q$'
  assert_no_call_matching '^compose pull$'
  assert_no_call_matching '^compose up -d$'
}
