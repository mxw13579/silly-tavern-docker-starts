#!/usr/bin/env bash

find_latest_daemon_json_backup() {
  local latest=""

  # 仅恢复最近一次 /etc/docker/daemon.json.bak.*（按 mtime 最新）。
  # BusyBox/Alpine 兼容：避免依赖 GNU find 的 -printf，也避免解析 ls 输出。
  if stat -c '%Y %n' /dev/null >/dev/null 2>&1; then
    latest="$(
      find /etc/docker -maxdepth 1 -type f -name 'daemon.json.bak.*' \
        -exec stat -c '%Y %n' {} \; 2>/dev/null \
        | sort -nr 2>/dev/null \
        | awk 'NR==1{print $2}' \
        || true
    )"
  elif stat -f '%m %N' /dev/null >/dev/null 2>&1; then
    # BSD/macOS stat 兼容分支
    latest="$(
      find /etc/docker -maxdepth 1 -type f -name 'daemon.json.bak.*' \
        -exec stat -f '%m %N' {} \; 2>/dev/null \
        | sort -nr 2>/dev/null \
        | awk 'NR==1{print $2}' \
        || true
    )"
  else
    # 极保守兜底：若没有可用的 stat 格式化能力，退化为按名称字典序找最新备份。
    # 本项目备份命名使用 YYYY-MM-DD_HHMMSS，字典序与时间序一致。
    latest="$(
      find /etc/docker -maxdepth 1 -type f -name 'daemon.json.bak.*' -print 2>/dev/null \
        | sort -r 2>/dev/null \
        | awk 'NR==1{print $0}' \
        || true
    )"
  fi
  printf '%s\n' "${latest}"
}


validate_json_file() {
  local path="$1"

  [[ -f "${path}" ]] || return 1
  [[ -s "${path}" ]] || return 1

  if command -v python3 &>/dev/null; then
    python3 - "${path}" <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    json.load(f)
PY
    return
  fi

  if command -v jq &>/dev/null; then
    jq -e . "${path}" >/dev/null 2>&1
    return
  fi

  # 恢复 daemon.json 备份属于高风险操作：无 python3/jq 时无法做可靠 JSON 校验，直接拒绝。
  return 1
}


restore_latest_daemon_json_backup_interactive() {
  ensure_interactive_tty

  if ! command -v python3 &>/dev/null && ! command -v jq &>/dev/null; then
    fatal "恢复 /etc/docker/daemon.json 备份需要真实 JSON 解析器（python3 或 jq）。当前未检测到 python3/jq。请先安装 python3 或 jq 后重试。"
  fi

  local latest_backup=""
  latest_backup="$(find_latest_daemon_json_backup)"

  if [[ -z "${latest_backup}" ]]; then
    msg_warn "未找到可恢复的备份文件：/etc/docker/daemon.json.bak.*"
    return 0
  fi

  msg_info "检测到最近一次 Docker 配置备份：${latest_backup}"

  if ! validate_json_file "${latest_backup}"; then
    fatal "备份文件不是有效 JSON：${latest_backup}"
  fi

  local answer=""
  read -r -p "确认使用该备份覆盖 /etc/docker/daemon.json？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*) ;;
    *) msg_warn "已取消恢复。"; return 0 ;;
  esac

  "${SUDO[@]}" mkdir -p /etc/docker

  local pre_restore_backup="/etc/docker/daemon.json.pre_restore.$(date +%F_%H%M%S)"
  local pre_restore_missing=0
  if [[ -f /etc/docker/daemon.json ]]; then
    run_quiet "备份当前 Docker 配置" "${SUDO[@]}" cp -a /etc/docker/daemon.json "${pre_restore_backup}" \
      || fatal "备份当前 /etc/docker/daemon.json 失败，已中止恢复。"
  else
    pre_restore_missing=1
    # 注意：不能 cp /dev/null（可能会尝试创建字符设备）；这里用 shell 重定向创建空文件作为占位。
    run_quiet "备份当前 Docker 配置(不存在则创建占位备份)" "${SUDO[@]}" sh -c ": >\"${pre_restore_backup}\"" \
      || fatal "创建 pre-restore 占位备份失败，已中止恢复。"
  fi
  msg_ok "已备份恢复前 Docker 配置到: ${pre_restore_backup}"

  run_quiet "恢复 Docker daemon.json" "${SUDO[@]}" cp -a "${latest_backup}" /etc/docker/daemon.json \
    || fatal "恢复失败：无法覆盖写入 /etc/docker/daemon.json。"
  msg_ok "已恢复 Docker 配置：${latest_backup} -> /etc/docker/daemon.json"

  msg_warn "修改 Docker daemon.json 后需要重启 Docker 才会生效。"
  read -r -p "是否现在重启 Docker 服务？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*)
      if restart_docker_service_restore; then
        msg_ok "Docker 服务已重启，恢复的配置已生效。"
        return 0
      fi

      msg_error "Docker 重启失败，将自动回滚到恢复前配置并再尝试重启一次..."
      if ((pre_restore_missing == 1)); then
        run_quiet "回滚 Docker 配置(恢复前无 daemon.json，移除当前文件)" "${SUDO[@]}" rm -f /etc/docker/daemon.json \
          || fatal "Docker 重启失败，且回滚操作失败：无法移除 /etc/docker/daemon.json。请手动处理。"
      else
        run_quiet "回滚 Docker 配置" "${SUDO[@]}" cp -a "${pre_restore_backup}" /etc/docker/daemon.json \
          || fatal "Docker 重启失败，且回滚操作失败：无法恢复 ${pre_restore_backup} -> /etc/docker/daemon.json。请手动处理。"
      fi

      if restart_docker_service_restore; then
        msg_warn "已回滚到恢复前配置并重启成功；本次恢复的 daemon.json 未生效。"
        return 0
      fi

      fatal "Docker 重启失败：已尝试回滚到恢复前配置并再次重启，但仍失败。请检查 /etc/docker/daemon.json（当前为回滚后的配置）并手动排查。参考备份：${latest_backup}（尝试恢复的备份）与 ${pre_restore_backup}（恢复前备份）。"
      ;;
    *)
      msg_warn "已跳过重启。当前 /etc/docker/daemon.json 尚未验证；请稍后手动重启 Docker 并确认服务状态正常。"
      ;;
  esac
}

