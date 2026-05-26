#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "status" ]]; then
  export ST_TOOLKIT_REQUIRE_SUDO=0
  export ST_TOOLKIT_SKIP_COUNTRY=1
fi

__st_scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sillytavern-toolkit/scripts/common.sh
. "${__st_scripts_dir}/common.sh"
# shellcheck source=sillytavern-toolkit/scripts/docker/install.sh
. "${__st_scripts_dir}/docker/install.sh"
# shellcheck source=sillytavern-toolkit/scripts/docker/mirror.sh
. "${__st_scripts_dir}/docker/mirror.sh"
# shellcheck source=sillytavern-toolkit/scripts/docker/compose.sh
. "${__st_scripts_dir}/docker/compose.sh"
# shellcheck source=sillytavern-toolkit/scripts/docker/status.sh
. "${__st_scripts_dir}/docker/status.sh"

usage() {
  cat <<'EOF'
用法: docker.sh <命令>

命令:
  install          安装或验证 Docker 与 Compose
  compose          单独检查/安装 Docker Compose
  config_mirror    配置默认 Docker 国内镜像加速器
  mirror_menu      Docker 镜像加速器交互管理
  mirror_status    显示 Docker 镜像加速器配置
  mirror_speed     测速当前 Docker 镜像加速器
  restore_daemon   恢复最近一次 daemon.json 备份
  restart_service  重启 Docker 服务
  list_images      查看已下载的 Docker 镜像
  images           list_images 的别名
  status           显示 Docker 状态
EOF
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
  restore_daemon)
    restore_latest_daemon_json_backup_interactive
    ;;
  restart_service)
    restart_docker_service
    ;;
  list_images|images)
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
