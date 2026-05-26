#!/usr/bin/env bash

DOCKER_DEFAULT_MIRROR="https://mirror.ccs.tencentyun.com"
DOCKER_HUB_NATIVE_REGISTRY="https://registry-1.docker.io"
OPSNOTE_MIRROR_URL="https://tools.opsnote.top/registry-mirrors/"
DOCKER_MIRROR_SPEED_CONCURRENCY="${DOCKER_MIRROR_SPEED_CONCURRENCY:-5}"
DOCKER_MIRROR_MENU_SEP="----------------------------------------------------------"

print_docker_mirror_menu_header() {
  local title="${1:-Docker 镜像加速器管理}"
  local description="${2:-候选源来自固定推荐项和 OpsNote 监控页，写入前会要求确认。}"

  clear || true
  echo "${DOCKER_MIRROR_MENU_SEP}"
  echo "SillyTavern Docker 工具箱 | FuFu API | 群 1019836466"
  echo "${DOCKER_MIRROR_MENU_SEP}"
  echo "${title}"
  echo "${description}"
  echo "${DOCKER_MIRROR_MENU_SEP}"
}

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

get_current_docker_mirrors() {
  [[ -f /etc/docker/daemon.json ]] || return 0

  if command -v python3 &>/dev/null; then
    python3 <<'PY' 2>/dev/null || true
import json
from pathlib import Path

path = Path("/etc/docker/daemon.json")
try:
    data = json.loads(path.read_text() or "{}")
except Exception:
    data = {}

mirrors = data.get("registry-mirrors", [])
if isinstance(mirrors, list):
    for mirror in mirrors:
        if isinstance(mirror, str):
            print(mirror)
PY
  else
    grep -Eo '"https://[^"]+"' /etc/docker/daemon.json 2>/dev/null | tr -d '"' || true
  fi
}

show_docker_mirror_config() {
  msg_info "当前 Docker 镜像加速配置:"

  local mirrors=()
  mapfile -t mirrors < <(get_current_docker_mirrors)

  if ((${#mirrors[@]} == 0)); then
    msg_warn "未配置 registry-mirrors。"
    return 0
  fi

  local index=1 mirror
  for mirror in "${mirrors[@]}"; do
    printf '   %d. %s\n' "${index}" "${mirror}"
    index=$((index + 1))
  done
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

print_mirror_speed_result() {
  local result="$1"
  local time code mirror

  IFS=$'\t' read -r time code mirror <<<"${result}"
  if [[ "${time}" == "9999.999" ]]; then
    printf '%-8s %-4s %s\n' "失败" "${code}" "${mirror}"
  else
    printf '%-9s %-4s %s\n' "${time}s" "${code}" "${mirror}"
  fi
}

print_mirror_http_hint() {
  msg_info "说明：HTTP 401 表示 Docker Registry /v2/ 可达但未认证，通常代表网络可达。"
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

speed_test_current_mirrors() {
  local mirrors=()
  mapfile -t mirrors < <(get_current_docker_mirrors)

  if ((${#mirrors[@]} == 0)); then
    msg_warn "当前未配置 Docker 镜像加速器，将测试原生 Docker Hub 访问。"
    print_mirror_http_hint
    printf '%-9s %-4s %s\n' "耗时" "HTTP" "地址"
    print_mirror_speed_result "$(measure_docker_hub_native)"
    return 0
  fi

  msg_info "正在测速当前 registry-mirrors..."
  print_mirror_http_hint
  printf '%-9s %-4s %s\n' "耗时" "HTTP" "地址"

  local mirror normalized result
  local valid_mirrors=()
  for mirror in "${mirrors[@]}"; do
    if normalized="$(normalize_mirror_url "${mirror}")"; then
      valid_mirrors+=("${normalized}")
    else
      printf '%-8s %-4s %s\n' "无效" "-" "${mirror}"
    fi
  done

  while IFS= read -r result; do
    [[ -n "${result}" ]] || continue
    print_mirror_speed_result "${result}"
  done < <(measure_mirrors_concurrent "${valid_mirrors[@]}")
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

mirror_menu_label() {
  local mirror="$1"
  local rank="$2"
  local label="${mirror#https://}"

  if [[ "${mirror}" == "${DOCKER_DEFAULT_MIRROR}" ]]; then
    if [[ "${rank}" == "1" ]]; then
      label="腾讯云（默认，最快）"
    else
      label="腾讯云（默认）"
    fi
  elif [[ "${rank}" == "1" ]]; then
    label="${label}（最快）"
  fi

  printf '%s\n' "${label}"
}

write_docker_mirrors() {
  local mirror="$1"
  local backup_path="/etc/docker/daemon.json.bak.$(date +%F_%H%M%S)"

  "${SUDO[@]}" mkdir -p /etc/docker
  if [[ -f /etc/docker/daemon.json ]]; then
    "${SUDO[@]}" cp -a /etc/docker/daemon.json "${backup_path}" || true
    msg_ok "已备份 Docker 配置到: ${backup_path}"
  fi

  if command -v python3 &>/dev/null; then
    "${SUDO[@]}" env DOCKER_SELECTED_MIRROR="${mirror}" python3 <<'PY'
import json
import os
from datetime import datetime
from pathlib import Path

path = Path("/etc/docker/daemon.json")
mirror = os.environ["DOCKER_SELECTED_MIRROR"]
data = {}

if path.exists() and path.read_text().strip():
    try:
        data = json.loads(path.read_text())
    except Exception:
        backup = path.with_name(f"daemon.json.invalid.{datetime.now().strftime('%Y-%m-%d_%H%M%S')}")
        backup.write_text(path.read_text())
        data = {}

data["registry-mirrors"] = [mirror]
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
  else
    if [[ -s /etc/docker/daemon.json ]]; then
      fatal "python3 不存在且 daemon.json 已存在。为避免破坏已有配置，无法自动写入。"
    fi

    cat <<EOF | "${SUDO[@]}" tee /etc/docker/daemon.json >/dev/null
{
  "registry-mirrors": [
    "${mirror}"
  ]
}
EOF
  fi
}

remove_docker_mirrors() {
  [[ -f /etc/docker/daemon.json ]] || {
    msg_warn "未找到 /etc/docker/daemon.json。"
    return 0
  }

  command -v python3 &>/dev/null || fatal "移除 registry-mirrors 需要 python3，以避免破坏 daemon.json 其他配置。"

  local backup_path="/etc/docker/daemon.json.bak.$(date +%F_%H%M%S)"
  "${SUDO[@]}" cp -a /etc/docker/daemon.json "${backup_path}" || true
  msg_ok "已备份 Docker 配置到: ${backup_path}"

  "${SUDO[@]}" python3 <<'PY'
import json
from pathlib import Path

path = Path("/etc/docker/daemon.json")
try:
    data = json.loads(path.read_text() or "{}")
except Exception as exc:
    raise SystemExit(f"daemon.json 不是有效 JSON: {exc}")

data.pop("registry-mirrors", None)
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
}

confirm_docker_restart() {
  ensure_interactive_tty

  local answer=""
  msg_warn "修改 Docker daemon.json 后需要重启 Docker 才会生效。"
  read -r -p "是否现在重启 Docker 服务？(y/n): " answer </dev/tty

  case "${answer}" in
    [Yy]*) restart_docker_service ;;
    *) msg_warn "已跳过重启。请稍后手动重启 Docker。" ;;
  esac
}

find_latest_daemon_json_backup() {
  local latest=""

  # 仅恢复最近一次 /etc/docker/daemon.json.bak.*（按 mtime 最新）。
  # BusyBox/Alpine 兼容：避免依赖 GNU find 的 -printf，也避免解析 ls 输出。
  if stat -c '%Y %n' /dev/null >/dev/null 2>&1; then
    latest="$(
      find /etc/docker -maxdepth 1 -type f -name 'daemon.json.bak.*' \
        -exec stat -c '%Y %n' {} \; 2>/dev/null \
        | sort -nr 2>/dev/null \
        | awk 'NR==1{print $2}' \
        || true
    )"
  elif stat -f '%m %N' /dev/null >/dev/null 2>&1; then
    # BSD/macOS stat 兼容分支
    latest="$(
      find /etc/docker -maxdepth 1 -type f -name 'daemon.json.bak.*' \
        -exec stat -f '%m %N' {} \; 2>/dev/null \
        | sort -nr 2>/dev/null \
        | awk 'NR==1{print $2}' \
        || true
    )"
  else
    # 极保守兜底：若没有可用的 stat 格式化能力，退化为按名称字典序找最新备份。
    # 本项目备份命名使用 YYYY-MM-DD_HHMMSS，字典序与时间序一致。
    latest="$(
      find /etc/docker -maxdepth 1 -type f -name 'daemon.json.bak.*' -print 2>/dev/null \
        | sort -r 2>/dev/null \
        | awk 'NR==1{print $0}' \
        || true
    )"
  fi
  printf '%s\n' "${latest}"
}

validate_json_file() {
  local path="$1"

  [[ -f "${path}" ]] || return 1
  [[ -s "${path}" ]] || return 1

  if command -v python3 &>/dev/null; then
    python3 - "${path}" <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    json.load(f)
PY
    return
  fi

  if command -v jq &>/dev/null; then
    jq -e . "${path}" >/dev/null 2>&1
    return
  fi

  # 恢复 daemon.json 备份属于高风险操作：无 python3/jq 时无法做可靠 JSON 校验，直接拒绝。
  return 1
}

restore_latest_daemon_json_backup_interactive() {
  ensure_interactive_tty

  if ! command -v python3 &>/dev/null && ! command -v jq &>/dev/null; then
    fatal "恢复 /etc/docker/daemon.json 备份需要真实 JSON 解析器（python3 或 jq）。当前未检测到 python3/jq。请先安装 python3 或 jq 后重试。"
  fi

  local latest_backup=""
  latest_backup="$(find_latest_daemon_json_backup)"

  if [[ -z "${latest_backup}" ]]; then
    msg_warn "未找到可恢复的备份文件：/etc/docker/daemon.json.bak.*"
    return 0
  fi

  msg_info "检测到最近一次 Docker 配置备份：${latest_backup}"

  if ! validate_json_file "${latest_backup}"; then
    fatal "备份文件不是有效 JSON：${latest_backup}"
  fi

  local answer=""
  read -r -p "确认使用该备份覆盖 /etc/docker/daemon.json？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*) ;;
    *) msg_warn "已取消恢复。"; return 0 ;;
  esac

  "${SUDO[@]}" mkdir -p /etc/docker

  local pre_restore_backup="/etc/docker/daemon.json.pre_restore.$(date +%F_%H%M%S)"
  local pre_restore_missing=0
  if [[ -f /etc/docker/daemon.json ]]; then
    run_quiet "备份当前 Docker 配置" "${SUDO[@]}" cp -a /etc/docker/daemon.json "${pre_restore_backup}" \
      || fatal "备份当前 /etc/docker/daemon.json 失败，已中止恢复。"
  else
    pre_restore_missing=1
    # 注意：不能 cp /dev/null（可能会尝试创建字符设备）；这里用 shell 重定向创建空文件作为占位。
    run_quiet "备份当前 Docker 配置(不存在则创建占位备份)" "${SUDO[@]}" sh -c ": >\"${pre_restore_backup}\"" \
      || fatal "创建 pre-restore 占位备份失败，已中止恢复。"
  fi
  msg_ok "已备份恢复前 Docker 配置到: ${pre_restore_backup}"

  run_quiet "恢复 Docker daemon.json" "${SUDO[@]}" cp -a "${latest_backup}" /etc/docker/daemon.json \
    || fatal "恢复失败：无法覆盖写入 /etc/docker/daemon.json。"
  msg_ok "已恢复 Docker 配置：${latest_backup} -> /etc/docker/daemon.json"

  msg_warn "修改 Docker daemon.json 后需要重启 Docker 才会生效。"
  read -r -p "是否现在重启 Docker 服务？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*)
      if restart_docker_service_restore; then
        msg_ok "Docker 服务已重启，恢复的配置已生效。"
        return 0
      fi

      msg_error "Docker 重启失败，将自动回滚到恢复前配置并再尝试重启一次..."
      if ((pre_restore_missing == 1)); then
        run_quiet "回滚 Docker 配置(恢复前无 daemon.json，移除当前文件)" "${SUDO[@]}" rm -f /etc/docker/daemon.json \
          || fatal "Docker 重启失败，且回滚操作失败：无法移除 /etc/docker/daemon.json。请手动处理。"
      else
        run_quiet "回滚 Docker 配置" "${SUDO[@]}" cp -a "${pre_restore_backup}" /etc/docker/daemon.json \
          || fatal "Docker 重启失败，且回滚操作失败：无法恢复 ${pre_restore_backup} -> /etc/docker/daemon.json。请手动处理。"
      fi

      if restart_docker_service_restore; then
        msg_warn "已回滚到恢复前配置并重启成功；本次恢复的 daemon.json 未生效。"
        return 0
      fi

      fatal "Docker 重启失败：已尝试回滚到恢复前配置并再次重启，但仍失败。请检查 /etc/docker/daemon.json（当前为回滚后的配置）并手动排查。参考备份：${latest_backup}（尝试恢复的备份）与 ${pre_restore_backup}（恢复前备份）。"
      ;;
    *)
      msg_warn "已跳过重启。当前 /etc/docker/daemon.json 尚未验证；请稍后手动重启 Docker 并确认服务状态正常。"
      ;;
  esac
}

select_docker_mirror_interactive() {
  ensure_interactive_tty

  local sorted=()
  mapfile -t sorted < <(build_mirror_options)

  local menu_mirrors=()
  local menu_results=()
  local menu_labels=()
  local failed_results=()
  local result time code mirror

  for result in "${sorted[@]}"; do
    IFS=$'\t' read -r time code mirror <<<"${result}"
    if mirror_probe_failed "${time}" "${code}"; then
      failed_results+=("${result}")
      continue
    fi

    if ((${#menu_mirrors[@]} < 6)); then
      menu_mirrors+=("${mirror}")
      menu_results+=("${result}")
      menu_labels+=("$(mirror_menu_label "${mirror}" "${#menu_mirrors[@]}")")
    fi
  done

  print_docker_mirror_menu_header "选择 Docker Hub 镜像加速器" "按本次测速结果排序；写入前会再次确认。"
  print_mirror_http_hint
  if ((${#menu_mirrors[@]} == 0)); then
    msg_warn "本次未发现测速成功的候选镜像，可选择自定义输入。"
  fi

  local i label display_time display_code
  for i in "${!menu_mirrors[@]}"; do
    IFS=$'\t' read -r display_time display_code mirror <<<"${menu_results[$i]}"
    display_time="${display_time}s"
    label="${menu_labels[$i]}"

    printf '%2d. %-28s %-10s HTTP %-3s %s\n' "$((i + 1))" "${label}" "${display_time}" "${display_code}" "${menu_mirrors[$i]}"
  done

  if ((${#failed_results[@]} > 0)); then
    echo
    echo "不可用候选（本次不推荐）："
    for result in "${failed_results[@]}"; do
      IFS=$'\t' read -r _ display_code mirror <<<"${result}"
      label="$(mirror_menu_label "${mirror}" "-")"
      printf '    %-28s %-10s HTTP %-3s %s\n' "${label}" "失败" "${display_code}" "${mirror}"
    done
  fi

  local custom_index cancel_index
  custom_index=$((${#menu_mirrors[@]} + 1))
  cancel_index=0
  printf '%2d. 自定义输入\n' "${custom_index}"
  printf '%2d. 取消\n' "${cancel_index}"

  local choice selected=""
  while true; do
    read -r -p "请输入选项 [0-${custom_index}]: " choice </dev/tty
    if [[ "${choice}" == "0" ]]; then
      msg_warn "已取消。"
      return 0
    elif [[ "${choice}" == "${custom_index}" ]]; then
      read -r -p "请输入自定义 HTTPS 镜像加速器地址: " selected </dev/tty
      selected="$(normalize_mirror_url "${selected}")" || {
        msg_warn "地址格式无效，必须是 HTTPS URL，且不能包含空格或 shell 特殊字符。"
        continue
      }
      break
    elif [[ "${choice}" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#menu_mirrors[@]})); then
      selected="${menu_mirrors[$((choice - 1))]}"
      break
    else
      msg_warn "无效选项。"
    fi
  done

  echo
  msg_info "已选择: ${selected}"
  local selected_result selected_time selected_code
  selected_result="$(measure_mirror "${selected}")"
  print_mirror_speed_result "${selected_result}"
  IFS=$'\t' read -r selected_time selected_code _ <<<"${selected_result}"

  local answer=""
  if mirror_probe_failed "${selected_time}" "${selected_code}"; then
    msg_warn "该镜像本次测速失败，默认不会写入。HTTP ${selected_code:-000} 通常表示该地址当前不可用或无法完成 /v2/ 探测。"
    read -r -p "如仍要写入，请输入 yes 或 YES: " answer </dev/tty
    if [[ "${answer}" != "yes" && "${answer}" != "YES" ]]; then
      msg_warn "已取消写入。"
      return 0
    fi
  else
    read -r -p "确认写入 /etc/docker/daemon.json？(y/n): " answer </dev/tty
    case "${answer}" in
      [Yy]*) ;;
      *)
        msg_warn "已取消写入。"
        return 0
        ;;
    esac
  fi

  write_docker_mirrors "${selected}"
  msg_ok "Docker 镜像加速器已更新为: ${selected}"
  confirm_docker_restart
}

remove_docker_mirrors_interactive() {
  ensure_interactive_tty
  show_docker_mirror_config

  local answer=""
  read -r -p "确认移除 registry-mirrors 配置？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*)
      remove_docker_mirrors
      msg_ok "Docker 镜像加速器配置已移除。"
      confirm_docker_restart
      ;;
    *)
      msg_warn "已取消。"
      ;;
  esac
}

docker_mirror_menu() {
  ensure_interactive_tty

  local choice=""
  while true; do
    print_docker_mirror_menu_header
    show_docker_mirror_config
    echo "${DOCKER_MIRROR_MENU_SEP}"
    echo "   1. 查看当前配置"
    echo "   2. 测速当前配置"
    echo "   3. 选择/更换镜像加速器"
    echo "   4. 移除镜像加速器"
    echo "   0. 返回"
    echo "${DOCKER_MIRROR_MENU_SEP}"
    read -r -p "请输入选项 [0-4]: " choice </dev/tty

    case "${choice}" in
      1) show_docker_mirror_config; pause_to_continue ;;
      2) speed_test_current_mirrors; pause_to_continue ;;
      3) select_docker_mirror_interactive; pause_to_continue ;;
      4) remove_docker_mirrors_interactive; pause_to_continue ;;
      0) break ;;
      *) msg_warn "无效选项。"; pause_to_continue ;;
    esac
  done
}

configure_docker_mirror_safe() {
  if [[ "${USE_CHINA_MIRROR}" != "true" ]]; then
    msg_warn "非中国大陆服务器或地区检测失败，跳过 Docker 镜像加速配置。"
    return 0
  fi

  if [[ -f /etc/docker/daemon.json ]] && grep -q '"registry-mirrors"' /etc/docker/daemon.json; then
    msg_ok "Docker 镜像加速已配置，跳过修改。"
    return 0
  fi

  msg_info "配置 Docker 国内镜像加速..."
  "${SUDO[@]}" mkdir -p /etc/docker

  if [[ -f /etc/docker/daemon.json ]]; then
    "${SUDO[@]}" cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%F_%H%M%S)" || true
  fi

  if command -v python3 &>/dev/null; then
    "${SUDO[@]}" env DOCKER_DEFAULT_MIRROR="${DOCKER_DEFAULT_MIRROR}" python3 <<'PY'
import json
import os
from datetime import datetime
from pathlib import Path

path = Path("/etc/docker/daemon.json")
mirror = os.environ["DOCKER_DEFAULT_MIRROR"]
data = {}

if path.exists() and path.read_text().strip():
    try:
        data = json.loads(path.read_text())
    except Exception:
        backup = path.with_name(f"daemon.json.invalid.{datetime.now().strftime('%Y-%m-%d_%H%M%S')}")
        backup.write_text(path.read_text())
        data = {}

mirrors = data.get("registry-mirrors", [])
if not isinstance(mirrors, list):
    mirrors = []

if mirror not in mirrors:
    mirrors.insert(0, mirror)

data["registry-mirrors"] = mirrors
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
  else
    if [[ ! -s /etc/docker/daemon.json ]]; then
      cat <<EOF | "${SUDO[@]}" tee /etc/docker/daemon.json >/dev/null
{
  "registry-mirrors": [
    "${DOCKER_DEFAULT_MIRROR}"
  ]
}
EOF
    else
      msg_warn "python3 不存在且 daemon.json 已存在，为避免覆盖，跳过 Docker 镜像加速自动合并。"
      return 0
    fi
  fi

  restart_docker_service
  msg_ok "Docker 镜像加速配置完成。"
}
