#!/usr/bin/env bash

# Minimal helpers for Bats tests (no external deps).

make_stub_dir() {
  local dir="${BATS_TEST_TMPDIR}/stubs"
  mkdir -p "${dir}"
  printf '%s\n' "${dir}"
}

write_exe() {
  local path="$1"
  shift
  mkdir -p "$(dirname "${path}")"
  {
    printf '%s\n' "$@"
  } >"${path}"
  chmod +x "${path}"
}

prepend_path() {
  local dir="$1"
  export PATH="${dir}:${PATH}"
}

assert_output_contains() {
  local needle="$1"
  [[ "${output}" == *"${needle}"* ]]
}

assert_status_eq() {
  local want="$1"
  [[ "${status}" -eq "${want}" ]]
}
