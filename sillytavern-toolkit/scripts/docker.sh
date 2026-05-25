#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  ST_TOOLKIT_REQUIRE_SUDO=0
  ST_TOOLKIT_SKIP_COUNTRY=1
fi

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DOCKER_DEFAULT_MIRROR="https://mirror.ccs.tencentyun.com"
OPSNOTE_MIRROR_URL="https://tools.opsnote.top/registry-mirrors/"

install_docker_debian_fallback() {
  msg_warn "尝试使用系统源安装 Docker 作为兜底方案..."
  "${SUDO[@]}" rm -f /etc/apt/sources.list.d/docker.list || true
  ensure_apt_ready_debian

  if run_quiet "安装系统源 Docker" "${SUDO[@]}" apt-get install -y docker.io docker-compose-plugin; then
    return 0
  fi

  if run_quiet "安装系统源 Docker 与 docker-compose" "${SUDO[@]}" apt-get install -y docker.io docker-compose; then
    return 0
  fi

  fatal "Docker 官方源和系统源安装均失败。"
}

install_docker_debian() {
  msg_info "安装 Docker..."
  install_base_packages

  local docker_repo_url="https://download.docker.com"
  if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
    docker_repo_url="https://mirrors.cloud.tencent.com/docker-ce"
  fi

  run_quiet "移除旧 Docker 包" "${SUDO[@]}" apt-get remove -y docker docker-engine docker.io containerd runc || true

  "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
  "${SUDO[@]}" rm -f /etc/apt/keyrings/docker.gpg

  local tmp_gpg codename
  tmp_gpg="$(mktemp)"

  if ! fetch_url_quiet "${docker_repo_url}/linux/${DOCKER_REPO_OS}/gpg" >"${tmp_gpg}"; then
    rm -f "${tmp_gpg}"
    install_docker_debian_fallback
    return 0
  fi

  if ! "${SUDO[@]}" gpg --dearmor -o /etc/apt/keyrings/docker.gpg "${tmp_gpg}" >/dev/null 2>&1; then
    rm -f "${tmp_gpg}"
    install_docker_debian_fallback
    return 0
  fi

  rm -f "${tmp_gpg}"
  "${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.gpg

  codename="$(get_docker_apt_codename)"
  [[ -n "${codename}" ]] || {
    install_docker_debian_fallback
    return 0
  }

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${docker_repo_url}/linux/${DOCKER_REPO_OS} ${codename} stable" \
    | "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null

  if ! run_quiet "刷新 Docker APT 源" "${SUDO[@]}" apt-get update -o Acquire::Retries=3; then
    install_docker_debian_fallback
    return 0
  fi

  if ! run_quiet "安装 Docker" "${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    install_docker_debian_fallback
    return 0
  fi
}

install_docker_redhat_fallback() {
  msg_warn "尝试使用系统源安装 Docker 作为兜底方案..."
  "${SUDO[@]}" rm -f /etc/yum.repos.d/docker-ce.repo || true
  run_quiet "刷新软件源缓存" "${SUDO[@]}" "${PKG_MANAGER}" makecache || true

  if run_quiet "安装系统源 Docker" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker docker-compose-plugin; then
    return 0
  fi

  if run_quiet "安装系统源 Docker 与 docker-compose" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker docker-compose; then
    return 0
  fi

  fatal "Docker 官方源和系统源安装均失败。"
}

install_docker_redhat() {
  msg_info "安装 Docker..."
  install_base_packages

  local repo_url=""
  case "${OS}" in
    fedora)
      repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
      [[ "${USE_CHINA_MIRROR}" == "true" ]] && repo_url="https://mirrors.cloud.tencent.com/docker-ce/linux/fedora/docker-ce.repo"
      ;;
    *)
      repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
      [[ "${USE_CHINA_MIRROR}" == "true" ]] && repo_url="https://mirrors.cloud.tencent.com/docker-ce/linux/centos/docker-ce.repo"
      ;;
  esac

  run_quiet "移除旧 Docker 包" "${SUDO[@]}" "${PKG_MANAGER}" remove -y \
    docker docker-client docker-client-latest docker-common docker-latest \
    docker-latest-logrotate docker-logrotate docker-engine || true

  local tmp_repo
  tmp_repo="$(mktemp)"

  if ! safe_curl_download -o "${tmp_repo}" "${repo_url}"; then
    rm -f "${tmp_repo}"
    install_docker_redhat_fallback
    return 0
  fi

  "${SUDO[@]}" mkdir -p /etc/yum.repos.d
  "${SUDO[@]}" cp "${tmp_repo}" /etc/yum.repos.d/docker-ce.repo
  rm -f "${tmp_repo}"

  if ! run_quiet "刷新 Docker 软件源缓存" "${SUDO[@]}" "${PKG_MANAGER}" makecache; then
    install_docker_redhat_fallback
    return 0
  fi

  if ! run_quiet "安装 Docker" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    install_docker_redhat_fallback
    return 0
  fi
}

install_docker_arch() {
  install_base_packages
  run_quiet "安装 Docker" "${SUDO[@]}" pacman -S --noconfirm docker docker-compose
}

install_docker_alpine() {
  install_base_packages

  if ! run_quiet "安装 Docker" "${SUDO[@]}" apk add --no-cache docker docker-cli-compose; then
    run_quiet "安装 Docker" "${SUDO[@]}" apk add --no-cache docker docker-compose
  fi
}

install_docker_suse() {
  install_base_packages
  run_quiet "安装 Docker" "${SUDO[@]}" zypper --non-interactive install docker docker-compose
}

ensure_docker_running() {
  if "${SUDO[@]}" docker info &>/dev/null; then
    return 0
  fi

  case "${INIT_SYSTEM}" in
    systemd)
      run_quiet "启动 Docker 服务" "${SUDO[@]}" systemctl enable --now docker || fatal "Docker 启动失败。"
      ;;
    openrc)
      "${SUDO[@]}" rc-update add docker boot || true
      run_quiet "启动 Docker 服务" "${SUDO[@]}" rc-service docker start || fatal "Docker 启动失败。"
      ;;
    *)
      fatal "当前环境没有 systemd/openrc，且 Docker 未运行。请手动启动 Docker 后重试。"
      ;;
  esac

  "${SUDO[@]}" docker info &>/dev/null || fatal "Docker 未正常运行。"
}

restart_docker_service() {
  command -v docker &>/dev/null || fatal "Docker 未安装，无法重启。"

  case "${INIT_SYSTEM}" in
    systemd)
      "${SUDO[@]}" systemctl daemon-reload || true
      run_quiet "重启 Docker 服务" "${SUDO[@]}" systemctl restart docker
      ;;
    openrc)
      run_quiet "重启 Docker 服务" "${SUDO[@]}" rc-service docker restart
      ;;
    *)
      fatal "当前环境没有 systemd/openrc，请手动重启 Docker。"
      ;;
  esac
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
    printf '%s\t%s\t%s\n' "${total}" "${code}" "${mirror}"
  else
    printf '9999.999\t%s\t%s\n' "${code:-000}" "${mirror}"
  fi
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

speed_test_current_mirrors() {
  local mirrors=()
  mapfile -t mirrors < <(get_current_docker_mirrors)

  if ((${#mirrors[@]} == 0)); then
    msg_warn "当前未配置 Docker 镜像加速器。"
    return 0
  fi

  msg_info "正在测速当前 registry-mirrors..."
  printf '%-9s %-4s %s\n' "耗时" "HTTP" "地址"

  local mirror normalized result
  for mirror in "${mirrors[@]}"; do
    if normalized="$(normalize_mirror_url "${mirror}")"; then
      result="$(measure_mirror "${normalized}")"
      print_mirror_speed_result "${result}"
    else
      printf '%-8s %-4s %s\n' "无效" "-" "${mirror}"
    fi
  done
}

fetch_opsnote_mirrors() {
  fetch_url_quiet "${OPSNOTE_MIRROR_URL}" |
    grep -Eo 'https://[A-Za-z0-9._~:/?#@!%+=-]+' |
    sed 's#[),.，。]*$##' |
    while read -r mirror; do
      normalize_mirror_url "${mirror}" 2>/dev/null || true
    done |
    grep -Ev '(^https://tools\.opsnote\.top|github|githubusercontent|ghcr\.io|ghcr\.nju\.edu\.cn)' |
    sort -u
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
  for mirror in "${candidates[@]}"; do
    results+=("$(measure_mirror "${mirror}")")
  done

  printf '%s\n' "${results[@]}" | sort -n -k1,1
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

select_docker_mirror_interactive() {
  ensure_interactive_tty

  local sorted=()
  mapfile -t sorted < <(build_mirror_options)

  local menu_mirrors=("${DOCKER_DEFAULT_MIRROR}")
  local menu_results=()
  local default_result result time code mirror

  default_result="$(printf '%s\n' "${sorted[@]}" | awk -F'\t' -v mirror="${DOCKER_DEFAULT_MIRROR}" '$3 == mirror { print; exit }')"
  [[ -n "${default_result}" ]] || default_result="$(measure_mirror "${DOCKER_DEFAULT_MIRROR}")"
  menu_results+=("${default_result}")

  for result in "${sorted[@]}"; do
    IFS=$'\t' read -r time code mirror <<<"${result}"
    [[ "${mirror}" == "${DOCKER_DEFAULT_MIRROR}" ]] && continue
    [[ "${time}" == "9999.999" ]] && continue
    menu_mirrors+=("${mirror}")
    menu_results+=("${result}")
    ((${#menu_mirrors[@]} >= 6)) && break
  done

  echo
  echo "请选择 Docker Hub 镜像加速器："

  local i label display_time display_code
  for i in "${!menu_mirrors[@]}"; do
    IFS=$'\t' read -r display_time display_code mirror <<<"${menu_results[$i]}"
    if [[ "${display_time}" == "9999.999" ]]; then
      display_time="失败"
    else
      display_time="${display_time}s"
    fi

    label="${menu_mirrors[$i]}"
    if ((i == 0)); then
      label="腾讯云（推荐）"
    fi

    printf '%2d. %-18s %-8s %s\n' "$((i + 1))" "${label}" "${display_time}" "${menu_mirrors[$i]}"
  done

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
  print_mirror_speed_result "$(measure_mirror "${selected}")"

  local answer=""
  read -r -p "确认写入 /etc/docker/daemon.json？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*)
      write_docker_mirrors "${selected}"
      msg_ok "Docker 镜像加速器已更新为: ${selected}"
      confirm_docker_restart
      ;;
    *)
      msg_warn "已取消写入。"
      ;;
  esac
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
    clear || true
    echo "--- Docker 镜像加速器管理 ---"
    echo "候选源来自固定推荐项和 OpsNote 监控页，写入前会要求确认。"
    echo "---------------------------------------------------"
    show_docker_mirror_config
    echo "---------------------------------------------------"
    echo "   1. 查看当前配置"
    echo "   2. 测速当前配置"
    echo "   3. 选择/更换镜像加速器"
    echo "   4. 移除镜像加速器"
    echo "   0. 返回"
    echo "---------------------------------------------------"
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

install_or_verify_docker() {
  msg_info "检查 Docker..."

  if ! command -v docker &>/dev/null; then
    case "${OS_FAMILY}" in
      debian) install_docker_debian ;;
      redhat) install_docker_redhat ;;
      arch) install_docker_arch ;;
      alpine) install_docker_alpine ;;
      suse) install_docker_suse ;;
      *) fatal "不支持的系统系列: ${OS_FAMILY}" ;;
    esac
  else
    msg_ok "Docker 已安装，跳过安装。"
  fi

  command -v docker &>/dev/null || fatal "Docker 安装失败。"
  ensure_docker_running
  configure_docker_mirror_safe
  ensure_docker_running
}

setup_docker_compose() {
  msg_info "检查 Docker Compose..."

  if detect_compose_cmd; then
    msg_ok "Compose 命令: ${COMPOSE_CMD[*]}"
    return 0
  fi

  msg_warn "未检测到 Docker Compose，尝试安装..."

  case "${OS_FAMILY}" in
    debian)
      ensure_apt_ready_debian
      if ! run_quiet "安装 Docker Compose 插件" "${SUDO[@]}" apt-get install -y docker-compose-plugin; then
        run_quiet "安装 docker-compose" "${SUDO[@]}" apt-get install -y docker-compose
      fi
      ;;
    redhat)
      run_quiet "安装 Docker Compose 插件" "${SUDO[@]}" "${PKG_MANAGER}" install -y docker-compose-plugin
      ;;
    arch)
      run_quiet "安装 Docker Compose" "${SUDO[@]}" pacman -S --noconfirm docker-compose
      ;;
    alpine)
      if ! run_quiet "安装 Docker Compose" "${SUDO[@]}" apk add --no-cache docker-cli-compose; then
        run_quiet "安装 Docker Compose" "${SUDO[@]}" apk add --no-cache docker-compose
      fi
      ;;
    suse)
      run_quiet "安装 Docker Compose" "${SUDO[@]}" zypper --non-interactive install docker-compose
      ;;
  esac

  detect_compose_cmd || fatal "Docker Compose 安装失败。"
  msg_ok "Compose 命令: ${COMPOSE_CMD[*]}"
}

list_docker_images() {
  command -v docker &>/dev/null || fatal "Docker 未安装，无法查看镜像。"
  "${SUDO[@]}" docker images
}

status_docker() {
  echo -n "   Docker 环境: "
  if ! command -v docker &>/dev/null; then
    echo -e "${C_RED}未安装${C_RESET}"
    return 0
  fi

  local version=""
  version="$(docker -v 2>/dev/null | awk '{print $3}' | sed 's/,//' || true)"

  if "${SUDO[@]}" docker info &>/dev/null; then
    echo -e "${C_GREEN}已安装 (v${version:-未知}) 且正在运行${C_RESET}"
  else
    echo -e "${C_YELLOW}已安装 (v${version:-未知}) 但未运行或当前用户无权限${C_RESET}"
  fi

  if detect_compose_cmd; then
    echo -e "     └─ Compose: ${C_GREEN}${COMPOSE_CMD[*]}${C_RESET}"
  else
    echo -e "     └─ Compose: ${C_YELLOW}未检测到${C_RESET}"
  fi

  if [[ -f /etc/docker/daemon.json ]] && grep -q "registry-mirrors" /etc/docker/daemon.json; then
    echo -e "     └─ 镜像加速: ${C_GREEN}已配置${C_RESET}"
  else
    echo -e "     └─ 镜像加速: ${C_YELLOW}未配置${C_RESET}"
  fi
}

usage() {
  msg_error "用法: $0 {install|compose|config_mirror|mirror_menu|mirror_status|mirror_speed|restart_service|list_images|status}"
}

case "${1:-}" in
  install)
    install_or_verify_docker
    setup_docker_compose
    ;;
  compose)
    setup_docker_compose
    ;;
  config_mirror)
    configure_docker_mirror_safe
    ;;
  mirror_menu)
    docker_mirror_menu
    ;;
  mirror_status)
    show_docker_mirror_config
    ;;
  mirror_speed)
    speed_test_current_mirrors
    ;;
  restart_service)
    restart_docker_service
    ;;
  list_images)
    list_docker_images
    ;;
  status)
    status_docker
    ;;
  *)
    usage
    exit 1
    ;;
esac
