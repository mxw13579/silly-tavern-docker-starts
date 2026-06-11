#!/usr/bin/env bash

DOCTOR_REPORT_DEFAULT_LINES=200
DOCTOR_REPORT_MAX_LINES=5000

doctor_report_usage() {
  cat <<'EOF'
Usage: doctor_report_st [options]

Options:
  --help                 Show this help
  --output PATH          Write report to PATH
  --stdout               Print report to stdout and do not create a file
  --no-logs              Skip Docker Compose logs
  --lines N              Log lines to capture, 1-5000
  --since VALUE          Pass a Docker Compose --since value to logs
  --service NAME         Capture logs for one Compose service, default sillytavern
  --all-services         Capture logs for all Compose services
EOF
}

doctor_report_error() {
  printf 'ERROR: %s\n' "$1" >&2
}

doctor_report_validate_lines() {
  local value="$1"

  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    doctor_report_error "invalid lines: ${value}"
    return 2
  fi

  if ((value > DOCTOR_REPORT_MAX_LINES)); then
    doctor_report_error "excessive lines: ${value} > ${DOCTOR_REPORT_MAX_LINES}"
    return 2
  fi
}

doctor_report_escape_sed_pattern() {
  sed -e 's/[][\\.^$*+?{}()|#]/\\&/g' <<<"$1"
}

doctor_report_redact_stream() {
  local app_dir="${DOCTOR_REPORT_APP_DIR:-${APP_DIR:-/data/docker/sillytavern}}"
  local home_value="${HOME:-}"
  local user_value="${USER:-${USERNAME:-}}"
  local app_dir_pattern=""
  local home_pattern=""
  local user_pattern=""
  local sed_args=()

  [[ -z "${app_dir}" ]] || app_dir_pattern="$(doctor_report_escape_sed_pattern "${app_dir}")"
  [[ -z "${home_value}" ]] || home_pattern="$(doctor_report_escape_sed_pattern "${home_value}")"
  [[ -z "${user_value}" ]] || user_pattern="$(doctor_report_escape_sed_pattern "${user_value}")"

  sed_args=(
    -E
    -e 's#((["'\'']?(Authorization|Proxy-Authorization|Cookie|Set-Cookie|X-API-Key)["'\'']?[[:space:]]*[:=][[:space:]]*).*#\1<redacted>#Ig'
    -e 's#((ST_AUTH_(USER|PASS))[[:space:]]*=[[:space:]]*).*#\1<redacted>#Ig'
    -e 's#([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@[:space:]]+@#\1<redacted>@#g' \
    -e 's#([?&][^=[:space:]&]*(token|key|api_key|apikey)[^=[:space:]&]*=)[^&[:space:]]+#\1<redacted>#Ig' \
    -e 's#(^|[[:space:],{])(["'\'']?(username|password|token|secret|api_key|apikey|api-key)["'\'']?[[:space:]]*[:=][[:space:]]*).*#\1\2<redacted>#Ig'
    -e 's#(^|[[:space:]])(HOME|APP_DIR|USER|USERNAME|SUDO_USER)([[:space:]]*=[[:space:]]*).*#\1\2\3<redacted>#Ig' \
    -e 's#[A-Za-z]:[\\/]+Users[\\/]+[^\\/[:space:]]+#<WINDOWS_PROFILE>#g' \
    -e 's#/home/[^/[:space:]]+#<HOME>#g' \
    -e 's#/Users/[^/[:space:]]+#<HOME>#g'
  )

  [[ -z "${app_dir_pattern}" ]] || sed_args+=(-e "s#${app_dir_pattern}#<APP_DIR>#g")
  [[ -z "${home_pattern}" ]] || sed_args+=(-e "s#${home_pattern}#<HOME>#g")
  [[ -z "${user_pattern}" ]] || sed_args+=(-e "s#(^|[[:space:]/\\\\])${user_pattern}($|[[:space:]/\\\\])#\\1<USER>\\2#g")

  sed "${sed_args[@]}"
}

doctor_report_write_raw() {
  if [[ "${DOCTOR_REPORT_TO_STDOUT}" == "1" ]]; then
    cat
  else
    cat >>"${DOCTOR_REPORT_TMP_FILE}"
  fi
}

doctor_report_emit() {
  printf '%s\n' "$*" | doctor_report_redact_stream | doctor_report_write_raw
}

doctor_report_emit_blank() {
  printf '\n' | doctor_report_write_raw
}

doctor_report_command_string() {
  local part
  for part in "$@"; do
    printf '%q ' "${part}"
  done
}

doctor_report_append_evidence() {
  local purpose="$1"
  local exit_code="$2"
  shift 2
  local command_text=""
  command_text="$(doctor_report_command_string "$@")"
  doctor_report_emit "- ${purpose}: exit=${exit_code}; command=${command_text% }"
}

doctor_report_append_block() {
  local content="$1"

  doctor_report_emit '```text'
  if [[ -n "${content}" ]]; then
    printf '%s\n' "${content}" | doctor_report_redact_stream | doctor_report_write_raw
  else
    doctor_report_emit '<no output>'
  fi
  doctor_report_emit '```'
}

doctor_report_run_capture() {
  local title="$1"
  shift
  local output=""
  local exit_code=0

  doctor_report_emit "### ${title}"
  if output="$("$@" 2>&1)"; then
    exit_code=0
  else
    exit_code=$?
  fi
  doctor_report_append_evidence "${title}" "${exit_code}" "$@"
  doctor_report_append_block "${output}"
  doctor_report_emit_blank
  return 0
}

doctor_report_read_file_capture() {
  local path="$1"
  local output=""
  local exit_code=0

  if [[ -r "${path}" ]]; then
    if output="$(cat -- "${path}" 2>&1)"; then
      exit_code=0
    else
      exit_code=$?
    fi
  elif declare -p DOCTOR_REPORT_SUDO >/dev/null 2>&1 && ((${#DOCTOR_REPORT_SUDO[@]} > 0)); then
    if output="$("${DOCTOR_REPORT_SUDO[@]}" cat -- "${path}" 2>&1)"; then
      exit_code=0
    else
      exit_code=$?
    fi
  else
    output="file is not readable"
    exit_code=1
  fi

  printf '%s\n' "${output}"
  return 0
}

doctor_report_detect_compose() {
  DOCTOR_REPORT_COMPOSE_CMD=()

  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi

  if "${DOCTOR_REPORT_SUDO[@]}" docker compose version >/dev/null 2>&1; then
    DOCTOR_REPORT_COMPOSE_CMD=(docker compose)
    return 0
  fi

  local compose_bin=""
  compose_bin="$(command -v docker-compose 2>/dev/null || true)"
  if [[ -n "${compose_bin}" ]]; then
    DOCTOR_REPORT_COMPOSE_CMD=("${compose_bin}")
    return 0
  fi

  return 1
}

doctor_report_file_status() {
  local label="$1"
  local path="$2"

  if [[ -f "${path}" ]]; then
    doctor_report_emit "- PASS ${label}: file exists"
  elif [[ -e "${path}" ]]; then
    doctor_report_emit "- FAIL ${label}: path exists but is not a regular file"
  else
    doctor_report_emit "- FAIL ${label}: missing"
  fi
}

doctor_report_append_file_metadata() {
  local label="$1"
  local path="$2"
  local size="unknown"
  local mode="unknown"
  local hash="unavailable"

  doctor_report_emit "### ${label}"
  if [[ ! -e "${path}" ]]; then
    doctor_report_emit "- Status: FAIL missing"
    doctor_report_emit_blank
    return 0
  fi

  if size="$(wc -c <"${path}" 2>/dev/null)"; then
    size="${size//[[:space:]]/}"
  else
    size="unreadable"
  fi

  if mode="$(stat -c '%a %U:%G' "${path}" 2>/dev/null)"; then
    :
  elif mode="$(stat -f '%Lp %Su:%Sg' "${path}" 2>/dev/null)"; then
    :
  else
    mode="unknown"
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "${path}" 2>/dev/null | awk '{print $1}' || true)"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "${path}" 2>/dev/null | awk '{print $1}' || true)"
  fi
  [[ -n "${hash}" ]] || hash="unavailable"

  doctor_report_emit "- Path: ${path}"
  doctor_report_emit "- Size bytes: ${size}"
  doctor_report_emit "- Mode owner: ${mode}"
  doctor_report_emit "- SHA256: ${hash}"
  doctor_report_emit_blank
}

doctor_report_append_config_signals() {
  local config_output=""

  doctor_report_emit "### Config Signals"
  if [[ ! -f "${DOCTOR_REPORT_CONFIG_FILE}" ]]; then
    doctor_report_emit "- WARN config file missing"
    doctor_report_emit_blank
    return 0
  fi

  config_output="$(doctor_report_read_file_capture "${DOCTOR_REPORT_CONFIG_FILE}")"
  if grep -q 'basicAuthMode:[[:space:]]*true' <<<"${config_output}"; then
    doctor_report_emit "- basicAuthMode: true"
  elif grep -q 'basicAuthMode:[[:space:]]*false' <<<"${config_output}"; then
    doctor_report_emit "- basicAuthMode: false"
  else
    doctor_report_emit "- basicAuthMode: unknown"
  fi

  if grep -q 'enableCorsProxy:[[:space:]]*true' <<<"${config_output}"; then
    doctor_report_emit "- enableCorsProxy: true"
  elif grep -q 'enableCorsProxy:[[:space:]]*false' <<<"${config_output}"; then
    doctor_report_emit "- enableCorsProxy: false"
  else
    doctor_report_emit "- enableCorsProxy: unknown"
  fi
  doctor_report_emit_blank
}

doctor_report_compose_validation() {
  local exit_code=0

  doctor_report_emit "### Compose Validation"
  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} == 0)); then
    doctor_report_emit "- WARN Docker Compose command unavailable; validation skipped"
    doctor_report_append_evidence "Compose validation" "skipped" docker compose config -q
    doctor_report_emit_blank
    return 0
  fi

  if [[ ! -d "${DOCTOR_REPORT_APP_DIR}" ]]; then
    doctor_report_emit "- FAIL APP_DIR missing; validation skipped"
    doctor_report_append_evidence "Compose validation" "skipped" docker compose config -q
    doctor_report_emit_blank
    return 0
  fi

  if [[ ! -f "${DOCTOR_REPORT_COMPOSE_FILE}" ]]; then
    doctor_report_emit "- FAIL Compose file missing; validation skipped"
    doctor_report_append_evidence "Compose validation" "skipped" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" config -q
    doctor_report_emit_blank
    return 0
  fi

  if (cd "${DOCTOR_REPORT_APP_DIR}" && "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" config -q >/dev/null 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  doctor_report_emit "- docker compose config -q exit code: ${exit_code}"
  doctor_report_append_evidence "Compose validation" "${exit_code}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" config -q
  doctor_report_emit_blank
}

doctor_report_append_docker_signals() {
  doctor_report_emit "## Docker Signals"
  if ! command -v docker >/dev/null 2>&1; then
    doctor_report_emit "- WARN docker command not found"
    doctor_report_emit_blank
    return 0
  fi

  doctor_report_run_capture "Docker Version" "${DOCTOR_REPORT_SUDO[@]}" docker --version

  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} > 0)); then
    doctor_report_run_capture "Compose Version" "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" version
  else
    doctor_report_emit "### Compose Version"
    doctor_report_emit "- WARN Docker Compose command not found"
    doctor_report_emit_blank
  fi

  if [[ -d "${DOCTOR_REPORT_APP_DIR}" ]] && ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} > 0)); then
    doctor_report_run_capture "Compose PS" bash -c 'cd "$1" && shift && "$@" ps' _ "${DOCTOR_REPORT_APP_DIR}" "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}"
  fi
}

doctor_report_append_logs() {
  local output=""
  local exit_code=0
  local logs_args=(logs --tail "${DOCTOR_REPORT_LINES}")

  doctor_report_emit "## Logs"
  if [[ "${DOCTOR_REPORT_NO_LOGS}" == "1" ]]; then
    doctor_report_emit "- Logs skipped by --no-logs"
    doctor_report_emit "### Command Evidence"
    doctor_report_append_evidence "Logs capture" "skipped" docker compose logs
    doctor_report_emit_blank
    return 0
  fi

  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} == 0)); then
    doctor_report_emit "- WARN Docker Compose command unavailable; logs skipped"
    doctor_report_emit "### Command Evidence"
    doctor_report_append_evidence "Logs capture" "skipped" docker compose logs
    doctor_report_emit_blank
    return 0
  fi

  if [[ ! -d "${DOCTOR_REPORT_APP_DIR}" ]]; then
    doctor_report_emit "- FAIL APP_DIR missing; logs skipped"
    doctor_report_emit "### Command Evidence"
    doctor_report_append_evidence "Logs capture" "skipped" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" "${logs_args[@]}"
    doctor_report_emit_blank
    return 0
  fi

  [[ -z "${DOCTOR_REPORT_SINCE}" ]] || logs_args+=(--since "${DOCTOR_REPORT_SINCE}")
  if [[ "${DOCTOR_REPORT_ALL_SERVICES}" != "1" ]]; then
    logs_args+=("${DOCTOR_REPORT_SERVICE}")
  fi

  if output="$(cd "${DOCTOR_REPORT_APP_DIR}" && "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" "${logs_args[@]}" 2>&1)"; then
    exit_code=0
  else
    exit_code=$?
  fi

  doctor_report_emit "### Command Evidence"
  doctor_report_append_evidence "Logs capture" "${exit_code}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" "${logs_args[@]}"
  doctor_report_append_block "${output}"
  doctor_report_emit_blank
}

doctor_report_generate() {
  local generated_at=""
  generated_at="$(date '+%Y-%m-%d %H:%M:%S %z')"

  doctor_report_emit "# SillyTavern Doctor Report"
  doctor_report_emit_blank
  doctor_report_emit "- Generated at: ${generated_at}"
  doctor_report_emit "- Report schema: doctor_report_st core"
  doctor_report_emit_blank

  doctor_report_emit "## Summary"
  if [[ -d "${DOCTOR_REPORT_APP_DIR}" ]]; then
    doctor_report_emit "- PASS APP_DIR exists"
  else
    doctor_report_emit "- FAIL APP_DIR missing"
  fi
  doctor_report_file_status "Compose file" "${DOCTOR_REPORT_COMPOSE_FILE}"
  doctor_report_file_status "Config file" "${DOCTOR_REPORT_CONFIG_FILE}"
  if command -v docker >/dev/null 2>&1; then
    doctor_report_emit "- PASS docker command found"
  else
    doctor_report_emit "- WARN docker command missing"
  fi
  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} > 0)); then
    doctor_report_emit "- PASS Docker Compose command found"
  else
    doctor_report_emit "- WARN Docker Compose command missing"
  fi
  doctor_report_emit_blank

  doctor_report_emit "## Runtime Paths"
  doctor_report_emit "- APP_DIR: ${DOCTOR_REPORT_APP_DIR}"
  doctor_report_emit "- Compose file: ${DOCTOR_REPORT_COMPOSE_FILE}"
  doctor_report_emit "- Config file: ${DOCTOR_REPORT_CONFIG_FILE}"
  doctor_report_emit_blank

  doctor_report_emit "## System Signals"
  doctor_report_run_capture "uname" uname -a
  if [[ -f /etc/os-release ]]; then
    doctor_report_run_capture "os-release" awk -F= '/^(PRETTY_NAME|ID|VERSION_ID)=/{print}' /etc/os-release
  else
    doctor_report_emit "### os-release"
    doctor_report_emit "- WARN /etc/os-release missing"
    doctor_report_emit_blank
  fi

  doctor_report_emit "## File Signals"
  doctor_report_append_file_metadata "APP_DIR" "${DOCTOR_REPORT_APP_DIR}"
  doctor_report_append_file_metadata "Compose File" "${DOCTOR_REPORT_COMPOSE_FILE}"
  doctor_report_append_file_metadata "Config File" "${DOCTOR_REPORT_CONFIG_FILE}"
  doctor_report_append_config_signals

  doctor_report_append_docker_signals
  doctor_report_compose_validation
  doctor_report_append_logs
}

doctor_report_prepare_output() {
  local output_dir=""
  local old_umask=""

  if [[ "${DOCTOR_REPORT_TO_STDOUT}" == "1" ]]; then
    DOCTOR_REPORT_TMP_FILE=""
    return 0
  fi

  output_dir="$(dirname -- "${DOCTOR_REPORT_OUTPUT}")"
  if [[ -d "${DOCTOR_REPORT_OUTPUT}" ]]; then
    doctor_report_error "output path is a directory: ${DOCTOR_REPORT_OUTPUT}"
    return 2
  fi
  if [[ ! -d "${output_dir}" ]]; then
    doctor_report_error "output directory does not exist: ${output_dir}"
    return 2
  fi
  if [[ ! -w "${output_dir}" ]]; then
    doctor_report_error "output directory is not writable: ${output_dir}"
    return 2
  fi

  old_umask="$(umask)"
  umask 077
  if ! DOCTOR_REPORT_TMP_FILE="$(mktemp "${output_dir}/.sillytavern_doctor_report.XXXXXX")"; then
    umask "${old_umask}"
    doctor_report_error "failed to create temporary report in ${output_dir}"
    return 2
  fi
  umask "${old_umask}"
  chmod 600 "${DOCTOR_REPORT_TMP_FILE}" 2>/dev/null || true
}

doctor_report_finalize_output() {
  if [[ "${DOCTOR_REPORT_TO_STDOUT}" == "1" ]]; then
    return 0
  fi

  if ! mv -f -- "${DOCTOR_REPORT_TMP_FILE}" "${DOCTOR_REPORT_OUTPUT}"; then
    rm -f -- "${DOCTOR_REPORT_TMP_FILE}" 2>/dev/null || true
    doctor_report_error "failed to finalize report: ${DOCTOR_REPORT_OUTPUT}"
    return 2
  fi
  chmod 600 "${DOCTOR_REPORT_OUTPUT}" 2>/dev/null || true
  printf 'Doctor report written: %s\n' "${DOCTOR_REPORT_OUTPUT}" >&2
}

doctor_report_parse_args() {
  DOCTOR_REPORT_OUTPUT=""
  DOCTOR_REPORT_TO_STDOUT=0
  DOCTOR_REPORT_NO_LOGS=0
  DOCTOR_REPORT_LINES="${DOCTOR_REPORT_DEFAULT_LINES}"
  DOCTOR_REPORT_SINCE=""
  DOCTOR_REPORT_SERVICE="sillytavern"
  DOCTOR_REPORT_SERVICE_SET=0
  DOCTOR_REPORT_ALL_SERVICES=0

  while (($# > 0)); do
    case "$1" in
      --help)
        doctor_report_usage
        return 100
        ;;
      --output)
        if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
          doctor_report_error "missing value for --output"
          return 2
        fi
        DOCTOR_REPORT_OUTPUT="$2"
        shift 2
        ;;
      --stdout)
        DOCTOR_REPORT_TO_STDOUT=1
        shift
        ;;
      --no-logs)
        DOCTOR_REPORT_NO_LOGS=1
        shift
        ;;
      --lines)
        if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
          doctor_report_error "missing value for --lines"
          return 2
        fi
        doctor_report_validate_lines "$2" || return 2
        DOCTOR_REPORT_LINES="$2"
        shift 2
        ;;
      --since)
        if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
          doctor_report_error "missing value for --since"
          return 2
        fi
        DOCTOR_REPORT_SINCE="$2"
        shift 2
        ;;
      --service)
        if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
          doctor_report_error "missing value for --service"
          return 2
        fi
        if [[ "${DOCTOR_REPORT_ALL_SERVICES}" == "1" ]]; then
          doctor_report_error "service/all-services conflict"
          return 2
        fi
        DOCTOR_REPORT_SERVICE="$2"
        DOCTOR_REPORT_SERVICE_SET=1
        shift 2
        ;;
      --all-services)
        if [[ "${DOCTOR_REPORT_SERVICE_SET}" == "1" ]]; then
          doctor_report_error "service/all-services conflict"
          return 2
        fi
        DOCTOR_REPORT_ALL_SERVICES=1
        shift
        ;;
      *)
        doctor_report_error "unknown option: $1"
        return 2
        ;;
    esac
  done

  if [[ "${DOCTOR_REPORT_TO_STDOUT}" == "1" && -n "${DOCTOR_REPORT_OUTPUT}" ]]; then
    doctor_report_error "output/stdout conflict"
    return 2
  fi

  if [[ "${DOCTOR_REPORT_TO_STDOUT}" != "1" && -z "${DOCTOR_REPORT_OUTPUT}" ]]; then
    if [[ -z "${HOME:-}" ]]; then
      doctor_report_error "HOME is not set; use --output PATH or --stdout"
      return 2
    fi
    DOCTOR_REPORT_OUTPUT="${HOME}/sillytavern_doctor_report_$(date +%Y%m%d_%H%M%S).md"
  fi
}

doctor_report_st() {
  local parse_status=0
  local restore_errexit=0

  case "$-" in
    *e*) restore_errexit=1 ;;
  esac
  set +e

  doctor_report_parse_args "$@"
  parse_status=$?
  if [[ "${parse_status}" == "100" ]]; then
    ((restore_errexit == 0)) || set -e
    return 0
  fi
  if [[ "${parse_status}" != "0" ]]; then
    ((restore_errexit == 0)) || set -e
    return "${parse_status}"
  fi

  DOCTOR_REPORT_APP_DIR="${APP_DIR:-/data/docker/sillytavern}"
  DOCTOR_REPORT_COMPOSE_FILE="${ST_COMPOSE_FILE:-${DOCTOR_REPORT_APP_DIR}/docker-compose.yaml}"
  DOCTOR_REPORT_CONFIG_FILE="${ST_CONFIG_FILE:-${DOCTOR_REPORT_APP_DIR}/config/config.yaml}"
  DOCTOR_REPORT_SUDO=()
  # shellcheck disable=SC2154
  if declare -p SUDO >/dev/null 2>&1; then
    DOCTOR_REPORT_SUDO=("${SUDO[@]}")
  fi

  doctor_report_detect_compose
  doctor_report_prepare_output || {
    ((restore_errexit == 0)) || set -e
    return 2
  }
  doctor_report_generate
  doctor_report_finalize_output
  parse_status=$?
  ((restore_errexit == 0)) || set -e
  return "${parse_status}"
}
