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

# ---------------------------------------------------------------------------
# 非交互答案机制
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/modules/snell.sh"
unset -f systemctl hostname
is_listen_port_occupied() { return 1; }

SBP_NONINTERACTIVE="true"

SBP_ANSWERS=([snell_port]="40123")
assert_eq "40123" "$(prompt_snell_port 2345 2>/dev/null)" "answered text prompt"

SBP_ANSWERS=()
assert_eq "2345" "$(prompt_snell_port 2345 2>/dev/null)" "empty answer falls back to default"

SBP_ANSWERS=([snell_port]="not-a-port")
if err="$( (prompt_snell_port 2345) 2>&1 >/dev/null )"; then
  fail "invalid answer should abort instead of looping"
fi
[[ "$err" == *"snell_port"* ]] || fail "invalid answer error should name the key: ${err}"

SBP_ANSWERS=([snell_psk]="short")
if err="$( (prompt_snell_psk "" 6) 2>&1 >/dev/null )"; then
  fail "invalid psk should abort"
fi
[[ "$err" != *"short"* ]] || fail "secret values must not be echoed in errors"

SBP_ANSWERS=([snell_mode]="unshaped")
assert_eq "unshaped" "$(prompt_snell_mode default 2>/dev/null)" "menu prompt accepts named answer"

SBP_ANSWERS=([confirm]="n")
if prompt_yes_no "继续？" "y" confirm 2>/dev/null; then fail "answered n should return false"; fi
SBP_ANSWERS=()
prompt_yes_no "继续？" "y" confirm 2>/dev/null || fail "missing answer should use default y"
if prompt_yes_no "删除？" "n" 2>/dev/null; then fail "keyless prompt should use default n"; fi
SBP_ANSWERS=([confirm]="maybe")
if ( prompt_yes_no "继续？" "y" confirm ) 2>/dev/null; then fail "invalid y/n answer accepted"; fi

assert_eq "false" "$(SBP_ANSWERS=([snell_tfo]="n"); prompt_snell_bool_value "TFO？" "true" snell_tfo 2>/dev/null)" "bool prompt honours key"

SBP_ANSWERS=()
agent_read_answers <<'ANSWERS'
snell_psk=abc=def==

snell_port=2346
ANSWERS
assert_eq "abc=def==" "${SBP_ANSWERS[snell_psk]}" "answer values may contain ="
assert_eq "2346" "${SBP_ANSWERS[snell_port]}" "second answer parsed"
if ( agent_read_answers <<< 'Bad-Key=1' ) 2>/dev/null; then fail "invalid answer key accepted"; fi
if ( agent_read_answers <<< 'novalue' ) 2>/dev/null; then fail "answer without = accepted"; fi

assert_eq "snell_wizard_flow" "$(agent_run_handler snell.configure)" "known action"
if agent_run_handler "rm -rf" >/dev/null; then fail "unknown action accepted"; fi
if ( agent_run bogus.action ) 2>/dev/null; then fail "agent_run accepted unknown action"; fi

SBP_NONINTERACTIVE="false"

printf "PASS: agent mode\n"
