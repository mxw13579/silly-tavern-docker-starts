#!/usr/bin/env bash

# Logging helpers.
# Note: These defaults are only used if the caller didn't define color constants.
[[ -v C_RESET ]] || C_RESET=$'\033[0m'
[[ -v C_RED ]] || C_RED=$'\033[0;31m'
[[ -v C_GREEN ]] || C_GREEN=$'\033[0;32m'
[[ -v C_YELLOW ]] || C_YELLOW=$'\033[0;33m'
[[ -v C_BLUE ]] || C_BLUE=$'\033[0;34m'
[[ -v C_CYAN ]] || C_CYAN=$'\033[0;36m'

log() { printf '%s\n' "$*"; }
msg_info() { printf '%b[INFO]%b %s\n' "${C_BLUE}" "${C_RESET}" "$*"; }
msg_ok() { printf '%b[OK]%b %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
msg_warn() { printf '%b[WARN]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
msg_error() { printf '%b[ERROR]%b %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
fatal() { msg_error "$*"; exit 1; }
pause_to_continue() { read -r -p "按 [Enter] 键返回..." </dev/tty || true; }

run_quiet() {
  local title="$1"
  shift

  local old_trap_int old_trap_term
  old_trap_int="$(trap -p | grep -E " SIGINT$| INT$" || true)"
  old_trap_term="$(trap -p | grep -E " SIGTERM$| TERM$" || true)"

  local logfile pid frames i
  logfile="$(mktemp "/tmp/st-toolkit-log.XXXXXX")"
  frames='|/-\'
  i=0
  pid=""

  printf '%s ' "${title}"
  "$@" >"${logfile}" 2>&1 &
  pid=$!

  cleanup_quiet() {
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
    fi
    printf '\n'
    log "已中断，日志文件: ${logfile}"
    exit 130
  }

  trap cleanup_quiet INT TERM

  while kill -0 "${pid}" 2>/dev/null; do
    printf '\r%s %s' "${title}" "${frames:i++%4:1}"
    sleep 0.15
  done

  # Restore caller traps for INT/TERM to avoid clobbering library users.
  if [[ -n "${old_trap_int}" ]]; then
    eval "${old_trap_int}"
  else
    trap - INT
  fi

  if [[ -n "${old_trap_term}" ]]; then
    eval "${old_trap_term}"
  else
    trap - TERM
  fi

  if wait "${pid}"; then
    printf '\r%s ✅\n' "${title}"
    rm -f "${logfile}"
    return 0
  fi

  printf '\r%s ❌\n' "${title}"
  log "命令执行失败，日志文件: ${logfile}"
  log "最近日志:"
  tail -n 80 "${logfile}" || true
  return 1
}
