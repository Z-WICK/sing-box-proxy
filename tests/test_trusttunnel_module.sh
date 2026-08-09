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

TRUSTTUNNEL_TEST_TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TRUSTTUNNEL_TEST_TMP"
}
trap cleanup EXIT

DATA_DIR="${TRUSTTUNNEL_TEST_TMP}/data"
TOOLS_DIR="${ROOT_DIR}/tools"
PUBLIC_HAPROXY_CONFIG_PATH="${ROOT_DIR}/tests/fixtures/haproxy-anytls.cfg"
# Load shared manager helpers without entering the interactive menu.
source <(sed '$d' "${ROOT_DIR}/scripts/sing-box-proxy-manager.sh")

TRUSTTUNNEL_INSTALL_DIR="${TRUSTTUNNEL_TEST_TMP}/trusttunnel"
TRUSTTUNNEL_ENDPOINT_BINARY="${TRUSTTUNNEL_INSTALL_DIR}/trusttunnel_endpoint"
TRUSTTUNNEL_VPN_CONFIG_PATH="${TRUSTTUNNEL_INSTALL_DIR}/vpn.toml"
TRUSTTUNNEL_HOSTS_CONFIG_PATH="${TRUSTTUNNEL_INSTALL_DIR}/hosts.toml"
TRUSTTUNNEL_CREDENTIALS_PATH="${TRUSTTUNNEL_INSTALL_DIR}/credentials.toml"
TRUSTTUNNEL_RULES_PATH="${TRUSTTUNNEL_INSTALL_DIR}/rules.toml"
TRUSTTUNNEL_CERT_PATH="${TRUSTTUNNEL_INSTALL_DIR}/cert.pem"
TRUSTTUNNEL_KEY_PATH="${TRUSTTUNNEL_INSTALL_DIR}/key.pem"
TRUSTTUNNEL_METADATA_DIR="${TRUSTTUNNEL_TEST_TMP}/metadata"
TRUSTTUNNEL_PUBLIC_LISTEN_PORT=""

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/modules/trusttunnel.sh"

assert_eq "443" "$(resolve_trusttunnel_client_port 4443)" "TrustTunnel HAProxy public port"
TRUSTTUNNEL_PUBLIC_LISTEN_PORT="2053"
assert_eq "2053" "$(resolve_trusttunnel_client_port 4443)" "TrustTunnel explicit public port"
TRUSTTUNNEL_PUBLIC_LISTEN_PORT=""

validate_trusttunnel_hostname "vpn.example.com" || fail "TrustTunnel DNS hostname should be valid"
validate_trusttunnel_hostname "2.26.204.231" && fail "TrustTunnel IP should not be accepted as SNI hostname"
validate_trusttunnel_hostname "2001:db8::1" && fail "TrustTunnel IPv6 should not be accepted as SNI hostname"

mkdir -p "$TRUSTTUNNEL_INSTALL_DIR"
write_trusttunnel_credentials "$TRUSTTUNNEL_CREDENTIALS_PATH" "alice" "secret-pass"
write_trusttunnel_rules_file
write_trusttunnel_vpn_config "$TRUSTTUNNEL_VPN_CONFIG_PATH" "0.0.0.0" "4443" "true"
write_trusttunnel_hosts_config "$TRUSTTUNNEL_HOSTS_CONFIG_PATH" "vpn.example.com" "$TRUSTTUNNEL_CERT_PATH" "$TRUSTTUNNEL_KEY_PATH"

parsed="$(extract_trusttunnel_config_details "$TRUSTTUNNEL_VPN_CONFIG_PATH" "$TRUSTTUNNEL_HOSTS_CONFIG_PATH")"
declare -A details=()
while IFS=$'\t' read -r key value; do
  details["$key"]="$value"
done <<< "$parsed"

assert_eq "true" "${details[found]}" "TrustTunnel config found"
assert_eq "0.0.0.0" "${details[listen_address]}" "TrustTunnel listen address"
assert_eq "4443" "${details[listen_port]}" "TrustTunnel listen port"
assert_eq "vpn.example.com" "${details[hostname]}" "TrustTunnel TLS hostname"
assert_eq "alice" "${details[username]}" "TrustTunnel username"
assert_eq "secret-pass" "${details[password]}" "TrustTunnel password"
assert_eq "true" "${details[ipv6_available]}" "TrustTunnel IPv6 setting"
assert_file_contains "$TRUSTTUNNEL_VPN_CONFIG_PATH" "[listen_protocols.http2]" "TrustTunnel HTTP/2 listener"
assert_file_contains "$TRUSTTUNNEL_VPN_CONFIG_PATH" "direct = {}" "TrustTunnel direct forwarder"
assert_file_contains "$TRUSTTUNNEL_VPN_CONFIG_PATH" "auth_failure_status_code = 407" "TrustTunnel auth failure status"
assert_file_contains "$TRUSTTUNNEL_HOSTS_CONFIG_PATH" "hostname = \"vpn.example.com\"" "TrustTunnel main host"

cat > "$TRUSTTUNNEL_ENDPOINT_BINARY" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${TRUSTTUNNEL_TEST_TMP}/endpoint-args"
format=""
previous=""
for arg in "\$@"; do
  if [[ "\$previous" == "--format" ]]; then
    format="\$arg"
  fi
  previous="\$arg"
done
if [[ "\$format" == "deeplink" ]]; then
  printf 'tt://?test-link\n\nTo connect on mobile, you can scan QR code on the page: https://example.invalid/qr\n'
else
  printf 'hostname = "vpn.example.com"\naddresses = ["203.0.113.10:443"]\n'
fi
EOF
chmod +x "$TRUSTTUNNEL_ENDPOINT_BINARY"
client_address="203.0.113.10:$(resolve_trusttunnel_client_port 4443)"
assert_eq "tt://?test-link" "$(trusttunnel_export_client "alice" "$client_address" "Alice TT" "deeplink")" "TrustTunnel deep link export"
assert_file_contains "${TRUSTTUNNEL_TEST_TMP}/endpoint-args" "203.0.113.10:443" "TrustTunnel export public port"
client_toml="$(write_trusttunnel_client_toml "trusttunnel.service" "alice" "$client_address" "Alice TT")"
assert_file_contains "$client_toml" "addresses = [\"203.0.113.10:443\"]" "TrustTunnel TOML public port"

save_trusttunnel_metadata "trusttunnel.service" "203.0.113.10" "vpn.example.com" "alice" "Alice TT" "self-signed" "true"
metadata="$(load_trusttunnel_metadata "trusttunnel.service")"
assert_file_contains <(printf '%s\n' "$metadata") $'client_server\t203.0.113.10' "TrustTunnel metadata server"
assert_file_contains <(printf '%s\n' "$metadata") $'display_name\tAlice TT' "TrustTunnel metadata display name"

generate_trusttunnel_self_signed_certificate "vpn.example.com" "$TRUSTTUNNEL_CERT_PATH" "$TRUSTTUNNEL_KEY_PATH" >/dev/null
openssl x509 -in "$TRUSTTUNNEL_CERT_PATH" -noout -text | grep -Fq "DNS:vpn.example.com" || fail "TrustTunnel certificate SAN missing"

printf "ok\n"
