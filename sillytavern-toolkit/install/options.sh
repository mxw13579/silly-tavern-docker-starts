parse_args() {
  while (($# > 0)); do
    case "$1" in
      --no-launch)
        LAUNCH_TOOLKIT=false
        ;;
      --ref)
        shift
        [[ -n "${1:-}" ]] || fatal "--ref 需要一个分支、标签或 commit。"
        TOOLKIT_REF="$1"
        ;;
      -y|--yes)
        ASSUME_YES=true
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        fatal "未知参数: $1"
        ;;
    esac
    shift
  done
}

truthy_env() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    0|false|FALSE|no|NO|n|N|off|OFF|"") return 1 ;;
    *) return 2 ;;
  esac
}

is_full_commit_ref() {
  [[ "${TOOLKIT_REF}" =~ ^[0-9A-Fa-f]{40}$ ]]
}

init_env_options() {
  local rc

  if truthy_env "${ST_TOOLKIT_YES:-}"; then
    ASSUME_YES=true
  else
    rc=$?
    case "${rc}" in
      1) ;;
      2) fatal "ST_TOOLKIT_YES 只能为 1/0、true/false、yes/no、on/off。" ;;
    esac
  fi

  if truthy_env "${ST_TOOLKIT_NO_LAUNCH:-}"; then
    LAUNCH_TOOLKIT=false
  else
    rc=$?
    case "${rc}" in
      1) ;;
      2) fatal "ST_TOOLKIT_NO_LAUNCH 只能为 1/0、true/false、yes/no、on/off。" ;;
    esac
  fi
}

validate_ref() {
  [[ -n "${TOOLKIT_REF}" ]] || fatal "TOOLKIT_REF 不能为空。"
  ((${#TOOLKIT_REF} <= 128)) || fatal "TOOLKIT_REF 长度不能超过 128。"

  [[ "${TOOLKIT_REF}" =~ ^[A-Za-z0-9._/-]+$ ]] || fatal "TOOLKIT_REF 只能包含 A-Z、a-z、0-9、.、_、-、/。"

  case "${TOOLKIT_REF}" in
    -*|/*|*..*|*//*|*"?*"|*"#"*|*"@{"*|*.lock|./*|*/.*)
      fatal "TOOLKIT_REF 格式不安全: ${TOOLKIT_REF}"
      ;;
  esac

  if is_full_commit_ref; then
    return 0
  fi

  if command -v git &>/dev/null; then
    git check-ref-format --allow-onelevel "${TOOLKIT_REF}" &>/dev/null || fatal "TOOLKIT_REF 不是合法的 git ref: ${TOOLKIT_REF}"
  fi
}

validate_checksums_url() {
  [[ -z "${CHECKSUMS_URL}" || "${CHECKSUMS_URL}" =~ ^https:// ]] || fatal "ST_TOOLKIT_CHECKSUMS_URL 必须使用 HTTPS。"
}
