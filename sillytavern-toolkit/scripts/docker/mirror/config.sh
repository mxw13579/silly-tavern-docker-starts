#!/usr/bin/env bash

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
