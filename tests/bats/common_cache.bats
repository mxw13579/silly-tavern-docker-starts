#!/usr/bin/env bats

load "../helpers/stubs.bash"

@test "common.sh cache key is path-safe (no slashes) and deterministic" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source "sillytavern-toolkit/scripts/common.sh"
    export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/xdgcache"
    k1="$(st_cache_key "../../etc/passwd")"
    k2="$(st_cache_key "../../etc/passwd")"
    [[ -n "${k1}" ]]
    [[ "${k1}" == "${k2}" ]]
    [[ "${k1}" != *"/"* ]]
    [[ "${k1}" != *".."* ]]
  '
  assert_status_eq 0
}

@test "common.sh test mode exposes safe default arrays and mirror flag" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source "sillytavern-toolkit/scripts/common.sh"
    declare -p SUDO | grep -F "declare -a" >/dev/null
    declare -p COMPOSE_CMD | grep -F "declare -a" >/dev/null
    [[ "${USE_CHINA_MIRROR}" == "false" ]]
    [[ ${#SUDO[@]} -eq 0 ]]
    [[ ${#COMPOSE_CMD[@]} -eq 0 ]]
  '
  assert_status_eq 0
}

@test "common.sh cache dir defaults to HOME/.cache when XDG_CACHE_HOME is unset" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source "sillytavern-toolkit/scripts/common.sh"
    unset XDG_CACHE_HOME
    export HOME="${BATS_TEST_TMPDIR}/home"
    [[ "$(st_cache_dir)" == "${HOME}/.cache/sillytavern-toolkit" ]]
  '
  assert_status_eq 0
}

@test "common.sh cache TTL fresh/expired behavior" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source "sillytavern-toolkit/scripts/common.sh"
    export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/xdgcache"
    key="$(st_cache_key "ttl-test")"
    printf "hello" | st_cache_write "${key}"
    st_cache_is_fresh 60 "${key}"
    [[ "$(st_cache_read 60 "${key}")" == "hello" ]]
    # Force expire: timestamp far in the past
    dir="$(st_cache_dir)"
    printf "1" >"${dir}/${key}.ts"
    ! st_cache_is_fresh 1 "${key}"
    ! st_cache_read 1 "${key}"
  '
  assert_status_eq 0
}

@test "common.sh cache future timestamp is treated as not fresh" {
  run bash -c '
    set -euo pipefail
    export ST_TOOLKIT_TEST_MODE=1
    export ST_TOOLKIT_REQUIRE_SUDO=0
    export ST_TOOLKIT_SKIP_COUNTRY=1
    set --
    source "sillytavern-toolkit/scripts/common.sh"
    export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/xdgcache"
    key="$(st_cache_key "future-ts")"
    printf "hello" | st_cache_write "${key}"
    dir="$(st_cache_dir)"
    now="$(date +%s)"
    printf "%s" "$((now + 3600))" >"${dir}/${key}.ts"
    ! st_cache_is_fresh 60 "${key}"
  '
  assert_status_eq 0
}
