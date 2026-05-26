#!/usr/bin/env bash
set -euo pipefail

# Common runtime facade. Implementation lives under scripts/lib/.

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'

declare -ag SUDO=()
OS=""
OS_LIKE=""
OS_FAMILY=""
OS_VERSION_ID=""
OS_VERSION_CODENAME=""
OS_UBUNTU_CODENAME=""
DOCKER_REPO_OS=""
PKG_MANAGER=""
INIT_SYSTEM=""
USE_CHINA_MIRROR=false
declare -ag COMPOSE_CMD=()

APP_DIR="${APP_DIR:-/data/docker/sillytavern}"
ST_PATH="${APP_DIR}"
ST_COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
ST_CONFIG_FILE="${APP_DIR}/config/config.yaml"

__st_common_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
__st_common_lib_dir="${__st_common_dir}/lib"

# shellcheck source=sillytavern-toolkit/scripts/lib/logging.sh
. "${__st_common_lib_dir}/logging.sh"
# shellcheck source=sillytavern-toolkit/scripts/lib/input.sh
. "${__st_common_lib_dir}/input.sh"
# shellcheck source=sillytavern-toolkit/scripts/lib/network.sh
. "${__st_common_lib_dir}/network.sh"
# shellcheck source=sillytavern-toolkit/scripts/lib/os.sh
. "${__st_common_lib_dir}/os.sh"
# shellcheck source=sillytavern-toolkit/scripts/lib/apt.sh
. "${__st_common_lib_dir}/apt.sh"
# shellcheck source=sillytavern-toolkit/scripts/lib/packages.sh
. "${__st_common_lib_dir}/packages.sh"
# shellcheck source=sillytavern-toolkit/scripts/lib/compose.sh
. "${__st_common_lib_dir}/compose.sh"

init_environment() {
  if [[ "${ST_TOOLKIT_REQUIRE_SUDO:-1}" == "1" ]]; then
    init_sudo
  else
    SUDO=()
  fi

  detect_os
  detect_init_system
  detect_package_manager

  if [[ "${ST_TOOLKIT_SKIP_COUNTRY:-0}" != "1" ]]; then
    detect_country
  else
    USE_CHINA_MIRROR=false
  fi
}

if [[ "${ST_TOOLKIT_TEST_MODE:-0}" != "1" ]]; then
  init_environment
fi
