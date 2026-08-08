#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf "FAIL: %s\n" "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "${message}: expected '${expected}', got '${actual}'"
}

assert_file_contains() {
  local file_path="$1"
  local expected="$2"
  local message="$3"

  grep -Fq "$expected" "$file_path" || fail "${message}: missing '${expected}' in ${file_path}"
}

# Load the shared manager helpers without entering the interactive menu.
source <(sed '$d' "${ROOT_DIR}/scripts/sing-box-proxy-manager.sh")

ANYTLS_TEST_TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$ANYTLS_TEST_TMP"
}
trap cleanup EXIT

DATA_DIR="${ROOT_DIR}/tests/fixtures/data"
TOOLS_DIR="${ROOT_DIR}/tools"
ANYTLS_METADATA_DIR="${ROOT_DIR}/tests/fixtures/data/metadata"
CLIENT_IMPORT_DIR="${ANYTLS_TEST_TMP}/client-import"
CLIENT_IMPORT_PUBLISH_DIR="${ANYTLS_TEST_TMP}/client-import-publish"
ANYTLS_HAPROXY_CONFIG_PATH="${ROOT_DIR}/tests/fixtures/haproxy-anytls.cfg"
ANYTLS_PUBLIC_LISTEN_PORT=""

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/modules/anytls.sh"

assert_eq "443" "$(resolve_anytls_client_port 4443)" "HAProxy frontend port"
assert_eq "5555" "$(resolve_anytls_client_port 5555)" "unmatched internal port fallback"

ANYTLS_PUBLIC_LISTEN_PORT="2053"
assert_eq "2053" "$(resolve_anytls_client_port 4443)" "explicit public port override"

ANYTLS_PUBLIC_LISTEN_PORT="not-a-port"
assert_eq "443" "$(resolve_anytls_client_port 4443)" "invalid override fallback"

profile_data="$(write_client_import_profiles "sing-box-anytls.service" "203.0.113.10" "$(resolve_anytls_client_port 4443)" "test-password" "true" "203.0.113.10" "true" "")"
surge_file=""
while IFS=$'\t' read -r key value; do
  if [[ "$key" == "surge_file" ]]; then
    surge_file="$value"
  fi
done <<< "$profile_data"
assert_file_contains "$surge_file" "AnyTLS-sing-box-anytls = anytls, 203.0.113.10, 443" "generated Surge profile public port"

ANYTLS_HAPROXY_CONFIG_PATH="${ROOT_DIR}/tests/fixtures/does-not-exist.cfg"
ANYTLS_PUBLIC_LISTEN_PORT=""
assert_eq "4443" "$(resolve_anytls_client_port 4443)" "missing HAProxy config fallback"

printf "ok\n"
