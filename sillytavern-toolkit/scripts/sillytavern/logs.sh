#!/usr/bin/env bash

DEFAULT_LOG_TAIL_LINES=200
DEFAULT_LOG_FOLLOW_LINES=100
DEFAULT_LOG_SINCE_LINES=1000
DEFAULT_LOG_SAVE_LINES=1000
MAX_LOG_LINES=5000

logs_error() {
  local problem="$1"
  local impact="$2"
  local fix="$3"

  printf 'ERROR: problem: %s\n' "${problem}" >&2
  printf 'ERROR: impact: %s\n' "${impact}" >&2
  printf 'ERROR: fix: %s\n' "${fix}" >&2
}

logs_usage() {
  cat <<'EOF'
Usage: sillytavern.sh logs [tail|follow|since|save] [options]

Commands:
  logs                         Show recent logs, same as logs tail --lines 200
  logs tail [--lines N]        Show a bounded log snapshot
  logs follow [--lines N]      Follow logs until Ctrl+C
  logs since VALUE [--all]     Show logs since a Compose time value
  logs save [--output PATH]    Save logs to a file

Common options:
  --lines N, --tail N          Positive line count, max 5000
  --since VALUE                Pass a Docker Compose --since value through
  --service NAME               Read one Compose service, default sillytavern
  --all-services               Read all Compose services
EOF
}

logs_validate_lines() {
  local value="$1"

  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    logs_error "invalid line count: ${value}" \
      "safe log inspection needs a positive bounded line count" \
      "use --lines with a value from 1 to ${MAX_LOG_LINES}"
    return 1
  fi

  if ((value > MAX_LOG_LINES)); then
    logs_error "line count is too large: ${value}" \
      "large SSH output can hide the useful failure context" \
      "use --lines with a value no larger than ${MAX_LOG_LINES}, or use logs save"
    return 1
  fi
}

logs_parse_common_option() {
  local option="$1"
  LOGS_COMMON_SHIFT=0

  case "${option}" in
    --service)
      [[ $# -ge 2 && -n "${2:-}" ]] || {
        logs_error "missing value for --service" \
          "the logs command cannot choose a Compose service" \
          "use --service sillytavern or --all-services"
        return 2
      }
      if [[ "${LOGS_ALL_SERVICES}" == "1" ]]; then
        logs_error "--service cannot be used with --all-services" \
          "Compose would receive conflicting service targeting" \
          "choose either --service NAME or --all-services"
        return 2
      fi
      LOGS_SERVICE="$2"
      LOGS_COMMON_SHIFT=2
      return 0
      ;;
    --all-services)
      if [[ -n "${LOGS_SERVICE}" ]]; then
        logs_error "--all-services cannot be used with --service" \
          "Compose would receive conflicting service targeting" \
          "choose either --all-services or --service NAME"
        return 2
      fi
      LOGS_ALL_SERVICES=1
      LOGS_COMMON_SHIFT=1
      return 0
      ;;
  esac

  return 1
}

logs_append_service_args() {
  if [[ "${LOGS_ALL_SERVICES}" == "1" ]]; then
    return 0
  fi

  LOGS_COMPOSE_ARGS+=("${LOGS_SERVICE:-sillytavern}")
}

logs_compose_in_app() {
  (cd "${APP_DIR}" && "${SUDO[@]}" "${COMPOSE_CMD[@]}" logs "$@")
}

logs_run_tail() {
  local lines="${DEFAULT_LOG_TAIL_LINES}"
  local since=""
  LOGS_SERVICE=""
  LOGS_ALL_SERVICES=0

  while (($# > 0)); do
    case "$1" in
      --lines|--tail)
        [[ $# -ge 2 && -n "${2:-}" ]] || {
          logs_error "missing value for $1" \
            "the logs command cannot keep output bounded" \
            "use $1 200"
          return 1
        }
        logs_validate_lines "$2" || return 1
        lines="$2"
        shift 2
        ;;
      --since)
        [[ $# -ge 2 && -n "${2:-}" ]] || {
          logs_error "missing value for --since" \
            "Docker Compose needs a time expression to filter logs" \
            "use --since 30m or --since 2026-06-11T10:00:00+08:00"
          return 1
        }
        since="$2"
        shift 2
        ;;
      --service|--all-services)
        logs_parse_common_option "$@" || return 1
        shift "${LOGS_COMMON_SHIFT}"
        ;;
      *)
        logs_error "unknown logs tail option: $1" \
          "unknown options are rejected before Docker Compose runs" \
          "use logs tail --lines N [--since VALUE] [--service NAME|--all-services]"
        return 1
        ;;
    esac
  done

  LOGS_COMPOSE_ARGS=(--tail "${lines}")
  [[ -z "${since}" ]] || LOGS_COMPOSE_ARGS+=(--since "${since}")
  logs_append_service_args
  logs_compose_in_app "${LOGS_COMPOSE_ARGS[@]}"
}

logs_run_follow() {
  local lines="${DEFAULT_LOG_FOLLOW_LINES}"
  local since=""
  LOGS_SERVICE=""
  LOGS_ALL_SERVICES=0

  while (($# > 0)); do
    case "$1" in
      --lines|--tail)
        [[ $# -ge 2 && -n "${2:-}" ]] || {
          logs_error "missing value for $1" \
            "the follow command needs a bounded starting window" \
            "use $1 100"
          return 1
        }
        logs_validate_lines "$2" || return 1
        lines="$2"
        shift 2
        ;;
      --since)
        [[ $# -ge 2 && -n "${2:-}" ]] || {
          logs_error "missing value for --since" \
            "Docker Compose needs a time expression to filter logs" \
            "use --since 30m"
          return 1
        }
        since="$2"
        shift 2
        ;;
      --service|--all-services)
        logs_parse_common_option "$@" || return 1
        shift "${LOGS_COMMON_SHIFT}"
        ;;
      *)
        logs_error "unknown logs follow option: $1" \
          "unknown options are rejected before Docker Compose runs" \
          "use logs follow [--lines N] [--since VALUE] [--service NAME|--all-services]"
        return 1
        ;;
    esac
  done

  msg_info "Press Ctrl+C to stop realtime logs. To save logs, use: bash sillytavern-toolkit/scripts/sillytavern.sh logs save --output <path>"
  LOGS_COMPOSE_ARGS=(--follow --tail "${lines}")
  [[ -z "${since}" ]] || LOGS_COMPOSE_ARGS+=(--since "${since}")
  logs_append_service_args
  logs_compose_in_app "${LOGS_COMPOSE_ARGS[@]}"
}

logs_run_since() {
  local since="${1:-}"
  local lines="${DEFAULT_LOG_SINCE_LINES}"
  local all_lines=0
  LOGS_SERVICE=""
  LOGS_ALL_SERVICES=0

  if [[ -z "${since}" || "${since}" == --* ]]; then
    logs_error "missing logs since value" \
      "Docker Compose needs a supported time expression" \
      "use logs since 30m or logs since 2026-06-11T10:00:00+08:00"
    return 1
  fi
  shift

  while (($# > 0)); do
    case "$1" in
      --lines|--tail)
        [[ $# -ge 2 && -n "${2:-}" ]] || {
          logs_error "missing value for $1" \
            "the since command cannot keep output bounded" \
            "use $1 1000 or --all"
          return 1
        }
        logs_validate_lines "$2" || return 1
        lines="$2"
        all_lines=0
        shift 2
        ;;
      --all)
        all_lines=1
        shift
        ;;
      --service|--all-services)
        logs_parse_common_option "$@" || return 1
        shift "${LOGS_COMMON_SHIFT}"
        ;;
      *)
        logs_error "unknown logs since option: $1" \
          "unknown options are rejected before Docker Compose runs" \
          "use logs since VALUE [--lines N|--all] [--service NAME|--all-services]"
        return 1
        ;;
    esac
  done

  LOGS_COMPOSE_ARGS=(--since "${since}")
  if ((all_lines)); then
    msg_warn "logs since --all output may be large; consider logs save for support artifacts."
  else
    LOGS_COMPOSE_ARGS+=(--tail "${lines}")
  fi
  logs_append_service_args
  logs_compose_in_app "${LOGS_COMPOSE_ARGS[@]}"
}

logs_run_save() {
  local output_path=""
  local lines="${DEFAULT_LOG_SAVE_LINES}"
  local since=""
  local all_lines=0
  local output_was_default=0
  LOGS_SERVICE=""
  LOGS_ALL_SERVICES=0

  while (($# > 0)); do
    case "$1" in
      --output)
        [[ $# -ge 2 && -n "${2:-}" ]] || {
          logs_error "missing value for --output" \
            "the logs command does not know where to save the file" \
            "use logs save --output /path/to/sillytavern.log"
          return 1
        }
        output_path="$2"
        shift 2
        ;;
      --lines|--tail)
        [[ $# -ge 2 && -n "${2:-}" ]] || {
          logs_error "missing value for $1" \
            "the save command cannot keep capture size bounded" \
            "use $1 1000 or --all"
          return 1
        }
        logs_validate_lines "$2" || return 1
        lines="$2"
        all_lines=0
        shift 2
        ;;
      --since)
        [[ $# -ge 2 && -n "${2:-}" ]] || {
          logs_error "missing value for --since" \
            "Docker Compose needs a time expression to filter logs" \
            "use --since 30m"
          return 1
        }
        since="$2"
        shift 2
        ;;
      --all)
        all_lines=1
        shift
        ;;
      --follow)
        logs_error "logs save does not support --follow" \
          "save must produce a one-shot support artifact" \
          "use logs follow for streaming or logs save without --follow"
        return 1
        ;;
      --service|--all-services)
        logs_parse_common_option "$@" || return 1
        shift "${LOGS_COMMON_SHIFT}"
        ;;
      *)
        logs_error "unknown logs save option: $1" \
          "unknown options are rejected before Docker Compose runs" \
          "use logs save [--output PATH] [--lines N|--since VALUE|--all]"
        return 1
        ;;
    esac
  done

  if [[ -z "${output_path}" ]]; then
    output_path="${HOME}/sillytavern_logs_$(date +%Y%m%d_%H%M%S).log"
    output_was_default=1
  fi

  local output_dir tmp_file
  output_dir="$(dirname -- "${output_path}")"
  if [[ ! -d "${output_dir}" ]]; then
    logs_error "output directory does not exist: ${output_dir}" \
      "the logs file cannot be written safely" \
      "create the directory or choose another --output path"
    return 1
  fi
  if [[ ! -w "${output_dir}" ]]; then
    logs_error "output directory is not writable: ${output_dir}" \
      "the logs file must be owned by the current shell user" \
      "choose a writable --output directory"
    return 1
  fi

  ((output_was_default == 0)) || msg_info "No --output provided; saving logs to ${output_path}"

  tmp_file="$(mktemp "${output_dir}/.sillytavern_logs.XXXXXX")" || return 1
  LOGS_COMPOSE_ARGS=()
  [[ -z "${since}" ]] || LOGS_COMPOSE_ARGS+=(--since "${since}")
  if ((all_lines)); then
    msg_warn "logs save --all output may be large."
  else
    LOGS_COMPOSE_ARGS+=(--tail "${lines}")
  fi
  logs_append_service_args

  if logs_compose_in_app "${LOGS_COMPOSE_ARGS[@]}" >"${tmp_file}"; then
    mv -f "${tmp_file}" "${output_path}"
    msg_ok "Logs saved: ${output_path}"
    msg_info "Attach this file when asking for support."
    return 0
  fi

  rm -f "${tmp_file}"
  return 1
}

logs_dispatch() {
  check_docker_env || return 1
  [[ -f "${ST_COMPOSE_FILE}" ]] || fatal "SillyTavern install not found; missing ${ST_COMPOSE_FILE}."

  local subcommand="${1:-tail}"
  if (($# > 0)); then
    shift
  fi

  case "${subcommand}" in
    tail)
      logs_run_tail "$@"
      ;;
    follow)
      logs_run_follow "$@"
      ;;
    since)
      logs_run_since "$@"
      ;;
    save)
      logs_run_save "$@"
      ;;
    help|--help|-h)
      logs_usage
      ;;
    *)
      logs_error "unknown logs subcommand: ${subcommand}" \
        "the toolkit only supports bounded inspection, explicit follow, since, and save" \
        "use logs tail, logs follow, logs since VALUE, or logs save"
      return 1
      ;;
  esac
}

logs_st() {
  logs_dispatch "$@"
}
