#!/usr/bin/env bats

load "../helpers/stubs.bash"

@test "change_access_st applies compose changes instead of restart-only flow" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${ST_COMPOSE_FILE}"
    printf "data: {}\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    configure_sillytavern_non_interactive() {
      printf "configured\n" >"${BATS_TEST_TMPDIR}/configured"
    }
    apply_compose_changes_st() {
      printf "applied\n" >"${BATS_TEST_TMPDIR}/applied"
    }
    restart_st() {
      printf "restart\n" >"${BATS_TEST_TMPDIR}/restart"
      return 99
    }

    NON_INTERACTIVE=1
    change_access_st

    [[ -f "${BATS_TEST_TMPDIR}/configured" ]]
    [[ -f "${BATS_TEST_TMPDIR}/applied" ]]
    [[ ! -f "${BATS_TEST_TMPDIR}/restart" ]]
  '

  assert_status_eq 0
}

@test "change_access_st creates backup before configure" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${ST_COMPOSE_FILE}"
    printf "data: {}\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    backup_access_config() {
      printf "backup\n" >>"${BATS_TEST_TMPDIR}/order"
      LAST_ACCESS_BACKUP_DIR="${BATS_TEST_TMPDIR}/backup"
    }
    configure_sillytavern_non_interactive() {
      printf "configure\n" >>"${BATS_TEST_TMPDIR}/order"
    }
    apply_compose_changes_st() {
      printf "apply\n" >>"${BATS_TEST_TMPDIR}/order"
    }

    NON_INTERACTIVE=1
    change_access_st

    [[ "$(cat "${BATS_TEST_TMPDIR}/order")" == $'"'"'backup\nconfigure\napply'"'"' ]]
  '

  assert_status_eq 0
}

@test "change_access_st rolls back with this call backup even if global changes later" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${ST_COMPOSE_FILE}"
    printf "data: {}\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    backup_access_config() {
      LAST_ACCESS_BACKUP_DIR="${BATS_TEST_TMPDIR}/this-backup"
    }
    configure_sillytavern_non_interactive() {
      LAST_ACCESS_BACKUP_DIR="${BATS_TEST_TMPDIR}/polluted-backup"
    }
    apply_compose_changes_st() { return 42; }
    apply_restored_access_config() {
      printf "%s\n" "$1" >"${BATS_TEST_TMPDIR}/rollback_arg"
      return 7
    }

    NON_INTERACTIVE=1
    change_access_st
  '

  [[ "${status}" -eq 7 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/rollback_arg")" == "${BATS_TEST_TMPDIR}/this-backup" ]]
}

@test "backup_access_config does not mark incomplete mkdir backup as current" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "services: {}\n" >"${ST_COMPOSE_FILE}"
    printf "data: {}\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"
    write_last_marker() {
      printf "%s\n" "${LAST_ACCESS_BACKUP_DIR:-}" >"${BATS_TEST_TMPDIR}/last_marker"
    }
    trap write_last_marker EXIT

    LAST_ACCESS_BACKUP_DIR="stale"
    SUDO=(false)

    backup_access_config
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "无法创建备份目录"
  [[ "$(cat "${BATS_TEST_TMPDIR}/last_marker")" == "" ]]
}

@test "backup_access_config does not mark incomplete cp backup as current" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config" "${BATS_TEST_TMPDIR}/stubs"
    printf "services: {}\n" >"${ST_COMPOSE_FILE}"
    printf "data: {}\n" >"${ST_CONFIG_FILE}"
    cat >"${BATS_TEST_TMPDIR}/stubs/sudo-fail-cp" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
case "$1" in
  mkdir) exit 0 ;;
  cp) exit 42 ;;
esac
exec "$@"
EOF
    chmod +x "${BATS_TEST_TMPDIR}/stubs/sudo-fail-cp"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"
    write_last_marker() {
      printf "%s\n" "${LAST_ACCESS_BACKUP_DIR:-}" >"${BATS_TEST_TMPDIR}/last_marker"
    }
    trap write_last_marker EXIT

    LAST_ACCESS_BACKUP_DIR="stale"
    SUDO=("${BATS_TEST_TMPDIR}/stubs/sudo-fail-cp")

    backup_access_config
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "无法备份 docker-compose.yaml"
  [[ "$(cat "${BATS_TEST_TMPDIR}/last_marker")" == "" ]]
}

@test "change_access_st restores backup and skips new apply when configure fails" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "old compose\n" >"${ST_COMPOSE_FILE}"
    printf "old config\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    configure_sillytavern_non_interactive() {
      printf "new compose\n" >"${ST_COMPOSE_FILE}"
      printf "new config\n" >"${ST_CONFIG_FILE}"
      return 42
    }
    apply_compose_changes_st() {
      printf "%s:%s\n" "$(cat "${ST_COMPOSE_FILE}")" "$(cat "${ST_CONFIG_FILE}")" >"${BATS_TEST_TMPDIR}/apply_seen"
    }

    NON_INTERACTIVE=1
    change_access_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "old config" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/apply_seen")" == "old compose:old config" ]]
  assert_output_contains "访问配置生成失败"
}

@test "change_access_st reports configure rollback apply failure" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "old compose\n" >"${ST_COMPOSE_FILE}"
    printf "old config\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    configure_sillytavern_non_interactive() {
      printf "new compose\n" >"${ST_COMPOSE_FILE}"
      printf "new config\n" >"${ST_CONFIG_FILE}"
      return 42
    }
    apply_compose_changes_st() {
      printf "apply\n" >>"${BATS_TEST_TMPDIR}/apply_calls"
      return 43
    }

    NON_INTERACTIVE=1
    change_access_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "old config" ]]
  [[ "$(wc -l <"${BATS_TEST_TMPDIR}/apply_calls" | tr -d " ")" == "1" ]]
  assert_output_contains "rollback apply failed"
}

@test "change_access_st restores previous files when compose apply fails" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "old compose\n" >"${ST_COMPOSE_FILE}"
    printf "old config\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    configure_sillytavern_non_interactive() {
      printf "new compose\n" >"${ST_COMPOSE_FILE}"
      printf "new config\n" >"${ST_CONFIG_FILE}"
    }
    apply_compose_changes_st() { return 42; }

    NON_INTERACTIVE=1
    change_access_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "old config" ]]
}

@test "change_access_st restores files and reapplies restored compose after apply failure" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "old compose\n" >"${ST_COMPOSE_FILE}"
    printf "old config\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    configure_sillytavern_non_interactive() {
      printf "new compose\n" >"${ST_COMPOSE_FILE}"
      printf "new config\n" >"${ST_CONFIG_FILE}"
    }
    apply_compose_changes_st() {
      apply_count_file="${BATS_TEST_TMPDIR}/apply_count"
      count=0
      [[ -f "${apply_count_file}" ]] && count="$(cat "${apply_count_file}")"
      count=$((count + 1))
      printf "%s\n" "${count}" >"${apply_count_file}"
      printf "%s:%s:%s\n" "${count}" "$(cat "${ST_COMPOSE_FILE}")" "$(cat "${ST_CONFIG_FILE}")" >>"${BATS_TEST_TMPDIR}/apply_seen"
      [[ "${count}" -eq 2 ]]
    }

    NON_INTERACTIVE=1
    change_access_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "old config" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/apply_count")" == "2" ]]
  grep -F -- "1:new compose:new config" "${BATS_TEST_TMPDIR}/apply_seen"
  grep -F -- "2:old compose:old config" "${BATS_TEST_TMPDIR}/apply_seen"
}

@test "change_access_st reports when restored compose reapply also fails" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    mkdir -p "${APP_DIR}/config"
    printf "old compose\n" >"${ST_COMPOSE_FILE}"
    printf "old config\n" >"${ST_CONFIG_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    configure_sillytavern_non_interactive() {
      printf "new compose\n" >"${ST_COMPOSE_FILE}"
      printf "new config\n" >"${ST_CONFIG_FILE}"
    }
    apply_compose_changes_st() {
      printf "apply\n" >>"${BATS_TEST_TMPDIR}/apply_calls"
      return 42
    }

    NON_INTERACTIVE=1
    change_access_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "old config" ]]
  [[ "$(wc -l <"${BATS_TEST_TMPDIR}/apply_calls" | tr -d " ")" == "2" ]]
  assert_output_contains "rollback apply failed"
}

@test "restore_access_files_from_backup rejects empty backup directory" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    restore_access_files_from_backup ""
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "备份目录为空"
}

@test "restore_access_files_from_backup rejects missing compose backup" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    backup_dir="${BATS_TEST_TMPDIR}/backup"
    mkdir -p "${backup_dir}"
    printf "old config\n" >"${backup_dir}/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    restore_access_files_from_backup "${backup_dir}"
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "备份缺少 docker-compose.yaml"
}

@test "restore_access_files_from_backup rejects missing config backup" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    backup_dir="${BATS_TEST_TMPDIR}/backup"
    mkdir -p "${backup_dir}"
    printf "old compose\n" >"${backup_dir}/docker-compose.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    restore_access_files_from_backup "${backup_dir}"
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "备份缺少 config.yaml"
}

@test "restore_access_files_from_backup reports compose restore copy failure" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    backup_dir="${BATS_TEST_TMPDIR}/backup"
    mkdir -p "${APP_DIR}/config" "${backup_dir}"
    printf "current compose\n" >"${ST_COMPOSE_FILE}"
    printf "current config\n" >"${ST_CONFIG_FILE}"
    printf "old compose\n" >"${backup_dir}/docker-compose.yaml"
    printf "old config\n" >"${backup_dir}/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    sudo_fail_compose_restore() {
      if [[ "$1" == "cp" && "$4" == "${ST_COMPOSE_FILE}" ]]; then
        return 42
      fi
      command "$@"
    }
    SUDO=(sudo_fail_compose_restore)

    restore_access_files_from_backup "${backup_dir}"
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "无法恢复 docker-compose.yaml"
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "current compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "current config" ]]
}

@test "restore_access_files_from_backup reports config restore copy failure" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    export ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"
    backup_dir="${BATS_TEST_TMPDIR}/backup"
    mkdir -p "${APP_DIR}/config" "${backup_dir}"
    printf "current compose\n" >"${ST_COMPOSE_FILE}"
    printf "current config\n" >"${ST_CONFIG_FILE}"
    printf "old compose\n" >"${backup_dir}/docker-compose.yaml"
    printf "old config\n" >"${backup_dir}/config.yaml"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/access.sh"

    sudo_fail_config_restore() {
      if [[ "$1" == "cp" && "$4" == "${ST_CONFIG_FILE}" ]]; then
        return 43
      fi
      command "$@"
    }
    SUDO=(sudo_fail_config_restore)

    restore_access_files_from_backup "${backup_dir}"
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "无法恢复 config.yaml"
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/docker-compose.yaml")" == "old compose" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/st_app/config/config.yaml")" == "current config" ]]
}

@test "apply_compose_changes_st reconciles compose project with remove-orphans and optional force recreate" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    mkdir -p "${APP_DIR}"
    printf "services: {}\n" >"${ST_COMPOSE_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"

    check_docker_env() { return 0; }
    compose_in_app() {
      printf "%s\n" "$*" >>"${BATS_TEST_TMPDIR}/compose_calls"
    }

    apply_compose_changes_st
    ST_FORCE_RECREATE=1 apply_compose_changes_st

    grep -F -- "up -d --remove-orphans" "${BATS_TEST_TMPDIR}/compose_calls"
    grep -F -- "up -d --remove-orphans --force-recreate" "${BATS_TEST_TMPDIR}/compose_calls"
    ! grep -F -- " restart" "${BATS_TEST_TMPDIR}/compose_calls"
  '

  assert_status_eq 0
}

@test "apply_compose_changes_st returns non-zero when compose up fails" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"
    export ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
    mkdir -p "${APP_DIR}"
    printf "services: {}\n" >"${ST_COMPOSE_FILE}"

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/compose.sh"
    source "sillytavern-toolkit/scripts/sillytavern/lifecycle.sh"

    check_docker_env() { return 0; }
    compose_in_app() {
      printf "%s\n" "$*" >"${BATS_TEST_TMPDIR}/compose_call"
      return 42
    }

    apply_compose_changes_st
  '

  [[ "${status}" -ne 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/compose_call")" == *"up -d --remove-orphans"* ]]
}
