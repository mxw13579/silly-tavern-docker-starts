#!/usr/bin/env bash

debian_components() {
  local components="main contrib non-free"

  if [[ "${OS}" == "debian" ]]; then
    local major="${OS_VERSION_ID%%.*}"
    if [[ "${major}" =~ ^[0-9]+$ ]] && (( major >= 12 )); then
      components="main contrib non-free non-free-firmware"
    fi
  fi

  printf '%s' "${components}"
}

guess_debian_codename_from_version() {
  local dv=""
  dv="$(cat /etc/debian_version 2>/dev/null || true)"

  case "${dv}" in
    13*) echo "trixie" ;;
    12*) echo "bookworm" ;;
    11*) echo "bullseye" ;;
    10*) echo "buster" ;;
    9*) echo "stretch" ;;
    *) echo "" ;;
  esac
}

get_apt_codename() {
  local codename="${OS_VERSION_CODENAME:-}"

  if [[ -z "${codename}" && "${OS}" == "debian" ]]; then
    codename="$(guess_debian_codename_from_version)"
  fi

  if [[ -z "${codename}" ]]; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi

  printf '%s' "${codename}"
}

get_docker_apt_codename() {
  local codename=""

  if [[ "${DOCKER_REPO_OS}" == "ubuntu" && -n "${OS_UBUNTU_CODENAME}" ]]; then
    codename="${OS_UBUNTU_CODENAME}"
  else
    codename="${OS_VERSION_CODENAME:-}"
  fi

  if [[ -z "${codename}" ]]; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi

  printf '%s' "${codename}"
}

apt_has_candidate() {
  local pkg="${1:-}"
  [[ -n "${pkg}" ]] || return 1
  command -v apt-cache &>/dev/null || return 0

  local candidate=""
  candidate="$(apt-cache policy "${pkg}" 2>/dev/null | sed -n 's/^[[:space:]]*Candidate: //p' | tail -n 1 || true)"
  [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

apt_sources_already_china_mirror() {
  grep -RqsE "aliyun|tuna|ustc|163|tencent|huawei" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
}

backup_apt_sources_full_for_repair() {
  local ts backup_dir
  ts="$(date +%F_%H%M%S)"
  backup_dir="/etc/apt/sources.backup.${ts}"

  "${SUDO[@]}" mkdir -p "${backup_dir}"
  if [[ -f /etc/apt/sources.list ]]; then
    "${SUDO[@]}" cp -a /etc/apt/sources.list "${backup_dir}/sources.list" || true
  fi

  if [[ -d /etc/apt/sources.list.d ]]; then
    "${SUDO[@]}" mkdir -p "${backup_dir}/sources.list.d"
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
      [[ -e "${f}" ]] || continue
      "${SUDO[@]}" mv -f "${f}" "${backup_dir}/sources.list.d/" || true
    done
  fi

  msg_ok "APT 源已完整备份到: ${backup_dir}"
}

backup_main_apt_sources_only() {
  local ts
  ts="$(date +%F_%H%M%S)"

  if [[ -f /etc/apt/sources.list ]]; then
    "${SUDO[@]}" cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.${ts}" || true
    msg_ok "已备份 /etc/apt/sources.list 到 /etc/apt/sources.list.bak.${ts}"
  fi
}

mirror_host_for_provider() {
  local provider="${1:-aliyun}"
  local distro="${2:-debian}"

  case "${provider}:${distro}" in
    aliyun:debian) echo "http://mirrors.aliyun.com/debian" ;;
    aliyun:ubuntu) echo "http://mirrors.aliyun.com/ubuntu" ;;
    tencent:debian) echo "http://mirrors.cloud.tencent.com/debian" ;;
    tencent:ubuntu) echo "http://mirrors.cloud.tencent.com/ubuntu" ;;
    huawei:debian) echo "https://repo.huaweicloud.com/debian" ;;
    huawei:ubuntu) echo "https://repo.huaweicloud.com/ubuntu" ;;
    *) return 1 ;;
  esac
}

write_debian_sources() {
  local codename="$1"
  local components="$2"
  local base_url="$3"
  local security_url="${4:-${base_url}-security}"

  cat <<EOF | "${SUDO[@]}" tee /etc/apt/sources.list >/dev/null
deb ${base_url} ${codename} ${components}
deb ${base_url} ${codename}-updates ${components}
deb ${security_url} ${codename}-security ${components}
EOF
}

write_ubuntu_sources() {
  local codename="$1"
  local base_url="$2"

  cat <<EOF | "${SUDO[@]}" tee /etc/apt/sources.list >/dev/null
deb ${base_url} ${codename} main restricted universe multiverse
deb ${base_url} ${codename}-updates main restricted universe multiverse
deb ${base_url} ${codename}-backports main restricted universe multiverse
deb ${base_url} ${codename}-security main restricted universe multiverse
EOF
}

ensure_apt_ready_debian() {
  [[ "${OS_FAMILY}" == "debian" ]] || return 0

  if run_quiet "检测 APT 索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3; then
    if apt_has_candidate "ca-certificates"; then
      return 0
    fi
  fi

  if [[ "${OS}" != "debian" && "${OS}" != "ubuntu" ]]; then
    fatal "APT 源不可用，且当前为 Debian/Ubuntu 衍生系统 ${OS}，为避免误改系统源，已停止。请先修复软件源。"
  fi

  msg_warn "APT 源不可用，进入自愈流程..."

  local codename components
  codename="$(get_apt_codename)"
  [[ -n "${codename}" ]] || fatal "无法获取系统代号 VERSION_CODENAME。"

  backup_apt_sources_full_for_repair

  if [[ "${OS}" == "debian" ]]; then
    components="$(debian_components)"
    if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
      write_debian_sources "${codename}" "${components}" "http://mirrors.aliyun.com/debian" "http://mirrors.aliyun.com/debian-security"
    else
      write_debian_sources "${codename}" "${components}" "http://deb.debian.org/debian" "http://security.debian.org/debian-security"
    fi
  else
    if [[ "${USE_CHINA_MIRROR}" == "true" ]]; then
      write_ubuntu_sources "${codename}" "http://mirrors.aliyun.com/ubuntu"
    else
      write_ubuntu_sources "${codename}" "http://archive.ubuntu.com/ubuntu"
    fi
  fi

  "${SUDO[@]}" rm -rf /var/lib/apt/lists/*
  run_quiet "刷新修复后的 APT 索引" "${SUDO[@]}" apt-get update -o Acquire::Retries=3
  apt_has_candidate "ca-certificates" || fatal "APT 源修复后仍不可用。"
}
