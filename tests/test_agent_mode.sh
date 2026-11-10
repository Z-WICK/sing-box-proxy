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
SNELL_FETCH_LATEST_RELEASES="false"

# Load the shared manager helpers without entering the interactive menu.
source <(sed '$d' "${ROOT_DIR}/scripts/sing-box-proxy-manager.sh")

# JSON escaping
assert_eq '"plain"' "$(agent_json_string "plain")" "plain string"
assert_eq '"a\"b\\c"' "$(agent_json_string 'a"b\c')" "quote and backslash"
assert_eq '"line1\nline2\ttab"' "$(agent_json_string $'line1\nline2\ttab')" "newline and tab"
assert_eq '"\u0001"' "$(agent_json_string $'\x01')" "control character"
assert_eq '"中文"' "$(agent_json_string "中文")" "utf-8 passthrough"

# Stub system interactions.
systemctl() {
  case "$1" in
    list-unit-files)
      printf "sing-box-socks5.service enabled enabled\nsing-box-custom.service disabled enabled\nnginx.service enabled enabled\n"
      ;;
    cat)
      case "$2" in
        snell-server.service) printf "[Service]\nExecStart=/usr/local/bin/snell-server -c /etc/snell/config.conf\n" ;;
        sing-box-socks5.service) printf "[Service]\nExecStart=/usr/local/bin/sing-box run -c /nonexistent/socks5.json\n" ;;
        sing-box-custom.service) printf "[Service]\nExecStart=/usr/local/bin/sing-box run -c /nonexistent/custom.json\n" ;;
        *) return 1 ;;
      esac
      ;;
    is-active) printf "active\n" ;;
    is-enabled) printf "enabled\n" ;;
    *) printf "systemctl %s\n" "$*" ;;
  esac
}
current_version() { printf '1.2.3'; }
default_server_identity() { printf '203.0.113.10'; }
hostname() { printf 'test"host'; }

units="$(agent_managed_units | tr '\n' ' ')"
assert_eq "sing-box-socks5.service sing-box-custom.service snell-server.service " "$units" "managed units"

status_json="$(agent_status)"
STATUS_JSON="$status_json" python3 - <<'PY' || fail "agent status is not valid JSON or has wrong content"
import json, os
data = json.loads(os.environ["STATUS_JSON"])
assert data["hostname"] == 'test"host', data["hostname"]
assert data["server_identity"] == "203.0.113.10"
assert data["singbox"] == {"installed": True, "version": "1.2.3", "binary": "/usr/local/bin/sing-box"}
units = {s["unit"]: s for s in data["services"]}
assert set(units) == {"sing-box-socks5.service", "sing-box-custom.service", "snell-server.service"}, units
assert units["sing-box-socks5.service"]["protocol"] == "socks5"
assert units["sing-box-custom.service"]["protocol"] == "sing-box"
assert units["snell-server.service"]["protocol"] == "snell"
assert units["snell-server.service"]["config"] == "/etc/snell/config.conf"
PY

# Only units managed by this script may be controlled.
( agent_require_managed_unit "sing-box-socks5.service" ) || fail "managed unit rejected"
if ( agent_require_managed_unit "nginx.service" ) 2>/dev/null; then
  fail "unmanaged unit accepted"
fi
if ( agent_require_managed_unit "bad;name.service" ) 2>/dev/null; then
  fail "invalid unit name accepted"
fi

assert_eq "systemctl restart sing-box-socks5.service" "$(agent_service sing-box-socks5.service restart 2>/dev/null)" "service restart"
if ( agent_service sing-box-socks5.service mask ) 2>/dev/null; then
  fail "unsupported service action accepted"
fi
if ( agent_logs sing-box-socks5.service 999999 ) 2>/dev/null; then
  fail "oversized log line count accepted"
fi
if ( agent_main bogus ) 2>/dev/null; then
  fail "unknown agent command accepted"
fi

printf "PASS: agent mode\n"
