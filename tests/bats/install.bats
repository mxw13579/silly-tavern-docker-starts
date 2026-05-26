#!/usr/bin/env bats

load "../helpers/stubs.bash"

write_install_stubs() {
  local stub_dir="$1"
  local repo_root="$2"

  # sudo stub: keep install.sh non-interactive and avoid privilege side effects.
  write_exe "${stub_dir}/sudo" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "${1:-}" == "-v" ]]; then exit 0; fi' \
    'if [[ "${1:-}" == "-n" && "${2:-}" == "true" ]]; then exit 0; fi' \
    'args=()' \
    'for a in "$@"; do' \
    '  case "$a" in' \
    '    -n|-v) ;;' \
    '    *) args+=("$a") ;;' \
    '  esac' \
    'done' \
    'exec "${args[@]}"'

  # curl stub: emulate ipinfo country probe (no network).
  write_exe "${stub_dir}/curl" \
    '#!/usr/bin/env bash' \
    'url=""' \
    'for a in "$@"; do url="$a"; done' \
    'case "$url" in' \
    '  *ipinfo.io/country) printf "%s" "${STUB_COUNTRY:-US}" ;;' \
    '  *) printf "%s" "" ;;' \
    'esac'

  # git stub: emulate "git clone --depth 1 --branch <ref> <url> <dest>".
  # Also support commit-hash path used by install.sh:
  #   git init <dir>
  #   git -C <dir> remote add origin <url>
  #   git -C <dir> fetch --depth 1 origin <commit>
  #   git -C <dir> checkout --detach FETCH_HEAD
  # Create a minimal toolkit tree under <worktree>/sillytavern-toolkit so install.sh can proceed.
  write_exe "${stub_dir}/git" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'repo_root="${STUB_REPO_ROOT:-}"' \
    'if [[ -z "${repo_root}" ]]; then echo "stub git: missing STUB_REPO_ROOT" >&2; exit 2; fi' \
    'REPO_PATH="sillytavern-toolkit"' \
    '' \
    'make_toolkit_tree() {' \
    '  local worktree="$1"' \
    '  local ref="$2"' \
    '  mkdir -p "${worktree}/${REPO_PATH}/scripts"' \
    '  printf "%s" "${ref}" > "${worktree}/${REPO_PATH}/.stub_ref"' \
    '  cat > "${worktree}/${REPO_PATH}/st-toolkit.sh" <<'\''SH'\''' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "LAUNCHED\\n" > "${TOOLKIT_DIR}/.launched"' \
    'exit 0' \
    'SH' \
    '  chmod +x "${worktree}/${REPO_PATH}/st-toolkit.sh"' \
    '  for f in common docker health sillytavern sources; do' \
    '    cat > "${worktree}/${REPO_PATH}/scripts/${f}.sh" <<'\''SH'\''' \
    '#!/usr/bin/env bash' \
    'exit 0' \
    'SH' \
    '    chmod +x "${worktree}/${REPO_PATH}/scripts/${f}.sh"' \
    '  done' \
    '}' \
    '' \
    'git_c_dir=""' \
    'if [[ "${1:-}" == "-C" ]]; then git_c_dir="${2:-}"; shift 2; fi' \
    'subcmd="${1:-}"' \
    '' \
    'case "${subcmd}" in' \
    '  clone)' \
    '    dest=""' \
    '    for a in "$@"; do dest="$a"; done' \
    '    ref=""' \
    '    for ((i=1;i<=$#;i++)); do' \
    '      if [[ "${!i}" == "--branch" ]]; then j=$((i+1)); ref="${!j}"; break; fi' \
    '    done' \
    '    make_toolkit_tree "${dest}" "${ref}"' \
    '    ;;' \
    '  init)' \
    '    worktree="${2:-}"' \
    '    [[ -n "${worktree}" ]] || { echo "stub git: init missing dir" >&2; exit 2; }' \
    '    mkdir -p "${worktree}/.git"' \
    '    ;;' \
    '  remote)' \
    '    [[ -n "${git_c_dir}" ]] || { echo "stub git: remote requires -C <dir>" >&2; exit 2; }' \
    '    # Record remote for debugging if needed.' \
    '    printf "%s" "${*:2}" > "${git_c_dir}/.stub_remote" || true' \
    '    ;;' \
    '  fetch)' \
    '    [[ -n "${git_c_dir}" ]] || { echo "stub git: fetch requires -C <dir>" >&2; exit 2; }' \
    '    ref=""' \
    '    for a in "$@"; do ref="$a"; done' \
    '    printf "%s" "${ref}" > "${git_c_dir}/.stub_fetch_ref"' \
    '    ;;' \
    '  checkout)' \
    '    [[ -n "${git_c_dir}" ]] || { echo "stub git: checkout requires -C <dir>" >&2; exit 2; }' \
    '    ref=""' \
    '    if [[ -f "${git_c_dir}/.stub_fetch_ref" ]]; then ref="$(cat "${git_c_dir}/.stub_fetch_ref")"; fi' \
    '    make_toolkit_tree "${git_c_dir}" "${ref}"' \
    '    ;;' \
    '  check-ref-format)' \
    '    # Minimal behavior: let install.sh decide validity via its own pre-checks.' \
    '    exit 0' \
    '    ;;' \
    '  *)' \
    '    # Keep stub permissive for other git subcommands not used by these tests.' \
    '    exit 0' \
    '    ;;' \
    'esac' \
    'exit 0'
}

@test "install.sh non-interactive proxy confirm does not hang (fails fast without TTY)" {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    if ! command -v sudo &>/dev/null || ! sudo -n true &>/dev/null; then
      skip "install.sh tests require root or passwordless sudo (sudo -n true)."
    fi
  fi

  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_install_stubs "${stub_dir}" "${PWD}"
  prepend_path "${stub_dir}"

  run bash -c '
    set -euo pipefail
    export STUB_COUNTRY="CN"
    export STUB_REPO_ROOT="${PWD}"
    export TOOLKIT_DIR="${BATS_TEST_TMPDIR}/toolkit"
    # No --yes / ST_TOOLKIT_YES: should hard-fail in non-interactive mode.
    bash "sillytavern-toolkit/install.sh" --ref main
  '

  [[ "${status}" -ne 0 ]]
  assert_output_contains "ST_TOOLKIT_YES"
}

@test "install.sh --ref overrides ST_TOOLKIT_REF and ST_TOOLKIT_NO_LAUNCH truthy/falsy controls launch" {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    if ! command -v sudo &>/dev/null || ! sudo -n true &>/dev/null; then
      skip "install.sh tests require root or passwordless sudo (sudo -n true)."
    fi
  fi

  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_install_stubs "${stub_dir}" "${PWD}"
  prepend_path "${stub_dir}"

  # Case A: ST_TOOLKIT_NO_LAUNCH=1 => should NOT run st-toolkit.sh
  run bash -c '
    set -euo pipefail
    export STUB_COUNTRY="US"
    export STUB_REPO_ROOT="${PWD}"
    export TOOLKIT_DIR="${BATS_TEST_TMPDIR}/toolkit_a"
    export ST_TOOLKIT_REF="env-ref-ignored"
    export ST_TOOLKIT_NO_LAUNCH="1"
    bash "sillytavern-toolkit/install.sh" --ref cli-ref
    [[ ! -f "${BATS_TEST_TMPDIR}/toolkit_a/.launched" ]]
    [[ "$(cat "${BATS_TEST_TMPDIR}/toolkit_a/.stub_ref")" == "cli-ref" ]]
  '
  assert_status_eq 0

  # Case B: ST_TOOLKIT_NO_LAUNCH=0 => should run st-toolkit.sh (safe stub) and create marker
  run bash -c '
    set -euo pipefail
    export STUB_COUNTRY="US"
    export STUB_REPO_ROOT="${PWD}"
    export TOOLKIT_DIR="${BATS_TEST_TMPDIR}/toolkit_b"
    export ST_TOOLKIT_REF="env-ref-ignored"
    export ST_TOOLKIT_NO_LAUNCH="0"
    bash "sillytavern-toolkit/install.sh" --ref cli-ref-2
    [[ -f "${BATS_TEST_TMPDIR}/toolkit_b/.launched" ]]
    [[ "$(cat "${BATS_TEST_TMPDIR}/toolkit_b/.stub_ref")" == "cli-ref-2" ]]
  '
  assert_status_eq 0
}

@test "install.sh unset boolean envs do not exit under set -e" {
  run bash -c '
    set -euo pipefail
    f="sillytavern-toolkit/install.sh"
    lib="${BATS_TEST_TMPDIR}/install-lib.sh"
    sed '\''$d'\'' "${f}" > "${lib}"
    . "${lib}"

    unset ST_TOOLKIT_YES ST_TOOLKIT_NO_LAUNCH
    ASSUME_YES=false
    LAUNCH_TOOLKIT=true
    init_env_options
    [[ "${ASSUME_YES}" == "false" ]]
    [[ "${LAUNCH_TOOLKIT}" == "true" ]]
  '

  assert_status_eq 0
}

@test "install.sh validate_ref rejects unsafe refs but allows normal branch/tag/commit" {
  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_install_stubs "${stub_dir}" "${PWD}"
  prepend_path "${stub_dir}"

  run bash -c '
    set -euo pipefail
    export STUB_COUNTRY="US"
    export STUB_REPO_ROOT="${PWD}"

    # Make install.sh non-interactive & side-effect free.
    export TOOLKIT_DIR="${BATS_TEST_TMPDIR}/toolkit_vref"
    export ST_TOOLKIT_NO_LAUNCH="1"

    # Reject empty/whitespace
    ! bash "sillytavern-toolkit/install.sh" --ref ""
    ! bash "sillytavern-toolkit/install.sh" --ref "main "
    ! bash "sillytavern-toolkit/install.sh" --ref " main"

    # Reject obvious bad patterns
    ! bash "sillytavern-toolkit/install.sh" --ref "../main"
    ! bash "sillytavern-toolkit/install.sh" --ref "/abs/path"
    ! bash "sillytavern-toolkit/install.sh" --ref "//double"
    ! bash "sillytavern-toolkit/install.sh" --ref "@{"
    ! bash "sillytavern-toolkit/install.sh" --ref "bad.lock"
    ! bash "sillytavern-toolkit/install.sh" --ref "-opt"
    ! bash "sillytavern-toolkit/install.sh" --ref "a?b"
    ! bash "sillytavern-toolkit/install.sh" --ref "a#b"
    ! bash "sillytavern-toolkit/install.sh" --ref "a:b"
    ! bash "sillytavern-toolkit/install.sh" --ref "a^b"

    # Allow typical branch/tag/commit patterns
    bash "sillytavern-toolkit/install.sh" --ref "main"
    bash "sillytavern-toolkit/install.sh" --ref "v1.0.0"
    bash "sillytavern-toolkit/install.sh" --ref "feature/foo"
    bash "sillytavern-toolkit/install.sh" --ref "0123456789abcdef0123456789abcdef01234567"
  '
  assert_status_eq 0
}

@test "install.sh treats only 40 hex chars as commit ref" {
  local stub_dir
  stub_dir="$(make_stub_dir)"
  write_install_stubs "${stub_dir}" "${PWD}"
  prepend_path "${stub_dir}"

  run bash -c '
    set -euo pipefail
    export STUB_COUNTRY="US"
    export STUB_REPO_ROOT="${PWD}"
    export ST_TOOLKIT_NO_LAUNCH="1"

    export TOOLKIT_DIR="${BATS_TEST_TMPDIR}/toolkit_short_hex"
    bash "sillytavern-toolkit/install.sh" --ref "1234567"
    [[ "$(cat "${TOOLKIT_DIR}/.stub_ref")" == "1234567" ]]
    [[ ! -f "${TOOLKIT_DIR}/../.stub_fetch_ref" ]]

    export TOOLKIT_DIR="${BATS_TEST_TMPDIR}/toolkit_full_hex"
    bash "sillytavern-toolkit/install.sh" --ref "0123456789abcdef0123456789abcdef01234567"
    [[ "$(cat "${TOOLKIT_DIR}/.stub_ref")" == "0123456789abcdef0123456789abcdef01234567" ]]
  '

  assert_status_eq 0
}

@test "install_from_proxy files list covers scripts/{lib,docker,sillytavern} and checksums bind to files[@]" {
  run bash -c '
    set -euo pipefail

    f="sillytavern-toolkit/install.sh"
    [[ -f "${f}" ]]

    # Extract install_from_proxy() body (brace-balanced) so we can validate the local files list.
    body="$(
      awk '
        function count_char(s, c,   n, i) { n=0; for (i=1;i<=length(s);i++) if (substr(s,i,1)==c) n++; return n }
        BEGIN { in=0; depth=0 }
        /^[[:space:]]*install_from_proxy\(\)[[:space:]]*\{/ { in=1 }
        {
          if (in) {
            print
            depth += count_char($0, "{")
            depth -= count_char($0, "}")
            if (depth == 0) exit 0
          }
        }
      ' "${f}"
    )"
    [[ -n "${body}" ]]

    # Assert checksums manifest verification uses the files[@] set (no drift between declared files and verified files).
    printf '%s\n' "${body}" | grep -F 'verify_checksums_manifest' >/dev/null
    printf '%s\n' "${body}" | grep -F '"${files[@]}"' >/dev/null

    # Parse the local files=(...) entries as literal strings.
    files_list="$(
      printf '%s\n' "${body}" |
        awk '
          BEGIN { in=0 }
          /^[[:space:]]*local[[:space:]]+files=\(/ { in=1; next }
          in && /^[[:space:]]*\)/ { in=0; exit 0 }
          in { print }
        ' |
        sed -n "s/^[[:space:]]*\"\([^\"]\+\)\"[[:space:]]*$/\1/p"
    )"
    [[ -n "${files_list}" ]]

    # Helper: require that all repo scripts under a dir are covered by the files list.
    require_dir_covered() {
      local rel_dir="$1"        # e.g. scripts/lib
      local repo_dir="$2"       # e.g. sillytavern-toolkit/scripts/lib

      # If the list includes the glob entry, accept it.
      if printf '%s\n' "${files_list}" | grep -Fx "${rel_dir}/*.sh" >/dev/null; then
        return 0
      fi

      # Otherwise, require explicit coverage of every *.sh currently present in the repo for that directory.
      local missing=0
      local sh
      for sh in "${repo_dir}"/*.sh; do
        # When no match, keep the literal pattern; guard it.
        [[ -e "${sh}" ]] || continue
        local rel="${sh#sillytavern-toolkit/}"
        if ! printf '%s\n' "${files_list}" | grep -Fx "${rel}" >/dev/null; then
          echo "missing from install_from_proxy files[]: ${rel}" >&2
          missing=1
        fi
      done
      [[ "${missing}" -eq 0 ]]
    }

    require_dir_covered "scripts/lib" "sillytavern-toolkit/scripts/lib"
    require_dir_covered "scripts/docker" "sillytavern-toolkit/scripts/docker"
    require_dir_covered "scripts/sillytavern" "sillytavern-toolkit/scripts/sillytavern"
  '

  assert_status_eq 0
}

@test "install.sh checksum manifest download is HTTPS-only and atomic backup names avoid collisions" {
  run bash -c '
    set -euo pipefail

    f="sillytavern-toolkit/install.sh"
    [[ -f "${f}" ]]

    grep -F "ST_TOOLKIT_CHECKSUMS_URL 必须使用 HTTPS" "${f}" >/dev/null
    grep -F "curl -fsSL --proto '\''=https'\'' --proto-redir '\''=https'\''" "${f}" >/dev/null

    grep -F "while [[ -e \"\${backup_dir}\" ]]; do" "${f}" >/dev/null
    grep -F "backup_dir=\"\${dst_dir}.bak_\${ts}.\${n}\"" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "install.sh checksum parser validates 64-hex hashes and supports binary marker paths" {
  run bash -c '
    set -euo pipefail

    f="sillytavern-toolkit/install.sh"
    [[ -f "${f}" ]]

    grep -F "[[ \"\${hash}\" =~ ^[0-9A-Fa-f]{64}$ ]]" "${f}" >/dev/null
    grep -F "path=\"\${path#\\*}\"" "${f}" >/dev/null
  '

  assert_status_eq 0
}

@test "install.sh verifies checksum manifest final line without trailing newline" {
  if ! command -v sha256sum &>/dev/null; then
    skip "sha256sum is required for checksum verification tests."
  fi

  run bash -c '
    set -euo pipefail

    f="sillytavern-toolkit/install.sh"
    [[ -f "${f}" ]]

    lib="${BATS_TEST_TMPDIR}/install-lib.sh"
    sed '\''$d'\'' "${f}" > "${lib}"
    . "${lib}"

    work="${BATS_TEST_TMPDIR}/checksum_no_newline"
    mkdir -p "${work}/root/scripts"
    printf "payload" > "${work}/root/scripts/common.sh"
    hash="$(sha256sum "${work}/root/scripts/common.sh" | awk "{print \$1}")"
    printf "%s  %s" "${hash}" "scripts/common.sh" > "${work}/manifest.sha256"

    fatal() { echo "$*" >&2; exit 1; }
    msg_warn() { :; }
    msg_ok() { :; }
    CHECKSUMS_URL="https://example.test/checksums.sha256"
    verify_checksums_manifest "${work}/root" "${work}/manifest.sha256" "scripts/common.sh"
  '

  assert_status_eq 0
}
