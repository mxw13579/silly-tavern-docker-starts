#!/usr/bin/env bats
# shellcheck disable=SC2016

load "../helpers/stubs.bash"

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export DOCTOR_FIXTURE="${REPO_ROOT}/tests/fixtures/doctor-redaction-input.txt"
}

redact_fixture() {
  run bash -c '
    set -euo pipefail
    source "${REPO_ROOT}/sillytavern-toolkit/scripts/doctor_report.sh"
    doctor_redact_stream <"${DOCTOR_FIXTURE}"
  '
}

assert_output_not_contains() {
  local needle="$1"
  [[ "${output}" != *"${needle}"* ]]
}

# doctor redaction fixture covers auth headers cookies tokens and env credentials
function doctor_redaction_fixture_covers_auth_headers_and_credentials { #@test
  redact_fixture

  assert_status_eq 0
  assert_output_contains "[REDACTED]"
  assert_output_contains "basicAuthUser"
  assert_output_contains "Authorization"
  assert_output_contains "Proxy-Authorization"
  assert_output_contains "Cookie"
  assert_output_contains "Set-Cookie"
  assert_output_contains "X-API-Key"

  for secret in \
    doctorBasicUserOne doctorBasicPassOne doctorEnvUserOne doctorEnvPassOne \
    doctorBearerTokenOne doctorProxyTokenOne doctorCookieOne doctorSetCookieOne \
    doctorHeaderApiKeyOne doctorYamlTokenOne doctorShellSecretOne \
    doctorSnakeApiKeyOne doctorMixedTokenOne doctorJsonTokenOne \
    doctorJsonSecretOne doctorJsonApiKeyOne doctorLogBearerOne \
    doctorLogCookieOne doctorLogTokenOne
  do
    assert_output_not_contains "${secret}"
  done
}

# doctor redaction fixture covers URL userinfo and query token keys
function doctor_redaction_fixture_covers_url_userinfo_and_query_tokens { #@test
  redact_fixture

  assert_status_eq 0
  assert_output_contains "example.com"
  assert_output_contains "example.org"
  assert_output_contains "safe=kept"

  for secret in \
    doctorUrlUserOne doctorUrlPassOne doctorUrlUserOnly \
    doctorQueryTokenOne doctorQueryKeyOne doctorQueryApiKeyOne \
    doctorAccessTokenOne
  do
    assert_output_not_contains "${secret}"
  done

  assert_output_not_contains "https://doctorUrlUserOne:doctorUrlPassOne@"
  assert_output_not_contains "https://doctorUrlUserOnly@"
}

# doctor redaction fixture covers HOME USER APP_DIR and Windows profile paths
function doctor_redaction_fixture_covers_home_user_app_dir_and_windows_paths { #@test
  redact_fixture

  assert_status_eq 0
  assert_output_contains "/data/docker/sillytavern/docker-compose.yaml"

  for secret in \
    "/home/doctorHomeUserOne" \
    "doctorOsUserOne" \
    "/home/doctorHomeUserOne/apps/sillytavern" \
    "C:\\Users\\Doctor WinUser\\AppData\\Roaming\\SillyTavern\\config.yaml" \
    "Doctor WinUser"
  do
    assert_output_not_contains "${secret}"
  done
}

# doctor report stdout applies the same redaction pipeline to captured logs
function doctor_report_stdout_applies_redaction_pipeline_to_logs { #@test
  local stub_dir app_dir calls
  stub_dir="$(make_stub_dir)"
  app_dir="${BATS_TEST_TMPDIR}/st_app"
  calls="${BATS_TEST_TMPDIR}/docker_calls"
  mkdir -p "${app_dir}/config"
  printf 'services:\n  sillytavern:\n    image: ghcr.io/sillytavern/sillytavern:latest\n' >"${app_dir}/docker-compose.yaml"
  printf 'basicAuthMode: true\nbasicAuthUser:\n  username: "doctorBasicUserOne"\n  password: "doctorBasicPassOne"\n' >"${app_dir}/config/config.yaml"
  : >"${calls}"
  write_exe "${stub_dir}/docker" \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"${DOCTOR_DOCKER_CALLS}"' \
    'case "$*" in' \
    '  "--version"|"info"|"compose version"|"compose config -q") exit 0 ;;' \
    '  "compose ps"*) printf "sillytavern running\n"; exit 0 ;;' \
    '  "compose logs"*) printf "Authorization: Bearer doctorLogBearerOne Cookie: doctorLogCookieOne token=doctorLogTokenOne\n"; exit 0 ;;' \
    'esac' \
    'exit 0'
  prepend_path "${stub_dir}"

  run env \
    APP_DIR="${app_dir}" \
    HOME="${BATS_TEST_TMPDIR}/home" \
    USER="doctorOsUserOne" \
    DOCTOR_DOCKER_CALLS="${calls}" \
    bash "${REPO_ROOT}/sillytavern-toolkit/scripts/sillytavern.sh" doctor-report --stdout --lines 1

  assert_status_eq 0
  assert_output_contains "Recent Logs"
  assert_output_not_contains "doctorLogBearerOne"
  assert_output_not_contains "doctorLogCookieOne"
  assert_output_not_contains "doctorLogTokenOne"
  assert_output_not_contains "doctorBasicPassOne"
}
