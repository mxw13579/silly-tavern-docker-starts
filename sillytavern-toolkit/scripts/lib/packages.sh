#!/usr/bin/env bash

install_redhat_gnupg_compatible() {
  case "${PKG_MANAGER}" in
    dnf)
      run_quiet "安装 gnupg2" "${SUDO[@]}" dnf install -y gnupg2 && return 0
      run_quiet "安装 gnupg" "${SUDO[@]}" dnf install -y gnupg && return 0
      ;;
    yum)
      run_quiet "安装 gnupg2" "${SUDO[@]}" yum install -y gnupg2 && return 0
      run_quiet "安装 gnupg" "${SUDO[@]}" yum install -y gnupg && return 0
      ;;
  esac

  msg_warn "gnupg/gnupg2 安装失败，但当前 RedHat Docker 安装流程不强依赖该包，继续执行。"
}

install_base_packages() {
  case "${PKG_MANAGER}" in
    apt)
      ensure_apt_ready_debian
      run_quiet "安装基础依赖" "${SUDO[@]}" apt-get install -y ca-certificates curl gnupg lsb-release
      ;;
    dnf)
      run_quiet "安装基础依赖" "${SUDO[@]}" dnf install -y ca-certificates curl dnf-plugins-core
      install_redhat_gnupg_compatible
      ;;
    yum)
      run_quiet "安装基础依赖" "${SUDO[@]}" yum install -y ca-certificates curl yum-utils
      install_redhat_gnupg_compatible
      ;;
    pacman)
      run_quiet "安装基础依赖" "${SUDO[@]}" pacman -Sy --noconfirm curl ca-certificates gnupg
      ;;
    apk)
      run_quiet "安装基础依赖" "${SUDO[@]}" apk add --no-cache curl ca-certificates gnupg
      ;;
    zypper)
      if ! run_quiet "安装基础依赖" "${SUDO[@]}" zypper --non-interactive install curl ca-certificates gpg2; then
        run_quiet "安装基础依赖" "${SUDO[@]}" zypper --non-interactive install curl ca-certificates gnupg
      fi
      ;;
  esac
}
