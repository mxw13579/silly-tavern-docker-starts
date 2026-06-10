#!/usr/bin/env bats
# shellcheck disable=SC2016

load "../helpers/stubs.bash"

setup_validation_fixture() {
  export ST_TOOLKIT_TEST_MODE=1
  export ST_TOOLKIT_REQUIRE_SUDO=0
  export ST_TOOLKIT_SKIP_COUNTRY=1
  export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
  export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
  export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
  mkdir -p "${APP_DIR}/config"
}

write_valid_st_files() {
  printf 'services:\n  sillytavern:\n    image: ghcr.io/sillytavern/sillytavern:latest\n' >"${ST_COMPOSE_FILE}"
  printf 'listen: true\n' >"${ST_CONFIG_FILE}"
}

@test "sillytavern.sh validate succeeds through compose config -q" {
  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${ST_COMPOSE_CALLS}"' \
    'case "$*" in' \
    '  "info") exit 0 ;;' \
    '  "compose version") exit 0 ;;' \
    '  "compose config -q") exit 0 ;;' \
    'esac' \
    'exit 42'
  prepend_path "${stub_dir}"

  setup_validation_fixture
  write_valid_st_files
  export ST_COMPOSE_CALLS="${BATS_TEST_TMPDIR}/compose_calls"

  run bash sillytavern-toolkit/scripts/sillytavern.sh validate

  assert_status_eq 0
  grep -Fx -- "compose config -q" "${ST_COMPOSE_CALLS}"
}

@test "sillytavern.sh does not expose hash helper commands as CLI" {
  run env \
    ST_TOOLKIT_TEST_MODE=1 \
    ST_TOOLKIT_REQUIRE_SUDO=0 \
    ST_TOOLKIT_SKIP_COUNTRY=1 \
    bash sillytavern-toolkit/scripts/sillytavern.sh hash_compose

  [[ "${status}" -ne 0 ]]
  [[ "${output}" != *"hash_compose"* ]]
  [[ "${output}" != *"hash_config"* ]]
}

@test "print_validation_problem writes problem impact and fix to stderr only" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"

    print_validation_problem "bad compose" "cannot apply" "run validate" \
      >"${BATS_TEST_TMPDIR}/stdout" \
      2>"${BATS_TEST_TMPDIR}/stderr"

    [[ ! -s "${BATS_TEST_TMPDIR}/stdout" ]]
    grep -F -- "problem: bad compose" "${BATS_TEST_TMPDIR}/stderr"
    grep -F -- "impact: cannot apply" "${BATS_TEST_TMPDIR}/stderr"
    grep -F -- "fix: run validate" "${BATS_TEST_TMPDIR}/stderr"
  '

  assert_status_eq 0
}

@test "validate_sillytavern_files fails when compose file is missing" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"
    printf "listen: true\n" >"${APP_DIR}/config/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    validate_sillytavern_files
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "problem:"
  assert_output_contains "impact:"
  assert_output_contains "fix:"
  assert_output_contains "docker-compose.yaml"
}

@test "validate_sillytavern_files fails when config file is missing" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${APP_DIR}/docker-compose.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    validate_sillytavern_files
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "problem:"
  assert_output_contains "impact:"
  assert_output_contains "fix:"
  assert_output_contains "config.yaml"
}

@test "validate_sillytavern_compose returns non-zero and explains compose config failure" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"
    printf "broken compose\n" >"${APP_DIR}/docker-compose.yaml"
    printf "listen: true\n" >"${APP_DIR}/config/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    check_docker_env() { return 0; }
    compose_in_app() {
      printf "%s\n" "$*" >"${BATS_TEST_TMPDIR}/compose_call"
      return 33
    }

    validate_sillytavern_compose
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "problem:"
  assert_output_contains "impact:"
  assert_output_contains "fix:"
  [[ "$(cat "${BATS_TEST_TMPDIR}/compose_call")" == *"config -q"* ]]
}

@test "validate_sillytavern_compose skip docker check avoids duplicate docker probe" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${APP_DIR}/docker-compose.yaml"
    printf "listen: true\n" >"${APP_DIR}/config/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    check_docker_env() {
      printf "check\n" >>"${BATS_TEST_TMPDIR}/docker_check"
      return 88
    }
    compose_in_app() {
      printf "%s\n" "$*" >"${BATS_TEST_TMPDIR}/compose_call"
      return 0
    }

    validate_sillytavern_compose --skip-docker-check
  '

  assert_status_eq 0
  [[ ! -e "${BATS_TEST_TMPDIR}/docker_check" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/compose_call")" == *"config -q"* ]]
}

@test "update_st validate failure does not run pull or up" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${APP_DIR}/docker-compose.yaml"
    printf "listen: true\n" >"${APP_DIR}/config/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    source "sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"
    check_docker_env() { printf "check\n" >>"${BATS_TEST_TMPDIR}/order"; return 0; }
    validate_sillytavern_compose() { printf "validate:%s\n" "$*" >>"${BATS_TEST_TMPDIR}/order"; return 22; }
    compose_in_app() { printf "%s\n" "$*" >>"${BATS_TEST_TMPDIR}/compose_calls"; return 0; }

    update_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/order")" == $'check\nvalidate:--skip-docker-check' ]]
  [[ ! -e "${BATS_TEST_TMPDIR}/compose_calls" ]]
}

@test "start_st validate failure does not run up" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${APP_DIR}/docker-compose.yaml"
    printf "listen: true\n" >"${APP_DIR}/config/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    source "sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"
    check_docker_env() { printf "check\n" >>"${BATS_TEST_TMPDIR}/order"; return 0; }
    validate_sillytavern_compose() { printf "validate:%s\n" "$*" >>"${BATS_TEST_TMPDIR}/order"; return 23; }
    compose_in_app() { printf "%s\n" "$*" >>"${BATS_TEST_TMPDIR}/compose_calls"; return 0; }

    start_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/order")" == $'check\nvalidate:--skip-docker-check' ]]
  [[ ! -e "${BATS_TEST_TMPDIR}/compose_calls" ]]
}

@test "apply_compose_changes_st validate failure does not run up" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${APP_DIR}/docker-compose.yaml"
    printf "listen: true\n" >"${APP_DIR}/config/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    source "sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"
    check_docker_env() { printf "check\n" >>"${BATS_TEST_TMPDIR}/order"; return 0; }
    validate_sillytavern_compose() { printf "validate:%s\n" "$*" >>"${BATS_TEST_TMPDIR}/order"; return 24; }
    compose_in_app() { printf "%s\n" "$*" >>"${BATS_TEST_TMPDIR}/compose_calls"; return 0; }

    apply_compose_changes_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/order")" == $'check\nvalidate:--skip-docker-check' ]]
  [[ ! -e "${BATS_TEST_TMPDIR}/compose_calls" ]]
}

@test "install_st validate failure after configuration does not run pull or up" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export NON_INTERACTIVE=1

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    source "sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"
    check_docker_env() { printf "check\n" >>"${BATS_TEST_TMPDIR}/order"; return 0; }
    configure_sillytavern_non_interactive() {
      printf "configure\n" >>"${BATS_TEST_TMPDIR}/order"
      mkdir -p "${APP_DIR}/config"
      printf "services: {}\n" >"${APP_DIR}/docker-compose.yaml"
      printf "listen: true\n" >"${APP_DIR}/config/config.yaml"
    }
    validate_sillytavern_compose() { printf "validate:%s\n" "$*" >>"${BATS_TEST_TMPDIR}/order"; return 25; }
    compose_in_app() { printf "%s\n" "$*" >>"${BATS_TEST_TMPDIR}/compose_calls"; return 0; }
    print_final_info() { printf "final\n" >>"${BATS_TEST_TMPDIR}/order"; }

    install_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/order")" == $'check\nconfigure\nvalidate:--skip-docker-check' ]]
  [[ ! -e "${BATS_TEST_TMPDIR}/compose_calls" ]]
}

@test "restore_access_st validates and applies restored files without restart" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config" "${APP_DIR}/backups/config/20260609_010203"
    printf "current compose\n" >"${APP_DIR}/docker-compose.yaml"
    printf "current config\n" >"${APP_DIR}/config/config.yaml"
    printf "old compose\n" >"${APP_DIR}/backups/config/20260609_010203/docker-compose.yaml"
    printf "old config\n" >"${APP_DIR}/backups/config/20260609_010203/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"
    ensure_interactive_tty() { return 0; }
    read_yes_no() { local __answer_var="$2"; printf -v "${__answer_var}" y; }
    validate_sillytavern_compose() { printf "validate\n" >>"${BATS_TEST_TMPDIR}/order"; }
    apply_compose_changes_without_validation_st() { printf "apply:%s\n" "$*" >>"${BATS_TEST_TMPDIR}/order"; }
    restart_st() { printf "restart\n" >>"${BATS_TEST_TMPDIR}/order"; return 99; }

    restore_access_st
  '

  assert_status_eq 0
  [[ "$(cat "${BATS_TEST_TMPDIR}/order")" == $'validate\napply:' ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "old config" ]]
}

@test "restore_access_st validate failure says restored but not applied and skips apply restart" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config" "${APP_DIR}/backups/config/20260609_010203"
    printf "current compose\n" >"${APP_DIR}/docker-compose.yaml"
    printf "current config\n" >"${APP_DIR}/config/config.yaml"
    printf "old compose\n" >"${APP_DIR}/backups/config/20260609_010203/docker-compose.yaml"
    printf "old config\n" >"${APP_DIR}/backups/config/20260609_010203/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"
    ensure_interactive_tty() { return 0; }
    read_yes_no() { local __answer_var="$2"; printf -v "${__answer_var}" y; }
    validate_sillytavern_compose() { printf "validate\n" >>"${BATS_TEST_TMPDIR}/order"; return 31; }
    apply_compose_changes_without_validation_st() { printf "apply\n" >>"${BATS_TEST_TMPDIR}/order"; return 0; }
    restart_st() { printf "restart\n" >>"${BATS_TEST_TMPDIR}/order"; return 99; }

    restore_access_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/order")" == "validate" ]]
  [[ "${output}" == *"尚未应用"* || "${output}" == *"已恢复但未应用"* ]]
  assert_output_contains "备份目录"
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "old config" ]]
}

@test "restore_access_st apply failure explains compose apply failure without restart" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config" "${APP_DIR}/backups/config/20260609_010203"
    printf "current compose\n" >"${APP_DIR}/docker-compose.yaml"
    printf "current config\n" >"${APP_DIR}/config/config.yaml"
    printf "old compose\n" >"${APP_DIR}/backups/config/20260609_010203/docker-compose.yaml"
    printf "old config\n" >"${APP_DIR}/backups/config/20260609_010203/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"
    ensure_interactive_tty() { return 0; }
    read_yes_no() { local __answer_var="$2"; printf -v "${__answer_var}" y; }
    validate_sillytavern_compose() { printf "validate\n" >>"${BATS_TEST_TMPDIR}/order"; return 0; }
    apply_compose_changes_without_validation_st() { printf "apply:%s\n" "$*" >>"${BATS_TEST_TMPDIR}/order"; return 32; }
    restart_st() { printf "restart\n" >>"${BATS_TEST_TMPDIR}/order"; return 99; }

    restore_access_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/order")" == $'validate\napply:' ]]
  assert_output_contains "Compose"
  assert_output_contains "应用失败"
  assert_output_contains "备份目录"
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "old config" ]]
}

@test "hash_file_sha256 reads through SUDO stub" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config" "${BATS_TEST_TMPDIR}/stubs"
    printf "secret config\n" >"${APP_DIR}/config/config.yaml"
    {
      printf "%s\n" "#!/usr/bin/env bash"
      printf "%s\n" "printf \"%s\\\\n\" \"\$*\" >>\"\${SUDO_CALLS}\""
      printf "%s\n" "exec \"\$@\""
    } >"${BATS_TEST_TMPDIR}/stubs/sudo-recorder"
    chmod +x "${BATS_TEST_TMPDIR}/stubs/sudo-recorder"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    export SUDO_CALLS="${BATS_TEST_TMPDIR}/sudo_calls"
    SUDO=("${BATS_TEST_TMPDIR}/stubs/sudo-recorder")

    hash_file_sha256 "${APP_DIR}/config/config.yaml" >"${BATS_TEST_TMPDIR}/hash_output"
    grep -E "^[0-9a-f]{64}$" "${BATS_TEST_TMPDIR}/hash_output"
    grep -F -- "sha256sum ${APP_DIR}/config/config.yaml" "${SUDO_CALLS}"
  '

  assert_status_eq 0
}

@test "hash_file_sha256 falls back to shasum and stays stable for same file" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config"
    printf "stable content\n" >"${APP_DIR}/config/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    SUDO=()

    expected_hash="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    command() {
      if [[ "${1:-}" == "-v" && "${2:-}" == "sha256sum" ]]; then
        return 1
      fi
      builtin command "$@"
    }
    shasum() {
      printf "%s  %s\n" "${expected_hash}" "${*: -1}"
    }

    first_hash="$(hash_file_sha256 "${APP_DIR}/config/config.yaml")"
    second_hash="$(hash_file_sha256 "${APP_DIR}/config/config.yaml")"
    [[ "${first_hash}" == "${expected_hash}" ]]
    [[ "${second_hash}" == "${first_hash}" ]]
  '

  assert_status_eq 0
}

@test "validate_sillytavern_compose supports docker-compose command facade" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    mkdir -p "${APP_DIR}/config" "${BATS_TEST_TMPDIR}/stubs"
    printf "services: {}\n" >"${APP_DIR}/docker-compose.yaml"
    printf "listen: true\n" >"${APP_DIR}/config/config.yaml"
    {
      printf "%s\n" "#!/usr/bin/env bash"
      printf "%s\n" "printf \"%s\\\\n\" \"\$*\" >>\"\${COMPOSE_CALLS}\""
      printf "%s\n" "[[ \"\$*\" == \"config -q\" ]]"
    } >"${BATS_TEST_TMPDIR}/stubs/docker-compose"
    chmod +x "${BATS_TEST_TMPDIR}/stubs/docker-compose"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/validation.sh"
    export COMPOSE_CALLS="${BATS_TEST_TMPDIR}/compose_calls"
    SUDO=()
    COMPOSE_CMD=("${BATS_TEST_TMPDIR}/stubs/docker-compose")
    check_docker_env() { return 0; }

    validate_sillytavern_compose
    grep -Fx -- "config -q" "${COMPOSE_CALLS}"
  '

  assert_status_eq 0
}
