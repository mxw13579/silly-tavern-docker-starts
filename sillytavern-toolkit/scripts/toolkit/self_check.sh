#!/usr/bin/env bash
set -euo pipefail

SELF_CHECK_STRICT=0
SELF_CHECK_QUIET=0
SELF_CHECK_PASS_COUNT=0
SELF_CHECK_WARN_COUNT=0
SELF_CHECK_FAIL_COUNT=0

self_check_usage() {
  cat <<'EOF'
Usage: self_check.sh [--strict] [--quiet]

Options:
  --strict   Treat WARN checks as a non-zero result.
  --quiet    Suppress PASS detail while keeping WARN, FAIL, and summary output.
  --help     Show this help.
EOF
}

while (($# > 0)); do
  case "$1" in
    --strict)
      SELF_CHECK_STRICT=1
      shift
      ;;
    --quiet)
      SELF_CHECK_QUIET=1
      shift
      ;;
    --help|-h)
      self_check_usage
      exit 0
      ;;
    *)
      self_check_usage >&2
      exit 2
      ;;
  esac
done

__self_check_source="${BASH_SOURCE[0]}"
__self_check_script_dir="$(cd -- "${__self_check_source%/*}" && pwd)"
__self_check_scripts_dir="$(cd -- "${__self_check_script_dir}/.." && pwd)"
TOOLKIT_ROOT="${ST_TOOLKIT_SELF_CHECK_ROOT:-$(cd -- "${__self_check_scripts_dir}/.." && pwd)}"

export ST_TOOLKIT_REQUIRE_SUDO=0
export ST_TOOLKIT_SKIP_COUNTRY=1
export ST_TOOLKIT_TEST_MODE="${ST_TOOLKIT_TEST_MODE:-1}"

APP_DIR="${APP_DIR:-/data/docker/sillytavern}"
ST_COMPOSE_FILE="${ST_COMPOSE_FILE:-${APP_DIR}/docker-compose.yaml}"
ST_CONFIG_FILE="${ST_CONFIG_FILE:-${APP_DIR}/config/config.yaml}"
declare -ag SUDO=()
declare -ag COMPOSE_CMD=()

if [[ -r "${__self_check_scripts_dir}/lib/compose.sh" ]]; then
  # shellcheck source=sillytavern-toolkit/scripts/lib/compose.sh
  # shellcheck disable=SC1091
  . "${__self_check_scripts_dir}/lib/compose.sh"
else
  detect_compose_cmd() {
    COMPOSE_CMD=()
    if docker compose version >/dev/null 2>&1; then
      COMPOSE_CMD=(docker compose)
      return 0
    fi
    if command -v docker-compose >/dev/null 2>&1; then
      COMPOSE_CMD=("$(command -v docker-compose)")
      return 0
    fi
    return 1
  }
fi

self_check_print() {
  printf '%s\n' "$*"
}

record_check() {
  local level="$1"
  local name="$2"
  local problem="${3:-}"
  local impact="${4:-}"
  local fix="${5:-}"

  case "${level}" in
    PASS)
      SELF_CHECK_PASS_COUNT=$((SELF_CHECK_PASS_COUNT + 1))
      if [[ "${SELF_CHECK_QUIET}" != "1" ]]; then
        self_check_print "PASS ${name}"
      fi
      ;;
    WARN)
      SELF_CHECK_WARN_COUNT=$((SELF_CHECK_WARN_COUNT + 1))
      self_check_print "WARN ${name}"
      self_check_print "problem: ${problem}"
      self_check_print "impact: ${impact}"
      self_check_print "fix: ${fix}"
      ;;
    FAIL)
      SELF_CHECK_FAIL_COUNT=$((SELF_CHECK_FAIL_COUNT + 1))
      self_check_print "FAIL ${name}"
      self_check_print "problem: ${problem}"
      self_check_print "impact: ${impact}"
      self_check_print "fix: ${fix}"
      ;;
  esac
}

check_required_file() {
  local rel_path="$1"
  local path="${TOOLKIT_ROOT}/${rel_path}"

  if [[ ! -e "${path}" ]]; then
    record_check FAIL "required file exists: ${rel_path}" \
      "required toolkit file is missing: ${rel_path}" \
      "toolkit commands that source or execute this file can fail before showing a useful error" \
      "restore the missing file from a complete toolkit copy"
  elif [[ ! -r "${path}" ]]; then
    record_check FAIL "required file readable: ${rel_path}" \
      "required toolkit file is not readable: ${rel_path}" \
      "self-check and dependent commands cannot inspect the file" \
      "fix file ownership or permissions so the current user can read it"
  else
    record_check PASS "required file readable: ${rel_path}"
  fi
}

check_entrypoint_permission() {
  local rel_path="$1"
  local path="${TOOLKIT_ROOT}/${rel_path}"

  [[ -e "${path}" ]] || return 0
  if [[ -x "${path}" ]]; then
    record_check PASS "entrypoint executable: ${rel_path}"
  else
    record_check WARN "entrypoint executable bit: ${rel_path}" \
      "entrypoint is readable but not executable: ${rel_path}" \
      "direct ./ entrypoint execution can fail on Unix-like filesystems" \
      "run chmod +x on the entrypoint or invoke it through bash"
  fi
}

check_command_required() {
  local cmd="$1"

  if command -v "${cmd}" >/dev/null 2>&1; then
    record_check PASS "required command available: ${cmd}"
  else
    record_check FAIL "required command available: ${cmd}" \
      "required command is not available on PATH: ${cmd}" \
      "this Bash toolkit relies on the command for local diagnostics or script execution" \
      "install the command or run from an environment where it is on PATH"
  fi
}

check_command_optional() {
  local label="$1"
  shift
  local cmd

  for cmd in "$@"; do
    if command -v "${cmd}" >/dev/null 2>&1; then
      record_check PASS "optional command available: ${cmd}"
      return 0
    fi
  done

  record_check WARN "optional command available: ${label}" \
    "optional command group is not available: ${label}" \
    "some diagnostics or follow-up maintenance hints may be less detailed" \
    "install one of: $*"
}

check_bash_syntax() {
  local rel_path="$1"
  local path="${TOOLKIT_ROOT}/${rel_path}"

  [[ -r "${path}" ]] || return 0
  if ! command -v bash >/dev/null 2>&1; then
    return 0
  fi

  if bash -n "${path}" >/dev/null 2>&1; then
    record_check PASS "bash syntax: ${rel_path}"
  else
    record_check FAIL "bash syntax: ${rel_path}" \
      "bash -n reported a syntax error in ${rel_path}" \
      "the script can fail before running its checks or commands" \
      "run bash -n ${rel_path} and fix the syntax error"
  fi
}

check_docker_discovery() {
  if command -v docker >/dev/null 2>&1; then
    record_check PASS "Docker CLI available: $(command -v docker)"
    if docker info >/dev/null 2>&1; then
      record_check PASS "Docker daemon accessible"
    else
      record_check WARN "Docker daemon accessible" \
        "docker CLI exists but docker info is not accessible" \
        "runtime health checks may fail even though toolkit files are valid" \
        "start Docker or fix current-user Docker permissions, then run health diagnostics"
    fi
  else
    record_check WARN "Docker CLI available" \
      "Docker CLI is not available on PATH" \
      "toolkit integrity can still be checked, but Docker operations will not run" \
      "install Docker before using container lifecycle commands"
  fi

  SUDO=()
  if detect_compose_cmd; then
    record_check PASS "Compose available: ${COMPOSE_CMD[*]}"
  else
    record_check WARN "Compose available" \
      "neither docker compose nor docker-compose was detected" \
      "Compose lifecycle and validation commands cannot run without a Compose facade" \
      "install Docker Compose or ensure docker compose is available on PATH"
  fi
}

check_path_readability() {
  local title="$1"
  local path="$2"

  if [[ -e "${path}" && -r "${path}" ]]; then
    record_check PASS "${title} readable: ${path}"
  elif [[ -e "${path}" ]]; then
    record_check FAIL "${title} readable: ${path}" \
      "${title} exists but is not readable: ${path}" \
      "diagnostics cannot inspect the existing path" \
      "fix ownership or permissions for the current user"
  else
    record_check WARN "${title} exists: ${path}" \
      "${title} is missing: ${path}" \
      "a fresh toolkit install can be valid before SillyTavern is deployed, but runtime commands may fail" \
      "run installation/configuration before lifecycle or health commands"
  fi
}

show_version_hint() {
  local branch=""
  local commit=""

  if command -v git >/dev/null 2>&1 && git -C "${TOOLKIT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    commit="$(git -C "${TOOLKIT_ROOT}" rev-parse --short HEAD 2>/dev/null || true)"
    branch="$(git -C "${TOOLKIT_ROOT}" branch --show-current 2>/dev/null || true)"
    record_check PASS "version hint: git ${branch:-detached} ${commit:-unknown}"
    return 0
  fi

  if [[ -e "${TOOLKIT_ROOT}/st-toolkit.sh" ]]; then
    record_check PASS "version hint: local file ${TOOLKIT_ROOT}/st-toolkit.sh"
  else
    record_check WARN "version hint available" \
      "no local git metadata or entrypoint mtime could be inspected" \
      "support reports may have less precise toolkit version context" \
      "run self-check from a complete toolkit directory"
  fi
}

main() {
  local required_file
  local syntax_file

  for required_file in \
    st-toolkit.sh install.sh scripts/common.sh scripts/health.sh \
    scripts/sillytavern.sh scripts/docker.sh scripts/sources.sh \
    scripts/toolkit/self_check.sh \
    scripts/lib/compose.sh scripts/lib/logging.sh scripts/lib/input.sh \
    scripts/lib/network.sh scripts/lib/os.sh scripts/lib/apt.sh \
    scripts/lib/packages.sh scripts/sillytavern/compose.sh \
    scripts/sillytavern/validation.sh scripts/sillytavern/config.sh \
    scripts/sillytavern/access.sh scripts/sillytavern/lifecycle.sh \
    scripts/sillytavern/logs.sh scripts/sillytavern/status.sh scripts/docker/install.sh \
    scripts/docker/mirror.sh scripts/docker/compose.sh scripts/docker/status.sh \
    scripts/sources/precheck.sh scripts/sources/backup.sh \
    scripts/sources/providers.sh scripts/sources/status.sh
  do
    check_required_file "${required_file}"
  done

  check_entrypoint_permission st-toolkit.sh
  check_entrypoint_permission install.sh
  check_entrypoint_permission scripts/sillytavern.sh

  for syntax_file in \
    scripts/toolkit/self_check.sh scripts/common.sh scripts/health.sh \
    scripts/sillytavern.sh scripts/docker.sh scripts/sources.sh \
    scripts/sillytavern/logs.sh
  do
    check_bash_syntax "${syntax_file}"
  done

  for required_cmd in bash find sed grep awk chmod mkdir cp rm; do
    check_command_required "${required_cmd}"
  done

  check_command_optional curl curl
  check_command_optional wget wget
  check_command_optional git git
  check_command_optional "sha256sum or shasum" sha256sum shasum
  check_command_optional "ss or netstat" ss netstat
  check_command_optional shellcheck shellcheck

  check_docker_discovery
  check_path_readability "toolkit root" "${TOOLKIT_ROOT}"
  check_path_readability "APP_DIR" "${APP_DIR}"
  check_path_readability "ST_COMPOSE_FILE" "${ST_COMPOSE_FILE}"
  check_path_readability "ST_CONFIG_FILE" "${ST_CONFIG_FILE}"
  show_version_hint

  self_check_print "summary: PASS=${SELF_CHECK_PASS_COUNT} WARN=${SELF_CHECK_WARN_COUNT} FAIL=${SELF_CHECK_FAIL_COUNT}"

  if ((SELF_CHECK_FAIL_COUNT > 0)); then
    return 1
  fi
  if [[ "${SELF_CHECK_STRICT}" == "1" && "${SELF_CHECK_WARN_COUNT}" -gt 0 ]]; then
    return 1
  fi
  return 0
}

main "$@"
