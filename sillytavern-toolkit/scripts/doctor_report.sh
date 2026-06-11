#!/usr/bin/env bash

DOCTOR_REPORT_DEFAULT_LINES=200
DOCTOR_REPORT_MAX_LINES=5000
DOCTOR_REPORT_COUNTS_PLACEHOLDER="DOCTOR_REPORT_STATUS_COUNTS_PENDING"
DOCTOR_REPORT_REQUIRED_SECTIONS=(
  "## Summary"
  "## Environment"
  "## Toolkit Self-check"
  "## Docker Compose"
  "## SillyTavern Status"
  "## Access Config"
  "## Mirror Config"
  "## Compose Validation"
  "## Command Evidence"
  "## Recent Logs"
  "## Recommendations"
)

doctor_report_usage() {
  cat <<'EOF'
Usage: sillytavern.sh doctor-report [options]
Alias: sillytavern.sh doctor [options]

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
  local value="$1"
  local escaped=""
  local char=""
  local index=0

  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    case "${char}" in
      '['|']'|\\|'.'|'^'|'$'|'*'|'+'|'?'|'{'|'}'|'('|')'|'|'|'#')
        escaped+="\\${char}"
        ;;
      *)
        escaped+="${char}"
        ;;
    esac
  done

  printf '%s' "${escaped}"
}

doctor_redact_stream() {
  local default_app_dir="/data/docker/sillytavern"
  local app_dir="${DOCTOR_REPORT_APP_DIR:-${APP_DIR:-${default_app_dir}}}"
  local home_value="${HOME:-}"
  local user_value="${USER:-${USERNAME:-}}"
  local app_dir_pattern=""
  local home_pattern=""
  local user_pattern=""
  local sed_args=()

  if [[ -n "${app_dir}" && "${app_dir}" != "${default_app_dir}" ]]; then
    app_dir_pattern="$(doctor_report_escape_sed_pattern "${app_dir}")"
  fi
  [[ -z "${home_value}" ]] || home_pattern="$(doctor_report_escape_sed_pattern "${home_value}")"
  [[ -z "${user_value}" ]] || user_pattern="$(doctor_report_escape_sed_pattern "${user_value}")"

  sed_args=(
    -E
    -e 's#(["'\'']?(Authorization|Proxy-Authorization|Cookie|Set-Cookie|X-API-Key)["'\'']?[[:space:]]*[:=][[:space:]]*).*#\1[REDACTED]#Ig'
    -e 's#((ST_AUTH_(USER|PASS))[[:space:]]*=[[:space:]]*).*#\1[REDACTED]#Ig'
    -e 's#([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@[:space:]]+@#\1[REDACTED]@#g'
    -e 's#([?&][^=[:space:]&]*(token|key|api_key|apikey)[^=[:space:]&]*=)[^&[:space:]]+#\1[REDACTED]#Ig'
    -e 's#(^|[[:space:],{])(["'\'']?basicAuthUser[.]?(username|password)["'\'']?[[:space:]]*[:=][[:space:]]*).*#\1\2[REDACTED]#Ig'
    -e 's#(^|[[:space:],{])(["'\'']?(username|password|token|secret|api_key|apikey|api-key)["'\'']?[[:space:]]*[:=][[:space:]]*).*#\1\2[REDACTED]#Ig'
    -e 's#(^|[[:space:],{])(["'\'']?[[:alnum:]_.-]*(token|secret|api[_-]?key|apikey)[[:alnum:]_.-]*["'\'']?[[:space:]]*[:=][[:space:]]*).*#\1\2[REDACTED]#Ig'
    -e 's#(^|[[:space:]])(HOME|APP_DIR|USER|USERNAME|SUDO_USER)([[:space:]]*=[[:space:]]*).*#\1\2\3[REDACTED]#Ig'
    -e 's#[A-Za-z]:[\\/]+Users[\\/]+[^\\/]+#<WINDOWS_PROFILE>#g'
    -e 's#/home/[^/[:space:]]+#<HOME>#g'
    -e 's#/Users/[^/[:space:]]+#<HOME>#g'
  )

  [[ -z "${app_dir_pattern}" ]] || sed_args+=(-e "s#${app_dir_pattern}#<APP_DIR>#g")
  [[ -z "${home_pattern}" ]] || sed_args+=(-e "s#${home_pattern}#<HOME>#g")
  [[ -z "${user_pattern}" ]] || sed_args+=(-e "s#(^|[[:space:]/\\\\])${user_pattern}($|[[:space:]/\\\\])#\\1<USER>\\2#g")

  sed "${sed_args[@]}"
}

doctor_report_redact_stream() {
  doctor_redact_stream "$@"
}

doctor_report_write_raw() {
  if [[ -n "${DOCTOR_REPORT_TMP_FILE:-}" ]]; then
    cat >>"${DOCTOR_REPORT_TMP_FILE}"
  elif [[ "${DOCTOR_REPORT_TO_STDOUT}" == "1" ]]; then
    cat
  else
    return 1
  fi
}

doctor_report_reset_counts() {
  DOCTOR_REPORT_PASS_COUNT=0
  DOCTOR_REPORT_WARN_COUNT=0
  DOCTOR_REPORT_FAIL_COUNT=0
}

doctor_report_cleanup_tmp() {
  if [[ -n "${DOCTOR_REPORT_TMP_FILE:-}" ]]; then
    rm -f -- "${DOCTOR_REPORT_TMP_FILE}" "${DOCTOR_REPORT_TMP_FILE}.final" 2>/dev/null || true
    DOCTOR_REPORT_TMP_FILE=""
  fi
}

doctor_report_increment_count() {
  case "$1" in
    PASS) DOCTOR_REPORT_PASS_COUNT=$((DOCTOR_REPORT_PASS_COUNT + 1)) ;;
    WARN) DOCTOR_REPORT_WARN_COUNT=$((DOCTOR_REPORT_WARN_COUNT + 1)) ;;
    FAIL) DOCTOR_REPORT_FAIL_COUNT=$((DOCTOR_REPORT_FAIL_COUNT + 1)) ;;
  esac
}

doctor_report_emit() {
  printf '%s\n' "$*" | doctor_redact_stream | doctor_report_write_raw
}

doctor_report_emit_blank() {
  printf '\n' | doctor_report_write_raw
}

doctor_report_emit_status() {
  local status="$1"
  local label="$2"
  local detail="$3"

  doctor_report_increment_count "${status}"
  doctor_report_emit "- ${status} ${label}: ${detail}"
}

doctor_report_command_string() {
  local part

  for part in "$@"; do
    printf '%q ' "${part}"
  done
}

doctor_report_add_evidence() {
  local purpose="$1"
  local exit_code="$2"
  local stdout_status="$3"
  local stderr_status="$4"
  local truncation_status="$5"
  local redaction_status="$6"
  local command_text=""
  shift 6

  command_text="$(doctor_report_command_string "$@")"
  DOCTOR_REPORT_EVIDENCE+=("- ${purpose}: attempted command=${command_text% }; exit code=${exit_code}; stdout captured=${stdout_status}; stderr captured=${stderr_status}; truncation=${truncation_status}; redaction=${redaction_status}")
}

doctor_report_add_skipped_evidence() {
  local purpose="$1"
  local reason="$2"
  shift 2

  doctor_report_add_evidence "${purpose}" "skipped (${reason})" "not_captured" "not_captured" "not_applicable" "applied" "$@"
}

doctor_report_add_file_read_evidence() {
  local purpose="$1"
  local read_status="$2"
  local exit_code="$3"
  local stdout_status="$4"
  local stderr_status="$5"
  local truncation_status="$6"
  local redaction_status="$7"
  local command_text=""
  shift 7

  command_text="$(doctor_report_command_string "$@")"
  DOCTOR_REPORT_EVIDENCE+=("- ${purpose}: attempted command=${command_text% }; read status=${read_status}; exit code=${exit_code}; stdout captured=${stdout_status}; stderr captured=${stderr_status}; truncation=${truncation_status}; redaction=${redaction_status}")
}

doctor_report_add_skipped_file_read_evidence() {
  local purpose="$1"
  local read_status="$2"
  local reason="$3"
  shift 3

  doctor_report_add_file_read_evidence "${purpose}" "${read_status}" "skipped (${reason})" "not_captured" "not_captured" "not_applicable" "applied" "$@"
}

doctor_report_capture_status() {
  local content="$1"

  if [[ -n "${content}" ]]; then
    printf 'captured'
  else
    printf 'empty'
  fi
}

doctor_report_capture_temp_file() {
  local output_var="$1"
  local stream_name="$2"
  local tmp_dir=""
  local tmp_file=""
  local mktemp_status=0

  tmp_dir="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
  if [[ -z "${tmp_dir}" || ! -d "${tmp_dir}" || ! -w "${tmp_dir}" ]]; then
    tmp_dir="/tmp"
  fi
  if [[ ! -d "${tmp_dir}" || ! -w "${tmp_dir}" ]]; then
    printf -v "${output_var}" '%s' ''
    return 1
  fi

  tmp_file="$(mktemp "${tmp_dir}/st-doctor-${stream_name}.XXXXXX" 2>/dev/null)"
  mktemp_status=$?
  if ((mktemp_status != 0)) || [[ -z "${tmp_file}" ]]; then
    printf -v "${output_var}" '%s' ''
    return 1
  fi

  printf -v "${output_var}" '%s' "${tmp_file}"
  return 0
}

doctor_report_capture_combined_command() {
  local purpose="$1"
  local output_var="$2"
  local output=""
  local exit_code=0
  shift 2

  if output="$("$@" 2>&1)"; then
    exit_code=0
  else
    exit_code=$?
  fi
  DOCTOR_REPORT_LAST_EXIT_CODE="${exit_code}"
  printf -v "${output_var}" '%s' "${output}"
  doctor_report_add_evidence "${purpose}" "${exit_code}" "captured_combined" "captured_combined" "not_truncated" "applied" "$@"
}

doctor_report_append_block() {
  local content="$1"

  doctor_report_emit '```text'
  if [[ -n "${content}" ]]; then
    printf '%s\n' "${content}" | doctor_redact_stream | doctor_report_write_raw
  else
    doctor_report_emit '<no output>'
  fi
  doctor_report_emit '```'
}

doctor_report_capture_command() {
  local purpose="$1"
  local output_var="$2"
  local output=""
  local stdout_output=""
  local stderr_output=""
  local stdout_file=""
  local stderr_file=""
  local exit_code=0
  shift 2

  if (($# == 0)) || [[ -z "${1:-}" ]]; then
    printf -v "${output_var}" '%s' ''
    DOCTOR_REPORT_LAST_EXIT_CODE="skipped"
    doctor_report_add_skipped_evidence "${purpose}" "empty command"
    return 0
  fi

  if ! doctor_report_capture_temp_file stdout_file "stdout"; then
    doctor_report_capture_combined_command "${purpose}" "${output_var}" "$@"
    return 0
  fi
  if ! doctor_report_capture_temp_file stderr_file "stderr"; then
    rm -f -- "${stdout_file}" 2>/dev/null || true
    doctor_report_capture_combined_command "${purpose}" "${output_var}" "$@"
    return 0
  fi

  if "$@" >"${stdout_file}" 2>"${stderr_file}"; then
    exit_code=0
  else
    exit_code=$?
  fi
  DOCTOR_REPORT_LAST_EXIT_CODE="${exit_code}"
  stdout_output="$(cat -- "${stdout_file}" 2>/dev/null || true)"
  stderr_output="$(cat -- "${stderr_file}" 2>/dev/null || true)"
  rm -f -- "${stdout_file}" "${stderr_file}" 2>/dev/null || true

  output="${stdout_output}"
  if [[ -n "${stderr_output}" ]]; then
    [[ -z "${output}" ]] || output+=$'\n'
    output+="${stderr_output}"
  fi

  printf -v "${output_var}" '%s' "${output}"
  doctor_report_add_evidence "${purpose}" "${exit_code}" "$(doctor_report_capture_status "${stdout_output}")" "$(doctor_report_capture_status "${stderr_output}")" "not_truncated" "applied" "$@"
  return 0
}

doctor_report_capture_command_in_dir() {
  local purpose="$1"
  local output_var="$2"
  local work_dir="$3"
  local output=""
  local stdout_output=""
  local stderr_output=""
  local stdout_file=""
  local stderr_file=""
  local exit_code=0
  shift 3

  if (($# == 0)) || [[ -z "${1:-}" ]]; then
    printf -v "${output_var}" '%s' ''
    DOCTOR_REPORT_LAST_EXIT_CODE="skipped"
    doctor_report_add_skipped_evidence "${purpose}" "empty command"
    return 0
  fi

  if [[ ! -d "${work_dir}" ]]; then
    printf -v "${output_var}" '%s' ''
    DOCTOR_REPORT_LAST_EXIT_CODE="skipped"
    doctor_report_add_skipped_evidence "${purpose}" "working directory missing" "$@"
    return 0
  fi

  if ! doctor_report_capture_temp_file stdout_file "stdout"; then
    if output="$(cd "${work_dir}" && "$@" 2>&1)"; then
      exit_code=0
    else
      exit_code=$?
    fi
    DOCTOR_REPORT_LAST_EXIT_CODE="${exit_code}"
    printf -v "${output_var}" '%s' "${output}"
    doctor_report_add_evidence "${purpose}" "${exit_code}" "captured_combined" "captured_combined" "not_truncated" "applied" "$@"
    return 0
  fi
  if ! doctor_report_capture_temp_file stderr_file "stderr"; then
    rm -f -- "${stdout_file}" 2>/dev/null || true
    if output="$(cd "${work_dir}" && "$@" 2>&1)"; then
      exit_code=0
    else
      exit_code=$?
    fi
    DOCTOR_REPORT_LAST_EXIT_CODE="${exit_code}"
    printf -v "${output_var}" '%s' "${output}"
    doctor_report_add_evidence "${purpose}" "${exit_code}" "captured_combined" "captured_combined" "not_truncated" "applied" "$@"
    return 0
  fi

  if (cd "${work_dir}" && "$@" >"${stdout_file}" 2>"${stderr_file}"); then
    exit_code=0
  else
    exit_code=$?
  fi
  DOCTOR_REPORT_LAST_EXIT_CODE="${exit_code}"
  stdout_output="$(cat -- "${stdout_file}" 2>/dev/null || true)"
  stderr_output="$(cat -- "${stderr_file}" 2>/dev/null || true)"
  rm -f -- "${stdout_file}" "${stderr_file}" 2>/dev/null || true

  output="${stdout_output}"
  if [[ -n "${stderr_output}" ]]; then
    [[ -z "${output}" ]] || output+=$'\n'
    output+="${stderr_output}"
  fi

  printf -v "${output_var}" '%s' "${output}"
  doctor_report_add_evidence "${purpose}" "${exit_code}" "$(doctor_report_capture_status "${stdout_output}")" "$(doctor_report_capture_status "${stderr_output}")" "not_truncated" "applied" "$@"
  return 0
}

doctor_report_append_captured_command() {
  local title="$1"
  local output=""
  shift

  doctor_report_emit "### ${title}"
  doctor_report_capture_command "${title}" output "$@"
  doctor_report_append_block "${output}"
  doctor_report_emit_blank
}

doctor_report_append_captured_command_in_dir() {
  local title="$1"
  local work_dir="$2"
  local output=""
  shift 2

  doctor_report_emit "### ${title}"
  doctor_report_capture_command_in_dir "${title}" output "${work_dir}" "$@"
  doctor_report_append_block "${output}"
  doctor_report_emit_blank
}

doctor_report_read_file_capture() {
  local purpose="$1"
  local path="$2"
  local output_var="${3:-}"
  local output=""
  local stdout_output=""
  local stderr_output=""
  local stdout_file=""
  local stderr_file=""
  local exit_code=0
  local read_status="read"
  local command_args=(cat -- "${path}")

  if [[ ! -r "${path}" ]]; then
    if [[ -e "${path}" ]] && declare -p DOCTOR_REPORT_SUDO >/dev/null 2>&1 && ((${#DOCTOR_REPORT_SUDO[@]} > 0)); then
      command_args=("${DOCTOR_REPORT_SUDO[@]}" cat -- "${path}")
      read_status="read_with_sudo"
    else
      if [[ -e "${path}" ]]; then
        doctor_report_add_skipped_file_read_evidence "${purpose}" "unreadable" "not readable and sudo unavailable" cat -- "${path}"
      else
        doctor_report_add_skipped_file_read_evidence "${purpose}" "missing" "file missing" cat -- "${path}"
      fi
      output="file is not readable"
      [[ -z "${output_var}" ]] || printf -v "${output_var}" '%s' "${output}"
      printf '%s\n' "${output}"
      return 0
    fi
  fi

  if ! doctor_report_capture_temp_file stdout_file "stdout"; then
    if output="$("${command_args[@]}" 2>&1)"; then
      exit_code=0
    else
      exit_code=$?
    fi
    [[ -z "${output_var}" ]] || printf -v "${output_var}" '%s' "${output}"
    doctor_report_add_file_read_evidence "${purpose}" "${read_status}" "${exit_code}" "captured_combined" "captured_combined" "not_truncated" "applied" "${command_args[@]}"
    printf '%s\n' "${output}"
    return 0
  fi
  if ! doctor_report_capture_temp_file stderr_file "stderr"; then
    rm -f -- "${stdout_file}" 2>/dev/null || true
    if output="$("${command_args[@]}" 2>&1)"; then
      exit_code=0
    else
      exit_code=$?
    fi
    [[ -z "${output_var}" ]] || printf -v "${output_var}" '%s' "${output}"
    doctor_report_add_file_read_evidence "${purpose}" "${read_status}" "${exit_code}" "captured_combined" "captured_combined" "not_truncated" "applied" "${command_args[@]}"
    printf '%s\n' "${output}"
    return 0
  fi

  if "${command_args[@]}" >"${stdout_file}" 2>"${stderr_file}"; then
    exit_code=0
  else
    exit_code=$?
  fi
  stdout_output="$(cat -- "${stdout_file}" 2>/dev/null || true)"
  stderr_output="$(cat -- "${stderr_file}" 2>/dev/null || true)"
  rm -f -- "${stdout_file}" "${stderr_file}" 2>/dev/null || true

  output="${stdout_output}"
  if [[ -n "${stderr_output}" ]]; then
    [[ -z "${output}" ]] || output+=$'\n'
    output+="${stderr_output}"
  fi

  if ((exit_code != 0)) && [[ -z "${output}" ]]; then
    output="file is not readable"
  fi

  [[ -z "${output_var}" ]] || printf -v "${output_var}" '%s' "${output}"
  doctor_report_add_file_read_evidence "${purpose}" "${read_status}" "${exit_code}" "$(doctor_report_capture_status "${stdout_output}")" "$(doctor_report_capture_status "${stderr_output}")" "not_truncated" "applied" "${command_args[@]}"
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
    doctor_report_emit_status "PASS" "${label}" "file exists"
  elif [[ -d "${path}" ]]; then
    doctor_report_emit_status "PASS" "${label}" "directory exists"
  elif [[ -e "${path}" ]]; then
    doctor_report_emit_status "FAIL" "${label}" "path exists but has an unexpected type"
  else
    doctor_report_emit_status "FAIL" "${label}" "missing"
  fi
}

doctor_report_append_summary() {
  doctor_report_emit "## Summary"
  doctor_report_file_status "APP_DIR" "${DOCTOR_REPORT_APP_DIR}"
  doctor_report_file_status "Compose file" "${DOCTOR_REPORT_COMPOSE_FILE}"
  doctor_report_file_status "Config file" "${DOCTOR_REPORT_CONFIG_FILE}"
  if command -v docker >/dev/null 2>&1; then
    doctor_report_emit_status "PASS" "docker command" "found"
  else
    doctor_report_emit_status "WARN" "docker command" "missing"
  fi
  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} > 0)); then
    doctor_report_emit_status "PASS" "Docker Compose command" "found"
  else
    doctor_report_emit_status "WARN" "Docker Compose command" "missing"
  fi
  doctor_report_emit "- Status counts: ${DOCTOR_REPORT_COUNTS_PLACEHOLDER}"
  doctor_report_emit "- Note: sensitive values were redacted"
  doctor_report_emit "- Mode: read-only report generation"
  doctor_report_emit_blank
}

doctor_report_append_environment() {
  local toolkit_dir=""
  local repo_root=""
  local git_branch=""
  local git_head=""

  toolkit_dir="$(cd -- "${DOCTOR_REPORT_SCRIPTS_DIR}/.." 2>/dev/null && pwd || printf '%s' "${DOCTOR_REPORT_SCRIPTS_DIR}/..")"
  repo_root="$(cd -- "${DOCTOR_REPORT_SCRIPTS_DIR}/../.." 2>/dev/null && pwd || printf '%s' "${DOCTOR_REPORT_SCRIPTS_DIR}/../..")"

  doctor_report_emit "## Environment"
  doctor_report_emit "- Generated at: $(date '+%Y-%m-%d %H:%M:%S %z')"
  doctor_report_emit "- Shell: ${SHELL:-unknown}"
  doctor_report_emit "- Bash version: ${BASH_VERSION:-unknown}"
  doctor_report_emit "- Toolkit dir: ${toolkit_dir}"
  doctor_report_emit "- App dir: ${DOCTOR_REPORT_APP_DIR}"
  if command -v git >/dev/null 2>&1 && git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch="$(git -C "${repo_root}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    git_head="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || true)"
    doctor_report_emit "- Git root: ${repo_root}"
    doctor_report_emit "- Git branch: ${git_branch:-unknown}"
    doctor_report_emit "- Git head: ${git_head:-unknown}"
  else
    doctor_report_emit "- Git: unavailable or not a worktree"
  fi
  doctor_report_emit_blank
  doctor_report_append_captured_command "uname" uname -a
  if [[ -f /etc/os-release ]]; then
    doctor_report_append_captured_command "os-release" awk -F= '/^(PRETTY_NAME|ID|VERSION_ID)=/{print}' /etc/os-release
  else
    doctor_report_emit "### os-release"
    doctor_report_emit "- WARN /etc/os-release missing"
    doctor_report_emit_blank
  fi
}

doctor_report_append_toolkit_self_check() {
  local self_check_file="${DOCTOR_REPORT_SCRIPTS_DIR}/toolkit/self_check.sh"

  doctor_report_emit "## Toolkit Self-check"
  doctor_report_file_status "sillytavern.sh" "${DOCTOR_REPORT_SCRIPTS_DIR}/sillytavern.sh"
  doctor_report_file_status "doctor_report.sh" "${DOCTOR_REPORT_SCRIPTS_DIR}/doctor_report.sh"
  doctor_report_file_status "toolkit/self_check.sh" "${self_check_file}"
  doctor_report_append_captured_command "sillytavern.sh syntax" bash -n "${DOCTOR_REPORT_SCRIPTS_DIR}/sillytavern.sh"
  doctor_report_append_captured_command "doctor_report.sh syntax" bash -n "${DOCTOR_REPORT_SCRIPTS_DIR}/doctor_report.sh"
  if [[ -f "${self_check_file}" ]]; then
    doctor_report_append_captured_command "self_check.sh syntax" bash -n "${self_check_file}"
  fi
}

doctor_report_append_compose_service_detail() {
  local service="$1"
  local container_refs_output=""
  local inspect_output=""
  local container_refs=()
  local ref=""

  doctor_report_emit "### Compose Service Containers (${service})"
  doctor_report_capture_command_in_dir "Compose Service Container IDs (${service})" container_refs_output "${DOCTOR_REPORT_APP_DIR}" "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" ps -q "${service}"
  doctor_report_append_block "${container_refs_output}"
  doctor_report_emit_blank

  while IFS= read -r ref; do
    [[ -n "${ref}" ]] || continue
    [[ "${ref}" == *[[:space:]]* ]] && continue
    [[ "${ref}" == -* ]] && continue
    container_refs+=("${ref}")
  done <<<"${container_refs_output}"

  doctor_report_emit "### Docker Inspect (${service})"
  if ((${#container_refs[@]} == 0)); then
    doctor_report_add_skipped_evidence "Docker Inspect (${service})" "no container ids from compose ps -q" docker inspect --format 'Name={{.Name}} State={{.State.Status}} RestartCount={{.RestartCount}} Image={{.Config.Image}}'
    doctor_report_append_block ""
  else
    doctor_report_capture_command "Docker Inspect (${service})" inspect_output "${DOCTOR_REPORT_SUDO[@]}" docker inspect --format 'Name={{.Name}} State={{.State.Status}} RestartCount={{.RestartCount}} Image={{.Config.Image}}' "${container_refs[@]}"
    doctor_report_append_block "${inspect_output}"
  fi
  doctor_report_emit_blank
}

doctor_report_append_docker_compose() {
  doctor_report_emit "## Docker Compose"
  if ! command -v docker >/dev/null 2>&1; then
    doctor_report_emit_status "WARN" "docker command" "not found"
    doctor_report_emit_blank
    return 0
  fi

  doctor_report_append_captured_command "Docker Version" "${DOCTOR_REPORT_SUDO[@]}" docker --version
  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} > 0)); then
    doctor_report_append_captured_command "Compose Version" "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" version
    if [[ -d "${DOCTOR_REPORT_APP_DIR}" ]]; then
      doctor_report_append_captured_command_in_dir "Compose PS" "${DOCTOR_REPORT_APP_DIR}" "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" ps
      if [[ "${DOCTOR_REPORT_ALL_SERVICES}" != "1" ]]; then
        doctor_report_append_captured_command_in_dir "Compose Service PS (${DOCTOR_REPORT_SERVICE})" "${DOCTOR_REPORT_APP_DIR}" "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" ps "${DOCTOR_REPORT_SERVICE}"
        doctor_report_append_captured_command_in_dir "Compose Service Image (${DOCTOR_REPORT_SERVICE})" "${DOCTOR_REPORT_APP_DIR}" "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" images "${DOCTOR_REPORT_SERVICE}"
        doctor_report_append_compose_service_detail "${DOCTOR_REPORT_SERVICE}"
      fi
    fi
  else
    doctor_report_emit_status "WARN" "Docker Compose command" "not found"
    doctor_report_emit_blank
  fi
}

doctor_report_append_sillytavern_status() {
  doctor_report_emit "## SillyTavern Status"
  doctor_report_file_status "APP_DIR" "${DOCTOR_REPORT_APP_DIR}"
  doctor_report_file_status "Compose file" "${DOCTOR_REPORT_COMPOSE_FILE}"
  doctor_report_file_status "Config file" "${DOCTOR_REPORT_CONFIG_FILE}"
  doctor_report_emit "- APP_DIR: ${DOCTOR_REPORT_APP_DIR}"
  doctor_report_emit "- Compose file: ${DOCTOR_REPORT_COMPOSE_FILE}"
  doctor_report_emit "- Config file: ${DOCTOR_REPORT_CONFIG_FILE}"
  doctor_report_emit "- Compose service scope: $([[ "${DOCTOR_REPORT_ALL_SERVICES}" == "1" ]] && printf 'all services' || printf '%s' "${DOCTOR_REPORT_SERVICE}")"
  doctor_report_emit "- Logs scope: $([[ "${DOCTOR_REPORT_NO_LOGS}" == "1" ]] && printf 'skipped' || printf 'tail=%s since=%s' "${DOCTOR_REPORT_LINES}" "${DOCTOR_REPORT_SINCE:-not set}")"
  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} > 0)) && [[ -d "${DOCTOR_REPORT_APP_DIR}" ]]; then
    doctor_report_emit "- Health-ish signals: compose ps captured in Docker Compose section"
  else
    doctor_report_emit "- Health-ish signals: compose ps unavailable"
  fi
  doctor_report_emit_blank
}

doctor_report_append_access_config() {
  local config_output=""
  local listen_value="unknown"
  local port_value="unknown"

  doctor_report_emit "## Access Config"
  if [[ ! -f "${DOCTOR_REPORT_CONFIG_FILE}" ]]; then
    doctor_report_emit_status "WARN" "config file" "missing"
    doctor_report_add_skipped_file_read_evidence "Access config read" "missing" "config file missing" cat -- "${DOCTOR_REPORT_CONFIG_FILE}"
    doctor_report_emit_blank
    return 0
  fi

  doctor_report_read_file_capture "Access config read" "${DOCTOR_REPORT_CONFIG_FILE}" config_output >/dev/null
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

  if grep -q 'basicAuthUser:' <<<"${config_output}"; then
    doctor_report_emit "- basicAuthUser block: present"
  else
    doctor_report_emit "- basicAuthUser block: not found"
  fi
  listen_value="$(awk -F: '/^[[:space:]]*listen[[:space:]]*:/{gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", $2); print $2; exit}' <<<"${config_output}")"
  port_value="$(awk -F: '/^[[:space:]]*port[[:space:]]*:/{gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", $2); print $2; exit}' <<<"${config_output}")"
  doctor_report_emit "- bind/listen fact: ${listen_value:-unknown}"
  doctor_report_emit "- port fact: ${port_value:-unknown}"
  doctor_report_emit_blank
}

doctor_report_append_mirror_config() {
  local mirrors_output=""

  doctor_report_emit "## Mirror Config"
  doctor_report_emit "- Toolkit China mirror flag: ${USE_CHINA_MIRROR:-unknown}"
  doctor_report_emit "- Public IP probe: not run"
  if [[ -f /etc/docker/daemon.json ]]; then
    doctor_report_file_status "Docker daemon config" "/etc/docker/daemon.json"
    doctor_report_read_file_capture "Docker daemon config read" "/etc/docker/daemon.json" mirrors_output >/dev/null
    if grep -q '"registry-mirrors"' <<<"${mirrors_output}"; then
      doctor_report_emit "- Docker registry mirror configured: yes"
      doctor_report_emit "- Docker registry mirror source: /etc/docker/daemon.json"
      grep -E '"https?://[^"]+"' <<<"${mirrors_output}" |
        sed -E 's/.*"(https?:\/\/[^"]+)".*/- Docker registry mirror URL: \1/' |
        head -n 5 |
        doctor_redact_stream |
        doctor_report_write_raw
    else
      doctor_report_emit "- Docker registry mirror configured: no"
      doctor_report_emit "- Docker registry mirror source: /etc/docker/daemon.json"
      doctor_report_emit "- Docker registry mirror URL: not configured"
    fi
  else
    doctor_report_emit "- Docker daemon config: not found"
    doctor_report_emit "- Docker registry mirror configured: unknown"
    doctor_report_emit "- Docker registry mirror source: missing /etc/docker/daemon.json"
    doctor_report_emit "- Docker registry mirror URL: unknown"
    doctor_report_add_skipped_file_read_evidence "Docker daemon config read" "missing" "daemon.json missing" cat -- "/etc/docker/daemon.json"
  fi
  doctor_report_emit_blank
}

doctor_report_append_compose_validation() {
  local exit_code=0
  local validation_output=""

  doctor_report_emit "## Compose Validation"
  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} == 0)); then
    doctor_report_emit_status "WARN" "Docker Compose command" "unavailable; validation skipped"
    doctor_report_add_skipped_evidence "Compose validation" "compose unavailable" docker compose config -q
    doctor_report_emit_blank
    return 0
  fi

  if [[ ! -d "${DOCTOR_REPORT_APP_DIR}" ]]; then
    doctor_report_emit_status "FAIL" "APP_DIR" "missing; validation skipped"
    doctor_report_add_skipped_evidence "Compose validation" "APP_DIR missing" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" config -q
    doctor_report_emit_blank
    return 0
  fi

  if [[ ! -f "${DOCTOR_REPORT_COMPOSE_FILE}" ]]; then
    doctor_report_emit_status "FAIL" "Compose file" "missing; validation skipped"
    doctor_report_add_skipped_evidence "Compose validation" "compose file missing" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" config -q
    doctor_report_emit_blank
    return 0
  fi

  doctor_report_capture_command_in_dir "Compose validation" validation_output "${DOCTOR_REPORT_APP_DIR}" "${DOCTOR_REPORT_SUDO[@]}" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" config -q
  exit_code="${DOCTOR_REPORT_LAST_EXIT_CODE}"

  if [[ "${exit_code}" == "0" ]]; then
    doctor_report_emit_status "PASS" "docker compose config -q" "exit code ${exit_code}"
  else
    doctor_report_emit_status "FAIL" "docker compose config -q" "exit code ${exit_code}"
  fi
  doctor_report_emit "### docker compose config -q output"
  doctor_report_append_block "${validation_output}"
  doctor_report_emit_blank
}

doctor_report_collect_recent_logs() {
  local output=""
  local exit_code=0
  local logs_args=(logs --tail "${DOCTOR_REPORT_LINES}")

  DOCTOR_REPORT_LOGS_OUTPUT=""
  DOCTOR_REPORT_LOGS_STATUS=""

  if [[ "${DOCTOR_REPORT_NO_LOGS}" == "1" ]]; then
    DOCTOR_REPORT_LOGS_STATUS="- Logs skipped by --no-logs"
    doctor_report_add_skipped_evidence "Logs capture" "--no-logs" docker compose logs
    return 0
  fi

  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} == 0)); then
    DOCTOR_REPORT_LOGS_STATUS="- WARN Docker Compose command unavailable; logs skipped"
    doctor_report_add_skipped_evidence "Logs capture" "compose unavailable" docker compose logs
    return 0
  fi

  if [[ ! -d "${DOCTOR_REPORT_APP_DIR}" ]]; then
    DOCTOR_REPORT_LOGS_STATUS="- FAIL APP_DIR missing; logs skipped"
    doctor_report_add_skipped_evidence "Logs capture" "APP_DIR missing" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" "${logs_args[@]}"
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
  DOCTOR_REPORT_LOGS_STATUS="- docker compose logs exit code: ${exit_code}"
  DOCTOR_REPORT_LOGS_OUTPUT="${output}"
  doctor_report_add_evidence "Logs capture" "${exit_code}" "captured_combined" "captured_combined" "not_truncated" "applied" "${DOCTOR_REPORT_COMPOSE_CMD[@]}" "${logs_args[@]}"
}

doctor_report_append_command_evidence() {
  local item=""

  doctor_report_emit "## Command Evidence"
  if ((${#DOCTOR_REPORT_EVIDENCE[@]} == 0)); then
    doctor_report_emit "- No commands were captured"
  else
    for item in "${DOCTOR_REPORT_EVIDENCE[@]}"; do
      doctor_report_emit "${item}"
    done
  fi
  doctor_report_emit_blank
}

doctor_report_append_recent_logs() {
  doctor_report_emit "## Recent Logs"
  doctor_report_emit "${DOCTOR_REPORT_LOGS_STATUS}"
  if [[ -n "${DOCTOR_REPORT_LOGS_OUTPUT}" ]]; then
    doctor_report_append_block "${DOCTOR_REPORT_LOGS_OUTPUT}"
  fi
  doctor_report_emit_blank
}

doctor_report_append_recommendations() {
  doctor_report_emit "## Recommendations"
  if [[ ! -d "${DOCTOR_REPORT_APP_DIR}" ]]; then
    doctor_report_emit "- problem: APP_DIR is missing; impact: lifecycle and evidence commands cannot resolve the deployment; fix: create or configure the SillyTavern deployment directory before lifecycle commands."
  fi
  if [[ ! -f "${DOCTOR_REPORT_COMPOSE_FILE}" ]]; then
    doctor_report_emit "- problem: Compose file is missing; impact: start/update/validation cannot determine services; fix: restore the expected Compose file before starting or updating the container."
  fi
  if [[ ! -f "${DOCTOR_REPORT_CONFIG_FILE}" ]]; then
    doctor_report_emit "- problem: config file is missing; impact: access mode and port facts are unavailable; fix: restore the expected config file before changing access settings."
  fi
  if ((${#DOCTOR_REPORT_COMPOSE_CMD[@]} == 0)); then
    doctor_report_emit "- problem: Docker Compose is unavailable; impact: compose validation, status, and logs cannot be captured; fix: install Docker Compose or make it visible in PATH."
  fi
  doctor_report_emit "- problem: report sharing may expose local context; impact: even redacted reports can include paths and status metadata; fix: review the redacted contents before sharing."
  doctor_report_emit_blank
}

doctor_report_run_section() {
  local section_function="$1"
  local section_status=0
  shift || true

  if ! declare -F "${section_function}" >/dev/null 2>&1; then
    doctor_report_error "missing report section function: ${section_function}"
    return 2
  fi

  "${section_function}" "$@"
  section_status=$?
  if ((section_status != 0)); then
    doctor_report_error "report section failed: ${section_function} (exit ${section_status})"
    return "${section_status}"
  fi
}

doctor_report_verify_sections() {
  local section=""
  local missing=0

  if [[ -z "${DOCTOR_REPORT_TMP_FILE:-}" || ! -f "${DOCTOR_REPORT_TMP_FILE}" ]]; then
    doctor_report_error "report temporary file is missing"
    return 2
  fi

  for section in "${DOCTOR_REPORT_REQUIRED_SECTIONS[@]}"; do
    if ! grep -Fx -- "${section}" "${DOCTOR_REPORT_TMP_FILE}" >/dev/null 2>&1; then
      doctor_report_error "report is missing section: ${section}"
      missing=1
    fi
  done

  ((missing == 0)) || return 2
}

doctor_report_generate() {
  local generation_status=0

  doctor_report_emit "# SillyTavern Doctor Report"
  doctor_report_emit_blank
  doctor_report_emit "- Report schema: doctor-report/v1"
  doctor_report_emit "- This report is read-only; command failures are recorded as evidence."
  doctor_report_emit_blank

  doctor_report_run_section doctor_report_append_summary || generation_status=2
  doctor_report_run_section doctor_report_append_environment || generation_status=2
  doctor_report_run_section doctor_report_append_toolkit_self_check || generation_status=2
  doctor_report_run_section doctor_report_append_docker_compose || generation_status=2
  doctor_report_run_section doctor_report_append_sillytavern_status || generation_status=2
  doctor_report_run_section doctor_report_append_access_config || generation_status=2
  doctor_report_run_section doctor_report_append_mirror_config || generation_status=2
  doctor_report_run_section doctor_report_append_compose_validation || generation_status=2
  doctor_report_run_section doctor_report_collect_recent_logs || generation_status=2
  doctor_report_run_section doctor_report_append_command_evidence || generation_status=2
  doctor_report_run_section doctor_report_append_recent_logs || generation_status=2
  doctor_report_run_section doctor_report_append_recommendations || generation_status=2
  doctor_report_verify_sections || generation_status=2

  return "${generation_status}"
}

doctor_report_prepare_output() {
  local output_dir=""
  local old_umask=""

  if [[ "${DOCTOR_REPORT_TO_STDOUT}" == "1" ]]; then
    output_dir="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
  else
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
  fi

  if [[ ! -d "${output_dir}" || ! -w "${output_dir}" ]]; then
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
  local counts_text="PASS=${DOCTOR_REPORT_PASS_COUNT} WARN=${DOCTOR_REPORT_WARN_COUNT} FAIL=${DOCTOR_REPORT_FAIL_COUNT}"
  local finalized_file=""

  if [[ -z "${DOCTOR_REPORT_TMP_FILE:-}" || ! -f "${DOCTOR_REPORT_TMP_FILE}" ]]; then
    doctor_report_error "report temporary file is missing"
    return 2
  fi

  finalized_file="${DOCTOR_REPORT_TMP_FILE}.final"
  if ! sed "s/${DOCTOR_REPORT_COUNTS_PLACEHOLDER}/${counts_text}/g" "${DOCTOR_REPORT_TMP_FILE}" >"${finalized_file}"; then
    rm -f -- "${DOCTOR_REPORT_TMP_FILE}" "${finalized_file}" 2>/dev/null || true
    doctor_report_error "failed to finalize report status counts"
    return 2
  fi
  mv -f -- "${finalized_file}" "${DOCTOR_REPORT_TMP_FILE}" || {
    rm -f -- "${DOCTOR_REPORT_TMP_FILE}" "${finalized_file}" 2>/dev/null || true
    doctor_report_error "failed to finalize report status counts"
    return 2
  }

  if [[ "${DOCTOR_REPORT_TO_STDOUT}" == "1" ]]; then
    cat -- "${DOCTOR_REPORT_TMP_FILE}"
    rm -f -- "${DOCTOR_REPORT_TMP_FILE}" 2>/dev/null || true
    DOCTOR_REPORT_TMP_FILE=""
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

doctor_report_main() {
  local parse_status=0
  local restore_errexit=0
  local generation_status=0

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

  DOCTOR_REPORT_SCRIPTS_DIR="${__st_scripts_dir:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
  DOCTOR_REPORT_APP_DIR="${APP_DIR:-/data/docker/sillytavern}"
  DOCTOR_REPORT_COMPOSE_FILE="${ST_COMPOSE_FILE:-${DOCTOR_REPORT_APP_DIR}/docker-compose.yaml}"
  DOCTOR_REPORT_CONFIG_FILE="${ST_CONFIG_FILE:-${DOCTOR_REPORT_APP_DIR}/config/config.yaml}"
  DOCTOR_REPORT_SUDO=()
  DOCTOR_REPORT_COMPOSE_CMD=()
  DOCTOR_REPORT_EVIDENCE=()
  DOCTOR_REPORT_LOGS_STATUS=""
  DOCTOR_REPORT_LOGS_OUTPUT=""
  DOCTOR_REPORT_TMP_FILE=""
  DOCTOR_REPORT_LAST_EXIT_CODE=0
  doctor_report_reset_counts

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
  generation_status=$?
  if ((generation_status != 0)); then
    doctor_report_cleanup_tmp
    ((restore_errexit == 0)) || set -e
    return "${generation_status}"
  fi
  doctor_report_finalize_output
  parse_status=$?
  ((restore_errexit == 0)) || set -e
  return "${parse_status}"
}

doctor_report_st() {
  doctor_report_main "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  doctor_report_main "$@"
fi
