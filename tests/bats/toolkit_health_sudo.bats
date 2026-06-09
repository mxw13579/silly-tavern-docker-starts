#!/usr/bin/env bats

load "../helpers/stubs.bash"

@test "health.sh routes compose daemon calls through sudo-aware helpers" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/scripts/health.sh"

    grep -F "health_compose()" "${f}" >/dev/null
    grep -F "health_compose_in_app()" "${f}" >/dev/null
    grep -F "ST_TOOLKIT_TEST_SUDO" "${f}" >/dev/null
    grep -F "\"\${SUDO[@]}\" \"\${COMPOSE_CMD[@]}\" \"\$@\"" "${f}" >/dev/null
    grep -F "health_compose version" "${f}" >/dev/null
    grep -F "health_compose_in_app ps -q sillytavern" "${f}" >/dev/null
    grep -F "health_compose_in_app ps" "${f}" >/dev/null
    grep -F "health_compose_in_app logs --tail 50 sillytavern" "${f}" >/dev/null

    ! grep -nF "\"\${COMPOSE_CMD[@]}\" version" "${f}" >/dev/null
    ! grep -nF "\"\${COMPOSE_CMD[@]}\" ps" "${f}" >/dev/null
    ! grep -nF "\"\${COMPOSE_CMD[@]}\" logs" "${f}" >/dev/null
  '

  assert_status_eq 0
}
