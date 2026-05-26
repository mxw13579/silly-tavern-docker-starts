#!/usr/bin/env bash

is_pure_number() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

generate_random_string() {
  local len="${1:-16}"
  if ! [[ "${len}" =~ ^[0-9]+$ ]] || (( len < 8 )); then
    len=16
  fi

  [[ -r /dev/urandom ]] || fatal "/dev/urandom 不可用，无法生成随机字符串。"

  local out="" chunk="" attempts=0
  while (( ${#out} < len )); do
    chunk="$(head -c 256 /dev/urandom | tr -dc 'A-Za-z0-9' | tr -d '\n')"
    out+="${chunk}"
    attempts=$((attempts + 1))
    (( attempts < 20 )) || fatal "随机字符串生成失败。"
  done

  out="${out:0:len}"
  is_pure_number "${out}" && out="a${out:1}"
  printf '%s' "${out}"
}

validate_credential() {
  local value="${1:-}"
  [[ -n "${value}" ]] || return 1
  [[ ! "${value}" =~ ^[0-9]+$ ]] || return 1
  [[ "${value}" =~ ^[A-Za-z0-9._@-]{3,64}$ ]] || return 1
}

ensure_interactive_tty() {
  [[ -r /dev/tty ]] || fatal "当前环境没有可交互 TTY，无法读取用户输入。请使用 bash script.sh 方式运行。"
}

read_yes_no() {
  local prompt="$1"
  local result_var="$2"
  local response=""

  while true; do
    read -r -p "${prompt}" response </dev/tty
    case "${response}" in
      [Yy]*) printf -v "${result_var}" "y"; return 0 ;;
      [Nn]*) printf -v "${result_var}" "n"; return 0 ;;
      *) msg_warn "请输入 y 或 n。" ;;
    esac
  done
}
