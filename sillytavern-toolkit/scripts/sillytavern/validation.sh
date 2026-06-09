#!/usr/bin/env bash

# SillyTavern 校验辅助函数，由 scripts/sillytavern.sh 在 common.sh 和 compose.sh 之后加载。

print_validation_problem() {
  local problem="$1"
  local impact="$2"
  local fix="$3"

  printf 'ERROR: problem: %s\n' "${problem}" >&2
  printf 'ERROR: impact: %s\n' "${impact}" >&2
  printf 'ERROR: fix: %s\n' "${fix}" >&2
}

validate_sillytavern_files() {
  local missing=0

  if ! "${SUDO[@]}" test -f "${ST_COMPOSE_FILE}"; then
    print_validation_problem \
      "缺少 SillyTavern Compose 文件: ${ST_COMPOSE_FILE}" \
      "Docker Compose 无法校验或启动当前 SillyTavern 项目。" \
      "请先执行安装，或从可用备份恢复 docker-compose.yaml。"
    missing=1
  fi

  if ! "${SUDO[@]}" test -f "${ST_CONFIG_FILE}"; then
    print_validation_problem \
      "缺少 SillyTavern 配置文件: ${ST_CONFIG_FILE}" \
      "SillyTavern 可能会以非预期或不完整的访问配置启动。" \
      "请重新配置访问方式，或从可用备份恢复 config.yaml。"
    missing=1
  fi

  [[ "${missing}" -eq 0 ]]
}

validate_sillytavern_compose() {
  local skip_docker_check="${1:-}"

  validate_sillytavern_files || return 1
  if [[ "${skip_docker_check}" != "--skip-docker-check" ]]; then
    check_docker_env || return 1
  fi

  if compose_in_app "校验 SillyTavern Compose 配置" config -q; then
    msg_ok "SillyTavern Compose 配置有效。"
    return 0
  fi

  print_validation_problem \
    "Docker Compose 拒绝当前 SillyTavern Compose 文件。" \
    "当前 Compose 文件不适合应用，服务状态未被修改。" \
    "请检查 docker-compose.yaml，并确认 config.yaml 存在，然后运行: bash scripts/sillytavern.sh validate"
  return 1
}

hash_file_sha256() {
  local file_path="$1"
  local hash_output=""

  if [[ -z "${file_path}" ]] || ! "${SUDO[@]}" test -f "${file_path}"; then
    print_validation_problem \
      "无法计算缺失文件的哈希: ${file_path:-<empty>}" \
      "备份、更新或恢复流程无法记录当前文件状态。" \
      "请检查文件路径，恢复缺失文件后重试。"
    return 1
  fi

  if command -v sha256sum &>/dev/null; then
    if hash_output="$("${SUDO[@]}" sha256sum "${file_path}" 2>/dev/null)"; then
      awk '{print $1}' <<<"${hash_output}"
      return 0
    fi
  fi

  if command -v shasum &>/dev/null; then
    if hash_output="$("${SUDO[@]}" shasum -a 256 "${file_path}" 2>/dev/null)"; then
      awk '{print $1}' <<<"${hash_output}"
      return 0
    fi
  fi

  print_validation_problem \
    "无法计算文件 SHA-256: ${file_path}" \
    "工具箱无法为回滚或诊断记录可靠的文件指纹。" \
    "请安装 sha256sum 或 shasum，并确认工具箱用户可通过 sudo 读取该文件。"
  return 1
}

hash_sillytavern_compose() {
  hash_file_sha256 "${ST_COMPOSE_FILE}"
}

hash_sillytavern_config() {
  hash_file_sha256 "${ST_CONFIG_FILE}"
}
