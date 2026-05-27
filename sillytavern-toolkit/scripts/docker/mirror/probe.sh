#!/usr/bin/env bash

normalize_mirror_url() {
  local url="${1:-}"

  url="${url//$'\r'/}"
  url="${url//$'\n'/}"
  url="${url//$'\t'/}"
  url="${url%"${url##*[![:space:]]}"}"
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%/}"

  [[ "${url}" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/%+=-]+)?$ ]] || return 1

  printf '%s\n' "${url}"
}


measure_mirror() {
  local mirror="$1"
  local endpoint
  endpoint="${mirror%/}/v2/"

  local cache_ttl=1800
  local cache_key=""
  cache_key="$(st_cache_key "docker.mirror.speed|${endpoint}" 2>/dev/null)" || cache_key=""
  if [[ -n "${cache_key}" ]]; then
    local cached=""
    if cached="$(st_cache_read "${cache_ttl}" "${cache_key}" 2>/dev/null)" && [[ -n "${cached}" ]]; then
      # 保证每次输出严格一行，并且末尾换行可靠（历史缓存可能缺少换行）。
      printf '%s\n' "${cached%$'\n'}"
      return 0
    fi
  fi

  command -v curl &>/dev/null || {
    printf '9999.999\t000\t%s\n' "${mirror}"
    return 0
  }

  local result code total
  result="$(curl -L -sS -o /dev/null -w '%{http_code} %{time_total}' \
    --connect-timeout 5 \
    --max-time 15 \
    "${endpoint}" 2>/dev/null || true)"

  code="${result%% *}"
  total="${result##* }"

  if [[ "${code}" == "200" || "${code}" == "401" ]]; then
    local line
    printf -v line '%s\t%s\t%s\n' "${total}" "${code}" "${mirror}"
    if [[ -n "${cache_key}" ]]; then
      printf '%s' "${line}" | st_cache_write "${cache_key}" 2>/dev/null || true
    fi
    printf '%s' "${line}"
  else
    local line
    printf -v line '9999.999\t%s\t%s\n' "${code:-000}" "${mirror}"
    if [[ -n "${cache_key}" ]]; then
      printf '%s' "${line}" | st_cache_write "${cache_key}" 2>/dev/null || true
    fi
    printf '%s' "${line}"
  fi
}


measure_docker_hub_native() {
  local endpoint="${DOCKER_HUB_NATIVE_REGISTRY}/v2/"
  local display="Docker Hub 原生 (${DOCKER_HUB_NATIVE_REGISTRY})"

  local cache_ttl=1800
  local cache_key=""
  cache_key="$(st_cache_key "docker.native.speed|${endpoint}" 2>/dev/null)" || cache_key=""
  if [[ -n "${cache_key}" ]]; then
    local cached=""
    if cached="$(st_cache_read "${cache_ttl}" "${cache_key}" 2>/dev/null)" && [[ -n "${cached}" ]]; then
      printf '%s\n' "${cached%$'\n'}"
      return 0
    fi
  fi

  command -v curl &>/dev/null || {
    printf '9999.999\t000\t%s\n' "${display}"
    return 0
  }

  local result code total line
  result="$(curl -L -sS -o /dev/null -w '%{http_code} %{time_total}' \
    --connect-timeout 5 \
    --max-time 15 \
    "${endpoint}" 2>/dev/null || true)"

  code="${result%% *}"
  total="${result##* }"

  if [[ "${code}" == "200" || "${code}" == "401" ]]; then
    printf -v line '%s\t%s\t%s\n' "${total}" "${code}" "${display}"
  else
    printf -v line '9999.999\t%s\t%s\n' "${code:-000}" "${display}"
  fi

  if [[ -n "${cache_key}" ]]; then
    printf '%s' "${line}" | st_cache_write "${cache_key}" 2>/dev/null || true
  fi
  printf '%s' "${line}"
}


measure_mirrors_concurrent() {
  local concurrency="${DOCKER_MIRROR_SPEED_CONCURRENCY:-5}"
  [[ "${concurrency}" =~ ^[0-9]+$ ]] || concurrency=5
  ((concurrency > 0)) || concurrency=5

  local mirrors=("$@")
  ((${#mirrors[@]} > 0)) || return 0

  local tmp_dir
  tmp_dir="$(mktemp -d)" || fatal "创建测速临时目录失败。"

  # NOTE: trap 是当前 shell 级别的；为了不影响调用方，必须保存并在函数结束时恢复。
  # 避免用命令替换 $(trap -p ...) 保存 trap：命令替换在 subshell 中执行，trap 视图可能不同。
  local __st_trap_prev_return_file __st_trap_prev_int_file __st_trap_prev_term_file
  __st_trap_prev_return_file="${tmp_dir}/.trap_prev.RETURN"
  __st_trap_prev_int_file="${tmp_dir}/.trap_prev.INT"
  __st_trap_prev_term_file="${tmp_dir}/.trap_prev.TERM"
  trap -p | grep -E " RETURN$" >"${__st_trap_prev_return_file}" 2>/dev/null || true
  trap -p | grep -E " SIGINT$| INT$" >"${__st_trap_prev_int_file}" 2>/dev/null || true
  trap -p | grep -E " SIGTERM$| TERM$" >"${__st_trap_prev_term_file}" 2>/dev/null || true

  local __st_trap_had_return=0 __st_trap_had_int=0 __st_trap_had_term=0
  [[ -s "${__st_trap_prev_return_file}" ]] && __st_trap_had_return=1
  [[ -s "${__st_trap_prev_int_file}" ]] && __st_trap_had_int=1
  [[ -s "${__st_trap_prev_term_file}" ]] && __st_trap_had_term=1

  restore_measure_traps() {
    if (( __st_trap_had_return )); then
      # shellcheck source=/dev/null
      . "${__st_trap_prev_return_file}" || true
    else
      trap - RETURN
    fi

    if (( __st_trap_had_int )); then
      # shellcheck source=/dev/null
      . "${__st_trap_prev_int_file}" || true
    else
      trap - INT
    fi

    if (( __st_trap_had_term )); then
      # shellcheck source=/dev/null
      . "${__st_trap_prev_term_file}" || true
    else
      trap - TERM
    fi
  }

  cleanup_measure_tmp() {
    if [[ -n "${tmp_dir:-}" && -d "${tmp_dir}" ]]; then
      rm -rf "${tmp_dir}" 2>/dev/null || true
    fi
  }

  cleanup_measure_jobs() {
    local child_pid

    for child_pid in "${pids[@]:-}"; do
      if [[ -n "${child_pid}" ]] && kill -0 "${child_pid}" 2>/dev/null; then
        kill "${child_pid}" 2>/dev/null || true
      fi
    done

    for child_pid in "${pids[@]:-}"; do
      if [[ -n "${child_pid}" ]]; then
        wait "${child_pid}" 2>/dev/null || true
      fi
    done
  }

  # 函数级清理：正常结束、提前 return、或被中断时，确保临时目录不会遗留在 /tmp。
  # 这里不使用 `return`（尤其是在 RETURN trap 中），避免触发 RETURN trap 递归的边缘情况。
  trap '
    restore_measure_traps
    cleanup_measure_tmp
    :
  ' RETURN

  trap '
    restore_measure_traps
    cleanup_measure_jobs
    cleanup_measure_tmp
    kill -INT "$$"
  ' INT

  trap '
    restore_measure_traps
    cleanup_measure_jobs
    cleanup_measure_tmp
    kill -TERM "$$"
  ' TERM

  local pids=()
  local active=0
  local index=0
  local mirror pid

  for mirror in "${mirrors[@]}"; do
    (
      measure_mirror "${mirror}"
    ) >"${tmp_dir}/${index}.out" &

    pids+=("$!")
    active=$((active + 1))
    index=$((index + 1))

    if ((active >= concurrency)); then
      for pid in "${pids[@]}"; do
        wait "${pid}" || true
      done
      pids=()
      active=0
    fi
  done

  for pid in "${pids[@]}"; do
    wait "${pid}" || true
  done

  local i
  for ((i = 0; i < ${#mirrors[@]}; i++)); do
    if [[ -s "${tmp_dir}/${i}.out" ]]; then
      cat "${tmp_dir}/${i}.out"
    else
      printf '9999.999\t000\t%s\n' "${mirrors[$i]}"
    fi
  done

  # 正常路径下也主动清理并恢复 trap，避免函数返回后影响调用方。
  restore_measure_traps
  cleanup_measure_tmp
}


mirror_probe_failed() {
  local elapsed="$1"
  local http_code="${2:-}"

  if [[ "${elapsed}" == "9999.999" ]]; then
    return 0
  fi

  if [[ ! "${http_code}" =~ ^[0-9]{3}$ || "${http_code}" == "000" ]]; then
    return 0
  fi

  [[ "${http_code}" != "200" && "${http_code}" != "401" ]]
}


fetch_opsnote_mirrors() {
  local cache_ttl=21600
  local cache_key=""
  cache_key="$(st_cache_key "docker.opsnote.mirrors|${OPSNOTE_MIRROR_URL}" 2>/dev/null)" || cache_key=""
  if [[ -n "${cache_key}" ]] && st_cache_read "${cache_ttl}" "${cache_key}" 2>/dev/null; then
    return 0
  fi

  local tmp
  tmp="$(mktemp)" || return 1

  if fetch_url_quiet "${OPSNOTE_MIRROR_URL}" |
    grep -Eo 'https://[A-Za-z0-9._~:/?#@!%+=-]+' |
    sed 's#[),.，。]*$##' |
    while read -r mirror; do
      normalize_mirror_url "${mirror}" 2>/dev/null || true
    done |
    grep -Ev '(^https://tools\.opsnote\.top|github|githubusercontent|ghcr\.io|ghcr\.nju\.edu\.cn)' |
    sort -u >"${tmp}"; then
    cat "${tmp}"
    if [[ -n "${cache_key}" ]]; then
      st_cache_write "${cache_key}" <"${tmp}" 2>/dev/null || true
    fi
    rm -f "${tmp}" 2>/dev/null || true
    return 0
  fi

  rm -f "${tmp}" 2>/dev/null || true
  return 1
}


build_mirror_options() {
  local candidates=("${DOCKER_DEFAULT_MIRROR}")
  local fetched=()

  msg_info "正在拉取 OpsNote 可用镜像列表..." >&2
  if mapfile -t fetched < <(fetch_opsnote_mirrors 2>/dev/null); then
    :
  else
    fetched=()
  fi

  local mirror
  for mirror in "${fetched[@]}"; do
    [[ "${mirror}" == "${DOCKER_DEFAULT_MIRROR}" ]] && continue
    candidates+=("${mirror}")
    ((${#candidates[@]} >= 21)) && break
  done

  msg_info "正在测速候选镜像..." >&2
  local results=()
  mapfile -t results < <(measure_mirrors_concurrent "${candidates[@]}")

  printf '%s\n' "${results[@]}" | sort -n -k1,1
}

