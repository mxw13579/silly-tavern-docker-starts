#!/usr/bin/env bats

load "../helpers/stubs.bash"

@test "sillytavern.sh non-interactive public mode fails before writing when credentials missing" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/config.sh"

    marker_dir="${BATS_TEST_TMPDIR}/markers_missing"
    mkdir -p "${marker_dir}"
    generate_compose_file() { printf "called" >"${marker_dir}/compose"; }
    write_sillytavern_config() { printf "called" >"${marker_dir}/config"; }
    prepare_app_dirs() { printf "called" >"${marker_dir}/dirs"; }

    export ST_ACCESS_MODE="public"
    unset ST_AUTH_USER
    unset ST_AUTH_PASS
    configure_sillytavern_non_interactive
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ST_AUTH_USER"
  [[ ! -f "${BATS_TEST_TMPDIR}/markers_missing/compose" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/markers_missing/config" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/markers_missing/dirs" ]]
}

@test "sillytavern.sh non-interactive public mode fails before writing when credentials invalid" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/config.sh"

    marker_dir="${BATS_TEST_TMPDIR}/markers_invalid"
    mkdir -p "${marker_dir}"
    generate_compose_file() { printf "called" >"${marker_dir}/compose"; }
    write_sillytavern_config() { printf "called" >"${marker_dir}/config"; }
    prepare_app_dirs() { printf "called" >"${marker_dir}/dirs"; }

    export ST_ACCESS_MODE="public"
    export ST_AUTH_USER="12"
    export ST_AUTH_PASS="ok_pass"
    configure_sillytavern_non_interactive
  '

  [[ "${status}" -ne 0 ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/markers_invalid/compose" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/markers_invalid/config" ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/markers_invalid/dirs" ]]
}

@test "sillytavern.sh interactive public mode orders credential validation before compose write" {
  run bash -c '
    set -euo pipefail
    config_file="sillytavern-toolkit/scripts/sillytavern/config.sh"
    user_line="$(grep -nF "validate_credential \"\${username}\" || fatal" "${config_file}" | cut -d: -f1)"
    pass_line="$(grep -nF "validate_credential \"\${password}\" || fatal" "${config_file}" | cut -d: -f1)"
    write_line="$(grep -nF "write_sillytavern_config \"y\" \"\${username}\" \"\${password}\"" "${config_file}" | cut -d: -f1)"
    compose_line="$(awk -v start="${pass_line}" -v end="${write_line}" "
      NR > start && NR < end && /generate_compose_file/ { print NR; exit }
    " "${config_file}")"

    [[ -n "${user_line}" ]]
    [[ -n "${pass_line}" ]]
    [[ -n "${compose_line}" ]]
    (( user_line < compose_line ))
    (( pass_line < compose_line ))
  '

  assert_status_eq 0
}

@test "sillytavern.sh non-interactive env parsing: local/public and bool_to_yn" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --

    source "sillytavern-toolkit/scripts/common.sh"
    source "sillytavern-toolkit/scripts/sillytavern/config.sh"

    generate_compose_file() { :; }
    write_sillytavern_config() { :; }
    prepare_app_dirs() { :; }

    export ST_ACCESS_MODE="local"
    export ST_ENABLE_WATCHTOWER="true"
    configure_sillytavern_non_interactive
    [[ "${ENABLE_EXTERNAL_ACCESS}" == "n" ]]
    [[ "${ENABLE_WATCHTOWER}" == "y" ]]

    export ST_ACCESS_MODE="public"
    export ST_AUTH_USER="user_ok"
    export ST_AUTH_PASS="pass_ok"
    export ST_ENABLE_WATCHTOWER="0"
    configure_sillytavern_non_interactive
    [[ "${ENABLE_EXTERNAL_ACCESS}" == "y" ]]
    [[ "${ENABLE_WATCHTOWER}" == "n" ]]
  '

  assert_status_eq 0
}

@test "sillytavern.sh facade smoke: --non-interactive status in test mode does not write compose/config" {
  local stub_dir
  stub_dir="$(make_stub_dir)"

  # Hard-fail if sudo/network is touched.
  write_exe "${stub_dir}/sudo" \
    '#!/usr/bin/env bash' \
    'echo "unexpected sudo" >&2' \
    'exit 99'
  write_exe "${stub_dir}/curl" \
    '#!/usr/bin/env bash' \
    'echo "unexpected curl" >&2' \
    'exit 99'
  write_exe "${stub_dir}/wget" \
    '#!/usr/bin/env bash' \
    'echo "unexpected wget" >&2' \
    'exit 99'

  prepend_path "${stub_dir}"

  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    export APP_DIR="${BATS_TEST_TMPDIR}/st_app"

    bash "sillytavern-toolkit/scripts/sillytavern.sh" --non-interactive status

    [[ ! -e "${APP_DIR}/docker-compose.yaml" ]]
    [[ ! -e "${APP_DIR}/config/config.yaml" ]]
  '

  assert_status_eq 0
}
