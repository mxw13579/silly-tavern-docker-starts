#!/usr/bin/env bash

DOCKER_DEFAULT_MIRROR="https://mirror.ccs.tencentyun.com"
DOCKER_HUB_NATIVE_REGISTRY="https://registry-1.docker.io"
OPSNOTE_MIRROR_URL="https://tools.opsnote.top/registry-mirrors/"
DOCKER_MIRROR_SPEED_CONCURRENCY="${DOCKER_MIRROR_SPEED_CONCURRENCY:-5}"
DOCKER_MIRROR_MENU_SEP="----------------------------------------------------------"

__st_docker_base_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || fatal "无法定位 Docker 脚本目录。"
__st_docker_mirror_dir="${__st_docker_base_dir}/mirror"

require_docker_mirror_module() {
  local module="$1"
  local path="${__st_docker_mirror_dir}/${module}"

  [[ -f "${path}" ]] || fatal "缺少 Docker 镜像加速器模块: ${path}"
  # shellcheck source=/dev/null
  . "${path}"
}

# shellcheck source=sillytavern-toolkit/scripts/docker/mirror/probe.sh
require_docker_mirror_module "probe.sh"
# shellcheck source=sillytavern-toolkit/scripts/docker/mirror/config.sh
require_docker_mirror_module "config.sh"
# shellcheck source=sillytavern-toolkit/scripts/docker/mirror/restore.sh
require_docker_mirror_module "restore.sh"
# shellcheck source=sillytavern-toolkit/scripts/docker/mirror/menu.sh
require_docker_mirror_module "menu.sh"
