#!/usr/bin/env bash

fetch_url_quiet() {
  local url="$1"

  if command -v curl &>/dev/null; then
    curl -fsSL --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 1 --retry-connrefused "${url}"
  elif command -v wget &>/dev/null; then
    wget -qO- --timeout=30 --tries=3 "${url}"
  else
    return 1
  fi
}

# 轻量文件缓存（用户级，无需 sudo）。
# - 缓存目录: ${XDG_CACHE_HOME:-$HOME/.cache}/sillytavern-toolkit
# - key: 使用 sha256sum/shasum/cksum 生成，避免路径穿越。
st_cache_dir() {
  local base=""
  if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    base="${XDG_CACHE_HOME}"
  elif [[ -n "${HOME:-}" ]]; then
    base="${HOME}/.cache"
  fi
  [[ -n "${base}" ]] || base="/tmp"
  printf '%s\n' "${base%/}/sillytavern-toolkit"
}

st_cache_key() {
  local raw="${1:-}"
  [[ -n "${raw}" ]] || return 1

  if command -v sha256sum &>/dev/null; then
    printf '%s' "${raw}" | sha256sum | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    printf '%s' "${raw}" | shasum -a 256 | awk '{print $1}'
  elif command -v cksum &>/dev/null; then
    local out crc size
    out="$(printf '%s' "${raw}" | cksum)" || return 1
    crc="${out%% *}"
    size="${out#* }"
    size="${size%% *}"
    printf 'cksum_%s_%s\n' "${crc}" "${size}"
  else
    return 1
  fi
}

st_cache_is_fresh() {
  local ttl="${1:-}"
  local key="${2:-}"
  [[ -n "${ttl}" && -n "${key}" ]] || return 1
  [[ "${ttl}" =~ ^[0-9]+$ ]] || return 1
  ((ttl > 0)) || return 1

  local dir ts_file data_file ts now
  dir="$(st_cache_dir)"
  ts_file="${dir}/${key}.ts"
  data_file="${dir}/${key}.data"

  [[ -f "${ts_file}" && -f "${data_file}" ]] || return 1

  ts="$(cat "${ts_file}" 2>/dev/null || true)"
  [[ "${ts}" =~ ^[0-9]+$ ]] || return 1

  now="$(date +%s 2>/dev/null || true)"
  [[ "${now}" =~ ^[0-9]+$ ]] || return 1

  # Guard against future timestamps: cache is only fresh when ts <= now and within ttl.
  ((ts <= now && now - ts <= ttl))
}

st_cache_read() {
  local ttl="${1:-}"
  local key="${2:-}"
  [[ -n "${ttl}" && -n "${key}" ]] || return 1

  st_cache_is_fresh "${ttl}" "${key}" || return 1
  cat "$(st_cache_dir)/${key}.data"
}

st_cache_write() {
  local key="${1:-}"
  [[ -n "${key}" ]] || return 1

  local dir data_file ts_file tmp_data tmp_ts
  dir="$(st_cache_dir)"

  mkdir -p "${dir}" 2>/dev/null || return 1

  data_file="${dir}/${key}.data"
  ts_file="${dir}/${key}.ts"

  tmp_data="$(mktemp "${dir}/.${key}.data.XXXXXX" 2>/dev/null || true)"
  [[ -n "${tmp_data}" ]] || return 1

  if ! cat >"${tmp_data}"; then
    rm -f "${tmp_data}" 2>/dev/null || true
    return 1
  fi

  tmp_ts="$(mktemp "${dir}/.${key}.ts.XXXXXX" 2>/dev/null || true)"
  if [[ -n "${tmp_ts}" ]]; then
    date +%s >"${tmp_ts}" 2>/dev/null || true
  fi

  mv -f "${tmp_data}" "${data_file}" 2>/dev/null || {
    rm -f "${tmp_data}" 2>/dev/null || true
    if [[ -n "${tmp_ts}" ]]; then
      rm -f "${tmp_ts}" 2>/dev/null || true
    fi
    return 1
  }

  if [[ -n "${tmp_ts}" ]]; then
    mv -f "${tmp_ts}" "${ts_file}" 2>/dev/null || rm -f "${tmp_ts}" 2>/dev/null || true
  else
    date +%s >"${ts_file}" 2>/dev/null || true
  fi
}

safe_curl_download() {
  command -v curl &>/dev/null || fatal "curl 不存在，无法下载文件。"
  curl -fL --progress-bar --connect-timeout 10 --max-time 180 --retry 3 --retry-delay 1 --retry-connrefused "$@"
}
