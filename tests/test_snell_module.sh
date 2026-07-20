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

assert_file_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  local message="$3"

  if grep -Fq "$unexpected" "$file_path"; then
    fail "${message}: unexpected '${unexpected}' in ${file_path}"
  fi
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
assert_eq "Snell|升级到 Snell 6|upgrade_snell_to_v6_flow" "${PROTOCOL_MENU_LINES[2]}" "Snell v6 upgrade menu item"
assert_eq "6" "$SNELL_DEFAULT_PROTOCOL_VERSION" "Snell default protocol version"

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
validate_snell_version "6" || fail "version 6 rejected"
if validate_snell_version "3"; then
  fail "unsupported version 3 accepted"
fi

validate_snell_mode "default" || fail "default mode rejected"
validate_snell_mode "unshaped" || fail "unshaped mode rejected"
validate_snell_mode "unsafe-raw" || fail "unsafe-raw mode rejected"
if validate_snell_mode "raw"; then
  fail "unsupported mode accepted"
fi

validate_snell_dns_ip_preference "prefer-ipv6" || fail "DNS preference rejected"
if validate_snell_dns_ip_preference "auto"; then
  fail "unsupported DNS preference accepted"
fi

assert_eq "4.1.1" "$(snell_release_version_for_protocol 4)" "Snell v4 release mapping"
assert_eq "5.0.1" "$(snell_release_version_for_protocol 5)" "Snell v5 release mapping"
assert_eq "6.0.0b4" "$(snell_release_version_for_protocol 6)" "Snell v6 release mapping"
assert_eq "https://dl.nssurge.com/snell/snell-server-v6.0.0b4-linux-amd64.zip" "$(snell_download_url "6.0.0b4" "amd64")" "Snell v6 download URL"
validate_snell_arch_for_release "6.0.0b4" "aarch64" || fail "Snell v6 aarch64 rejected"
if validate_snell_arch_for_release "6.0.0b4" "armv7l"; then
  fail "Snell v6 armv7l accepted"
fi

prompted_obfs="$(prompt_snell_obfs "off" 2>/dev/null <<< "")"
assert_eq "off" "$prompted_obfs" "Snell OBFS prompt stdout"

mkdir -p "$(dirname "$SNELL_BINARY_PATH")"
printf '#!/usr/bin/env sh\nprintf "snell-server v5.0.1 (test)\\n"\n' > "$SNELL_BINARY_PATH"
chmod +x "$SNELL_BINARY_PATH"
assert_eq "5.0.1" "$(installed_snell_release_version)" "detect release from binary"

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

migrate_snell_config_to_protocol "$SNELL_CONFIG_PATH" "6"
assert_file_contains "$SNELL_CONFIG_PATH" "listen = ::0:2345" "v4 to v6 keeps listen port"
assert_file_contains "$SNELL_CONFIG_PATH" "psk = abcDEF123456" "v4 to v6 keeps psk"
assert_file_contains "$SNELL_CONFIG_PATH" "mode = default" "v4 to v6 mode"
assert_file_contains "$SNELL_CONFIG_PATH" "dns-ip-preference = ipv4-only" "v4 to v6 DNS preference"
assert_file_contains "$SNELL_CONFIG_PATH" "tfo = true" "v4 to v6 keeps TFO"
assert_file_not_contains "$SNELL_CONFIG_PATH" "version =" "v6 removes server protocol version"
assert_file_not_contains "$SNELL_CONFIG_PATH" "obfs =" "v6 removes legacy obfs"
assert_file_not_contains "$SNELL_CONFIG_PATH" "ipv6 =" "v6 removes legacy IPv6 switch"

parsed="$(extract_snell_config_details "$SNELL_CONFIG_PATH")"
details=()
while IFS=$'\t' read -r key value; do
  details["$key"]="$value"
done <<< "$parsed"
assert_eq "default" "${details[mode]}" "parsed v6 mode"
assert_eq "ipv4-only" "${details[dns_ip_preference]}" "parsed v6 DNS preference"

SNELL_V5_CONFIG="${SNELL_CONFIG_DIR}/v5.conf"
write_snell_config "$SNELL_V5_CONFIG" "3456" "v5PSK12345678" "tls" "example.com" "true" "false" "1.1.1.1" "5"
migrate_snell_config_to_protocol "$SNELL_V5_CONFIG" "6"
assert_file_contains "$SNELL_V5_CONFIG" "listen = ::0:3456" "v5 to v6 keeps listen port"
assert_file_contains "$SNELL_V5_CONFIG" "psk = v5PSK12345678" "v5 to v6 keeps psk"
assert_file_contains "$SNELL_V5_CONFIG" "dns-ip-preference = default" "v5 IPv6 migration"
assert_file_contains "$SNELL_V5_CONFIG" "tfo = false" "v5 to v6 keeps TFO"
assert_file_not_contains "$SNELL_V5_CONFIG" "obfs-host" "v5 to v6 removes obfs host"

surge_line="$(build_snell_surge_line "Node" "203.0.113.10" "2345" "abcDEF123456" "5" "true" "off" "")"
assert_eq "Node = snell, 203.0.113.10, 2345, psk=abcDEF123456, version=5, tfo=true, reuse=true, ecn=true" "$surge_line" "surge line without obfs"

surge_line="$(build_snell_surge_line "Node" "203.0.113.10" "2345" "abcDEF123456" "5" "true" "tls" "example.com")"
assert_eq "Node = snell, 203.0.113.10, 2345, psk=abcDEF123456, version=5, tfo=true, obfs=tls, obfs-host=example.com, reuse=true, ecn=true" "$surge_line" "surge line with obfs"

surge_line="$(build_snell_surge_line "Node" "203.0.113.10" "2345" "abcDEF123456" "6" "true" "tls" "ignored.example.com" "unshaped")"
assert_eq "Node = snell, 203.0.113.10, 2345, psk=abcDEF123456, version=6, tfo=true, mode=unshaped, reuse=true, ecn=true" "$surge_line" "Snell v6 Surge line"

printf "ok\n"
