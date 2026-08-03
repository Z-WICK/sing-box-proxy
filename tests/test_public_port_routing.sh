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

DATA_DIR="${ROOT_DIR}/tests/fixtures/data"
TOOLS_DIR="${ROOT_DIR}/tools"
PUBLIC_HAPROXY_CONFIG_PATH="${ROOT_DIR}/tests/fixtures/haproxy-anytls.cfg"
SNELL_FETCH_LATEST_RELEASES="false"

# Load the shared manager helpers without entering the interactive menu.
source <(sed '$d' "${ROOT_DIR}/scripts/sing-box-proxy-manager.sh")

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/modules/vless_reality.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/modules/socks5.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/modules/snell.sh"

assert_eq "443" "$(resolve_public_listen_port 4443)" "shared HAProxy resolver"
assert_eq "443" "$(resolve_vless_reality_client_port 4443)" "VLESS public port"
assert_eq "443" "$(resolve_socks5_client_port 4443)" "SOCKS5 public port"
assert_eq "443" "$(resolve_snell_client_port 4443)" "Snell public port"

assert_eq "443" "$(build_vless_reality_uri "203.0.113.10" "$(resolve_vless_reality_client_port 4443)" "00000000-0000-0000-0000-000000000001" "www.example.com" "public-key" "0123456789abcdef" "xtls-rprx-vision" "Node" | sed -E 's#.*@[^:]+:([0-9]+)\?.*#\1#')" "VLESS URI public port"
assert_eq "443" "$(build_socks5_uri "203.0.113.10" "$(resolve_socks5_client_port 4443)" "proxy" "test-password" "Node" | sed -E 's#.*@[^:]+:([0-9]+).*#\1#')" "SOCKS5 URI public port"
assert_eq "Node = snell, 203.0.113.10, 443, psk=test-psk, version=6, tfo=true, mode=default, reuse=true, ecn=true" "$(build_snell_surge_line "Node" "203.0.113.10" "$(resolve_snell_client_port 4443)" "test-psk" "6" "true" "off" "" "default")" "Snell Surge public port"

VLESS_REALITY_PUBLIC_LISTEN_PORT="2053"
SOCKS5_PUBLIC_LISTEN_PORT="2054"
SNELL_PUBLIC_LISTEN_PORT="2055"
assert_eq "2053" "$(resolve_vless_reality_client_port 4443)" "VLESS explicit public port"
assert_eq "2054" "$(resolve_socks5_client_port 4443)" "SOCKS5 explicit public port"
assert_eq "2055" "$(resolve_snell_client_port 4443)" "Snell explicit public port"

PUBLIC_HAPROXY_CONFIG_PATH="${ROOT_DIR}/tests/fixtures/does-not-exist.cfg"
VLESS_REALITY_PUBLIC_LISTEN_PORT=""
SOCKS5_PUBLIC_LISTEN_PORT=""
SNELL_PUBLIC_LISTEN_PORT=""
assert_eq "4443" "$(resolve_vless_reality_client_port 4443)" "VLESS direct port fallback"
assert_eq "4443" "$(resolve_socks5_client_port 4443)" "SOCKS5 direct port fallback"
assert_eq "4443" "$(resolve_snell_client_port 4443)" "Snell direct port fallback"

printf "ok\n"
