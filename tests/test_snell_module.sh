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

SNELL_TEST_TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$SNELL_TEST_TMP"
}
trap cleanup EXIT

DATA_DIR="${SNELL_TEST_TMP}/data"
SNELL_CONFIG_DIR="${SNELL_TEST_TMP}/etc/snell"
SNELL_CONFIG_PATH="${SNELL_CONFIG_DIR}/config.conf"
SNELL_BINARY_PATH="${SNELL_TEST_TMP}/usr/local/bin/snell-server"
SNELL_VERSION_FILE="${SNELL_CONFIG_DIR}/ver.txt"

PROTOCOL_MENU_LINES=()
register_protocol_menu_item() {
  PROTOCOL_MENU_LINES+=("$1|$2|$3")
}

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/modules/snell.sh"

register_snell_menu_items
assert_eq "Snell|配置向导|snell_wizard_flow" "${PROTOCOL_MENU_LINES[0]}" "Snell wizard menu item"
assert_eq "Snell|查看参数|show_snell_parameters_flow" "${PROTOCOL_MENU_LINES[1]}" "Snell show menu item"

validate_snell_psk "Abc123_.-:=" || fail "valid psk rejected"
if validate_snell_psk "bad space"; then
  fail "psk with spaces accepted"
fi

validate_snell_obfs "off" || fail "obfs off rejected"
validate_snell_obfs "tls" || fail "obfs tls rejected"
validate_snell_obfs "http" || fail "obfs http rejected"
if validate_snell_obfs "ws"; then
  fail "invalid obfs accepted"
fi

validate_snell_version "4" || fail "version 4 rejected"
validate_snell_version "5" || fail "version 5 rejected"
if validate_snell_version "3"; then
  fail "unsupported version 3 accepted"
fi

mkdir -p "$(dirname "$SNELL_BINARY_PATH")"
printf '#!/usr/bin/env sh\nexit 0\n' > "$SNELL_BINARY_PATH"
chmod +x "$SNELL_BINARY_PATH"

write_snell_config "$SNELL_CONFIG_PATH" "2345" "abcDEF123456" "off" "" "false" "true" "1.1.1.1, 8.8.8.8" "5"
assert_file_contains "$SNELL_CONFIG_PATH" "[snell-server]" "config header"
assert_file_contains "$SNELL_CONFIG_PATH" "listen = ::0:2345" "listen config"
assert_file_contains "$SNELL_CONFIG_PATH" "psk = abcDEF123456" "psk config"
assert_file_contains "$SNELL_CONFIG_PATH" "obfs = off" "obfs config"
assert_file_contains "$SNELL_CONFIG_PATH" "version = 5" "version config"

parsed="$(extract_snell_config_details "$SNELL_CONFIG_PATH")"
declare -A details=()
while IFS=$'\t' read -r key value; do
  details["$key"]="$value"
done <<< "$parsed"

assert_eq "true" "${details[found]}" "parsed found"
assert_eq "2345" "${details[port]}" "parsed port"
assert_eq "abcDEF123456" "${details[psk]}" "parsed psk"
assert_eq "off" "${details[obfs]}" "parsed obfs"
assert_eq "5" "${details[version]}" "parsed version"

set_snell_config_protocol_version "$SNELL_CONFIG_PATH" "4"
parsed="$(extract_snell_config_details "$SNELL_CONFIG_PATH")"
details=()
while IFS=$'\t' read -r key value; do
  details["$key"]="$value"
done <<< "$parsed"
assert_eq "4" "${details[version]}" "updated protocol version"
assert_eq "abcDEF123456" "${details[psk]}" "updated config keeps psk"

surge_line="$(build_snell_surge_line "Node" "203.0.113.10" "2345" "abcDEF123456" "5" "true" "off" "")"
assert_eq "Node = snell, 203.0.113.10, 2345, psk=abcDEF123456, version=5, tfo=true, reuse=true, ecn=true" "$surge_line" "surge line without obfs"

surge_line="$(build_snell_surge_line "Node" "203.0.113.10" "2345" "abcDEF123456" "5" "true" "tls" "example.com")"
assert_eq "Node = snell, 203.0.113.10, 2345, psk=abcDEF123456, version=5, tfo=true, obfs=tls, obfs-host=example.com, reuse=true, ecn=true" "$surge_line" "surge line with obfs"

printf "ok\n"
