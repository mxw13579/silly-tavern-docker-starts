#!/usr/bin/env bats

load "../helpers/stubs.bash"

@test "linux one-shot public mode writes Basic Auth before public compose binding" {
  run bash -c '
    set -euo pipefail
    body="$(sed -n "/^configure_sillytavern_interactive()/,/^print_final_info()/p" linux-silly-tavern-docker-deploy.sh)"

    auth_line="$(printf "%s\n" "${body}" |
      grep -nF "write_sillytavern_config \"y\" \"\${username}\" \"\${password}\"" |
      cut -d: -f1)"
    compose_line="$(printf "%s\n" "${body}" |
      grep -nF "generate_compose_file \"\${ENABLE_EXTERNAL_ACCESS}\" \"\${ENABLE_WATCHTOWER}\"" |
      cut -d: -f1)"

    [[ -n "${auth_line}" ]]
    [[ -n "${compose_line}" ]]
    (( auth_line < compose_line ))

    ! printf "%s\n" "${body}" | awk -v auth_line="${auth_line}" \
      "NR < auth_line && /generate_compose_file/ { found=1 } END { exit found ? 0 : 1 }"
  '

  assert_status_eq 0
}

@test "linux one-shot replaces config and compose only after temporary files are written" {
  run bash -c '
    set -euo pipefail
    grep -F '\''if ! config_tmp="$("${SUDO[@]}" mktemp "${config_path}.XXXXXX")"; then'\'' linux-silly-tavern-docker-deploy.sh >/dev/null
    grep -F '\''fatal "Failed to create temporary SillyTavern config."'\'' linux-silly-tavern-docker-deploy.sh >/dev/null
    grep -F '\''"${SUDO[@]}" mv "${config_tmp}" "${config_path}"'\'' linux-silly-tavern-docker-deploy.sh >/dev/null
    grep -F '\''if ! compose_tmp="$("${SUDO[@]}" mktemp "${compose_path}.XXXXXX")"; then'\'' linux-silly-tavern-docker-deploy.sh >/dev/null
    grep -F '\''fatal "Failed to create temporary docker-compose.yaml."'\'' linux-silly-tavern-docker-deploy.sh >/dev/null
    grep -F '\''"${SUDO[@]}" mv "${compose_tmp}" "${compose_path}"'\'' linux-silly-tavern-docker-deploy.sh >/dev/null
  '

  assert_status_eq 0
}

@test "linux one-shot cleans temporary files on write or replace failures" {
  run bash -c '
    set -euo pipefail
    config_body="$(sed -n "/^write_sillytavern_config()/,/^generate_compose_file()/p" linux-silly-tavern-docker-deploy.sh)"
    compose_body="$(sed -n "/^generate_compose_file()/,/^configure_sillytavern_interactive()/p" linux-silly-tavern-docker-deploy.sh)"

    [[ "$(printf "%s\n" "${config_body}" | grep -cF '\''"${SUDO[@]}" rm -f "${config_tmp}"'\'')" -ge 3 ]]
    [[ "$(printf "%s\n" "${compose_body}" | grep -cF '\''"${SUDO[@]}" rm -f "${compose_tmp}"'\'')" -ge 4 ]]
    ! grep -F "trap " linux-silly-tavern-docker-deploy.sh | grep -F "RETURN" >/dev/null
  '

  assert_status_eq 0
}

@test "linux one-shot makes compose readable before replacement" {
  run bash -c '
    set -euo pipefail
    body="$(sed -n "/^generate_compose_file()/,/^configure_sillytavern_interactive()/p" linux-silly-tavern-docker-deploy.sh)"

    chmod_line="$(printf "%s\n" "${body}" |
      grep -nF '\''"${SUDO[@]}" chmod 0644 "${compose_tmp}"'\'' |
      cut -d: -f1)"
    mv_line="$(printf "%s\n" "${body}" |
      grep -nF '\''"${SUDO[@]}" mv "${compose_tmp}" "${compose_path}"'\'' |
      cut -d: -f1)"

    [[ -n "${chmod_line}" ]]
    [[ -n "${mv_line}" ]]
    (( chmod_line < mv_line ))
  '

  assert_status_eq 0
}
