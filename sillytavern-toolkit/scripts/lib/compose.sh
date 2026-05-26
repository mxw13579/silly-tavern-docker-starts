#!/usr/bin/env bash

detect_compose_cmd() {
  COMPOSE_CMD=()

  if "${SUDO[@]}" docker compose version &>/dev/null; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi

  local compose_bin=""
  compose_bin="$(command -v docker-compose 2>/dev/null || true)"
  if [[ -n "${compose_bin}" ]]; then
    COMPOSE_CMD=("${compose_bin}")
    return 0
  fi

  return 1
}

compose_quiet() {
  local title="$1"
  shift
  run_quiet "${title}" "${SUDO[@]}" "${COMPOSE_CMD[@]}" "$@"
}
