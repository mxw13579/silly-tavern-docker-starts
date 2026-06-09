#!/usr/bin/env bash

docker_daemon_json_path() {
  printf '%s\n' "${DOCKER_DAEMON_JSON_PATH:-/etc/docker/daemon.json}"
}

docker_json_python_cmd() {
  if command -v python3 &>/dev/null; then
    command -v python3
    return 0
  fi

  if command -v python &>/dev/null && python - <<'PY' &>/dev/null
import sys
raise SystemExit(0 if sys.version_info[0] >= 3 else 1)
PY
  then
    command -v python
    return 0
  fi

  return 1
}

validate_docker_mirror_url() {
  local mirror="${1:-}"
  local remainder=""
  local authority=""

  [[ -n "${mirror}" ]] || return 1
  [[ "${mirror}" != *[[:space:]]* ]] || return 1

  case "${mirror}" in
    http://*) remainder="${mirror#http://}" ;;
    https://*) remainder="${mirror#https://}" ;;
    *) return 1 ;;
  esac

  authority="${remainder%%/*}"
  authority="${authority%%\?*}"
  authority="${authority%%#*}"

  [[ -n "${authority}" ]] || return 1
  [[ "${authority}" != :* ]] || return 1
  [[ "${authority}" != *"@"* ]] || return 1
}

require_docker_mirror_url() {
  local mirror="$1"
  validate_docker_mirror_url "${mirror}" || fatal "Invalid Docker registry mirror URL: ${mirror}"
}

get_current_docker_mirrors() {
  local daemon_path="${1:-$(docker_daemon_json_path)}"
  [[ -f "${daemon_path}" ]] || return 0

  local python_cmd
  python_cmd="$(docker_json_python_cmd)" || return 1

  DOCKER_DAEMON_JSON_PATH="${daemon_path}" "${python_cmd}" <<'PY' 2>/dev/null
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse


def valid_registry_mirror_url(value):
    if not isinstance(value, str):
        return False
    if not value or value.strip() != value:
        return False
    if any(ch.isspace() or ord(ch) < 32 for ch in value):
        return False
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)


path = Path(os.environ.get("DOCKER_DAEMON_JSON_PATH", "/etc/docker/daemon.json"))
try:
    data = json.loads(path.read_text() or "{}")
except Exception:
    sys.exit(1)

mirrors = data.get("registry-mirrors")
if not isinstance(mirrors, list) or not mirrors:
    sys.exit(1)

for mirror in mirrors:
    if not valid_registry_mirror_url(mirror):
        sys.exit(1)

for mirror in mirrors:
    print(mirror)
PY
}

docker_registry_mirrors_configured() {
  local daemon_path="${1:-$(docker_daemon_json_path)}"
  local mirrors
  mirrors="$(get_current_docker_mirrors "${daemon_path}")" || return 1
  [[ -n "${mirrors}" ]]
}

show_docker_mirror_config() {
  msg_info "当前 Docker 镜像加速配置:"

  local mirrors_text=""
  if ! mirrors_text="$(get_current_docker_mirrors)"; then
    msg_warn "daemon.json 无效，或 registry-mirrors 不是非空有效 URL 数组。"
    return 0
  fi

  local mirrors=()
  mapfile -t mirrors <<<"${mirrors_text}"
  if [[ -z "${mirrors_text}" ]]; then
    mirrors=()
  fi

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

write_docker_mirrors() {
  local mirror="$1"
  require_docker_mirror_url "${mirror}"

  local daemon_path
  daemon_path="$(docker_daemon_json_path)"
  local backup_path
  backup_path="${daemon_path}.bak.$(date +%F_%H%M%S)"

  "${SUDO[@]}" mkdir -p "$(dirname -- "${daemon_path}")"
  if [[ -f "${daemon_path}" ]]; then
    "${SUDO[@]}" cp -a "${daemon_path}" "${backup_path}" || true
    msg_ok "已备份 Docker 配置到: ${backup_path}"
  fi

  local python_cmd=""
  if python_cmd="$(docker_json_python_cmd)"; then
    "${SUDO[@]}" env DOCKER_DAEMON_JSON_PATH="${daemon_path}" DOCKER_SELECTED_MIRROR="${mirror}" "${python_cmd}" <<'PY'
import json
import os
from datetime import datetime
from pathlib import Path

path = Path(os.environ.get("DOCKER_DAEMON_JSON_PATH", "/etc/docker/daemon.json"))
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
    if [[ -s "${daemon_path}" ]]; then
      fatal "python3 不存在且 daemon.json 已存在。为避免破坏已有配置，无法自动写入。"
    fi

    cat <<EOF | "${SUDO[@]}" tee "${daemon_path}" >/dev/null
{
  "registry-mirrors": [
    "${mirror}"
  ]
}
EOF
  fi
}

remove_docker_mirrors() {
  local daemon_path
  daemon_path="$(docker_daemon_json_path)"

  [[ -f "${daemon_path}" ]] || {
    msg_warn "未找到 /etc/docker/daemon.json。"
    return 0
  }

  local python_cmd
  python_cmd="$(docker_json_python_cmd)" || fatal "移除 registry-mirrors 需要 python3，以避免破坏 daemon.json 其他配置。"

  local backup_path
  backup_path="${daemon_path}.bak.$(date +%F_%H%M%S)"
  "${SUDO[@]}" cp -a "${daemon_path}" "${backup_path}" || true
  msg_ok "已备份 Docker 配置到: ${backup_path}"

  "${SUDO[@]}" env DOCKER_DAEMON_JSON_PATH="${daemon_path}" "${python_cmd}" <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ.get("DOCKER_DAEMON_JSON_PATH", "/etc/docker/daemon.json"))
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

configure_docker_mirror_safe() {
  if [[ "${USE_CHINA_MIRROR}" != "true" ]]; then
    msg_warn "非中国大陆服务器或地区检测失败，跳过 Docker 镜像加速配置。"
    return 0
  fi

  local daemon_path
  daemon_path="$(docker_daemon_json_path)"

  if docker_registry_mirrors_configured "${daemon_path}"; then
    msg_ok "Docker 镜像加速已配置，跳过修改。"
    return 0
  fi

  msg_info "配置 Docker 国内镜像加速..."
  require_docker_mirror_url "${DOCKER_DEFAULT_MIRROR}"
  "${SUDO[@]}" mkdir -p "$(dirname -- "${daemon_path}")"

  if [[ -f "${daemon_path}" ]]; then
    "${SUDO[@]}" cp -a "${daemon_path}" "${daemon_path}.bak.$(date +%F_%H%M%S)" || true
  fi

  local python_cmd=""
  if python_cmd="$(docker_json_python_cmd)"; then
    "${SUDO[@]}" env DOCKER_DAEMON_JSON_PATH="${daemon_path}" DOCKER_DEFAULT_MIRROR="${DOCKER_DEFAULT_MIRROR}" "${python_cmd}" <<'PY'
import json
import os
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse


def valid_registry_mirror_url(value):
    if not isinstance(value, str):
        return False
    if not value or value.strip() != value:
        return False
    if any(ch.isspace() or ord(ch) < 32 for ch in value):
        return False
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)

path = Path(os.environ.get("DOCKER_DAEMON_JSON_PATH", "/etc/docker/daemon.json"))
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
mirrors = [item for item in mirrors if valid_registry_mirror_url(item)]

if mirror not in mirrors:
    mirrors.insert(0, mirror)

data["registry-mirrors"] = mirrors
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
  else
    if [[ ! -s "${daemon_path}" ]]; then
      cat <<EOF | "${SUDO[@]}" tee "${daemon_path}" >/dev/null
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
