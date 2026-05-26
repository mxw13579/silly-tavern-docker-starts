#!/usr/bin/env bash
set -euo pipefail

ST_TOOLKIT_REQUIRE_SUDO=1
ST_TOOLKIT_SKIP_COUNTRY=1

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HEALTH_OK_COUNT=0
HEALTH_WARN_COUNT=0
HEALTH_FAIL_COUNT=0

ok() {
  HEALTH_OK_COUNT=$((HEALTH_OK_COUNT + 1))
  msg_ok "$*"
}

warn() {
  HEALTH_WARN_COUNT=$((HEALTH_WARN_COUNT + 1))
  msg_warn "$*"
}

fail() {
  HEALTH_FAIL_COUNT=$((HEALTH_FAIL_COUNT + 1))
  msg_error "$*"
}

section() {
  log
  log "== $* =="
}

show_health_summary() {
  log
  log "== 检查汇总 =="
  msg_info "通过: ${HEALTH_OK_COUNT}，警告: ${HEALTH_WARN_COUNT}，失败: ${HEALTH_FAIL_COUNT}"

  if ((HEALTH_FAIL_COUNT > 0)); then
    msg_error "下一步建议：优先处理失败项，确认 Docker/Compose 可用、部署文件存在，并重新运行健康检查。"
  elif ((HEALTH_WARN_COUNT > 0)); then
    msg_warn "下一步建议：检查警告项；若服务访问异常，请查看容器状态、端口映射和最近日志。"
  else
    msg_ok "下一步建议：基础健康检查通过；如仍有业务异常，请继续检查应用配置和运行日志。"
  fi
}

show_file_status() {
  local title="$1"
  local path="$2"

  if [[ -e "${path}" ]]; then
    ok "${title}: ${path}"
    ls -ld "${path}" 2>/dev/null || true
  else
    fail "${title}不存在: ${path}"
  fi
}

docker_available=false
docker_running=false
compose_available=false
container_id=""

section "基础环境"
if command -v docker &>/dev/null; then
  docker_available=true
  ok "Docker 命令可用: $(command -v docker)"
  "${SUDO[@]}" docker --version 2>/dev/null || true
else
  fail "Docker 命令不可用"
fi

if [[ "${docker_available}" == "true" ]] && "${SUDO[@]}" docker info &>/dev/null; then
  docker_running=true
  ok "Docker daemon 可访问"
else
  fail "Docker daemon 不可访问或当前用户无权限"
fi

if [[ "${docker_available}" == "true" ]] && detect_compose_cmd; then
  compose_available=true
  ok "Compose 可用: ${COMPOSE_CMD[*]}"
  "${COMPOSE_CMD[@]}" version 2>/dev/null || true
else
  fail "未检测到 docker compose 或 docker-compose"
fi

section "部署文件"
show_file_status "部署目录" "${APP_DIR}"
show_file_status "Compose 文件" "${ST_COMPOSE_FILE}"
show_file_status "配置文件" "${ST_CONFIG_FILE}"

section "容器状态"
if [[ "${docker_running}" == "true" && "${compose_available}" == "true" && -f "${ST_COMPOSE_FILE}" ]]; then
  container_id="$(cd "${APP_DIR}" && "${COMPOSE_CMD[@]}" ps -q sillytavern 2>/dev/null || true)"
  if [[ -n "${container_id}" ]]; then
    ok "SillyTavern 容器 ID: ${container_id}"
    "${SUDO[@]}" docker inspect --format '名称={{.Name}} 状态={{.State.Status}} 重启次数={{.RestartCount}} 健康={{if .State.Health}}{{.State.Health.Status}}{{else}}未配置{{end}}' "${container_id}" 2>/dev/null || true
  else
    warn "未找到 sillytavern 服务容器"
  fi

  (cd "${APP_DIR}" && "${COMPOSE_CMD[@]}" ps 2>/dev/null) || true
else
  warn "跳过容器状态检查：Docker/Compose/Compose 文件不完整"
fi

section "端口映射与监听"
if [[ -f "${ST_COMPOSE_FILE}" ]]; then
  msg_info "Compose 中的 8000 端口配置:"
  grep -n "8000" "${ST_COMPOSE_FILE}" 2>/dev/null || warn "Compose 文件中未找到 8000 端口配置"
fi

if [[ -n "${container_id}" ]]; then
  msg_info "Docker 端口映射:"
  "${SUDO[@]}" docker port "${container_id}" 2>/dev/null || warn "未读取到 Docker 端口映射"
fi

if command -v ss &>/dev/null; then
  msg_info "本机监听 8000 信息:"
  ss -ltnp 2>/dev/null | awk 'NR == 1 || $4 ~ /(^|[:.])8000$/ { print }' || true
elif command -v netstat &>/dev/null; then
  msg_info "本机监听 8000 信息:"
  netstat -ltnp 2>/dev/null | awk 'NR == 1 || $4 ~ /(^|[:.])8000$/ { print }' || true
else
  warn "未找到 ss/netstat，无法展示本机监听信息"
fi

section "最近日志"
if [[ "${docker_running}" == "true" && "${compose_available}" == "true" && -f "${ST_COMPOSE_FILE}" ]]; then
  msg_info "最近 50 行日志:"
  (cd "${APP_DIR}" && "${COMPOSE_CMD[@]}" logs --tail 50 sillytavern 2>/dev/null) || warn "无法读取 sillytavern 日志"
else
  warn "跳过日志检查：Docker/Compose/Compose 文件不完整"
fi

show_health_summary
