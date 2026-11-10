#!/usr/bin/env bash

: "${TRUSTTUNNEL_SERVICE_NAME:=trusttunnel.service}"
: "${TRUSTTUNNEL_INSTALL_DIR:=/opt/trusttunnel}"
: "${TRUSTTUNNEL_ENDPOINT_BINARY:=${TRUSTTUNNEL_INSTALL_DIR}/trusttunnel_endpoint}"
: "${TRUSTTUNNEL_SETUP_WIZARD:=${TRUSTTUNNEL_INSTALL_DIR}/setup_wizard}"
: "${TRUSTTUNNEL_VPN_CONFIG_PATH:=${TRUSTTUNNEL_INSTALL_DIR}/vpn.toml}"
: "${TRUSTTUNNEL_HOSTS_CONFIG_PATH:=${TRUSTTUNNEL_INSTALL_DIR}/hosts.toml}"
: "${TRUSTTUNNEL_CREDENTIALS_PATH:=${TRUSTTUNNEL_INSTALL_DIR}/credentials.toml}"
: "${TRUSTTUNNEL_RULES_PATH:=${TRUSTTUNNEL_INSTALL_DIR}/rules.toml}"
: "${TRUSTTUNNEL_CERT_PATH:=${TRUSTTUNNEL_INSTALL_DIR}/cert.pem}"
: "${TRUSTTUNNEL_KEY_PATH:=${TRUSTTUNNEL_INSTALL_DIR}/key.pem}"
: "${TRUSTTUNNEL_STANDARD_LISTEN_ADDR:=0.0.0.0}"
: "${TRUSTTUNNEL_STANDARD_LISTEN_PORT:=443}"
: "${TRUSTTUNNEL_FALLBACK_LISTEN_PORT:=8443}"
: "${TRUSTTUNNEL_PUBLIC_LISTEN_PORT:=}"
: "${TRUSTTUNNEL_METADATA_DIR:=/etc/trusttunnel-meta}"
: "${TRUSTTUNNEL_INSTALL_SCRIPT_URL:=https://raw.githubusercontent.com/TrustTunnel/TrustTunnel/refs/heads/master/scripts/install.sh}"
: "${TRUSTTUNNEL_DEFAULT_USERNAME:=trusttunnel}"
: "${TRUSTTUNNEL_DEFAULT_IPV6_AVAILABLE:=true}"
: "${TRUSTTUNNEL_DEFAULT_DISPLAY_NAME:=TrustTunnel}"

register_trusttunnel_menu_items() {
  register_protocol_menu_item "TrustTunnel" "配置向导" "trusttunnel_wizard_flow"
  register_protocol_menu_item "TrustTunnel" "查看参数" "show_trusttunnel_parameters_flow"
  register_protocol_menu_item "TrustTunnel" "更新 endpoint" "update_trusttunnel_flow"
  register_protocol_menu_item "TrustTunnel" "卸载 endpoint" "uninstall_trusttunnel_flow"
}

resolve_trusttunnel_client_port() {
  local internal_port="$1"
  resolve_public_listen_port "$internal_port" "${TRUSTTUNNEL_PUBLIC_LISTEN_PORT:-}" "${PUBLIC_HAPROXY_CONFIG_PATH:-/etc/haproxy/haproxy.cfg}"
}

validate_trusttunnel_port() {
  local value="$1"
  if declare -F is_valid_port >/dev/null 2>&1; then
    is_valid_port "$value"
    return
  fi
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  (( value >= 1 && value <= 65535 ))
}

validate_trusttunnel_hostname() {
  local value="$1"
  [[ "$value" != *:* ]] &&
    [[ ! "$value" =~ ^[0-9]+(\.[0-9]+){3}$ ]] &&
    [[ "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

validate_trusttunnel_username() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9_.@-]{1,64}$ ]]
}

validate_trusttunnel_password() {
  local value="$1"
  [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

validate_trusttunnel_bool() {
  local value="$1"
  [[ "$value" == "true" || "$value" == "false" ]]
}

validate_trusttunnel_path() {
  local value="$1"
  [[ "$value" == /* && "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

trusttunnel_metadata_path_for_service() {
  local service_name service_base
  service_name="$(normalize_service_name "$1")"
  service_base="$service_name"
  service_base="$(printf '%s' "$service_base" | sed 's/\.service$//')"
  printf "%s/%s.json" "$TRUSTTUNNEL_METADATA_DIR" "$service_base"
}

save_trusttunnel_metadata() {
  local service_name="$1"
  local client_server="$2"
  local hostname="$3"
  local username="$4"
  local display_name="$5"
  local cert_mode="$6"
  local ipv6_available="$7"
  local metadata_path

  metadata_path="$(trusttunnel_metadata_path_for_service "$service_name")"
  mkdir -p "$TRUSTTUNNEL_METADATA_DIR"

  TRUSTTUNNEL_METADATA_PATH="$metadata_path" \
  TRUSTTUNNEL_CLIENT_SERVER="$client_server" \
  TRUSTTUNNEL_HOSTNAME="$hostname" \
  TRUSTTUNNEL_USERNAME="$username" \
  TRUSTTUNNEL_DISPLAY_NAME="$display_name" \
  TRUSTTUNNEL_CERT_MODE="$cert_mode" \
  TRUSTTUNNEL_IPV6_AVAILABLE="$ipv6_available" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ['TRUSTTUNNEL_METADATA_PATH'])
payload = {
    'client_server': os.environ.get('TRUSTTUNNEL_CLIENT_SERVER', ''),
    'hostname': os.environ.get('TRUSTTUNNEL_HOSTNAME', ''),
    'username': os.environ.get('TRUSTTUNNEL_USERNAME', ''),
    'display_name': os.environ.get('TRUSTTUNNEL_DISPLAY_NAME', ''),
    'cert_mode': os.environ.get('TRUSTTUNNEL_CERT_MODE', 'self-signed'),
    'ipv6_available': os.environ.get('TRUSTTUNNEL_IPV6_AVAILABLE', 'true').lower() == 'true',
}
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
path.chmod(0o600)
PY
}

load_trusttunnel_metadata() {
  local service_name="$1"
  local metadata_path
  metadata_path="$(trusttunnel_metadata_path_for_service "$service_name")"

  [[ -f "$metadata_path" ]] || return 0

  TRUSTTUNNEL_METADATA_PATH="$metadata_path" python3 - <<'PY'
import json
import os

try:
    with open(os.environ['TRUSTTUNNEL_METADATA_PATH'], 'r', encoding='utf-8') as fp:
        data = json.load(fp)
except Exception:
    raise SystemExit(0)

def emit(key, value):
    if isinstance(value, bool):
        value = 'true' if value else 'false'
    print(f"{key}\t{'' if value is None else value}")

emit('client_server', data.get('client_server', ''))
emit('hostname', data.get('hostname', ''))
emit('username', data.get('username', ''))
emit('display_name', data.get('display_name', ''))
emit('cert_mode', data.get('cert_mode', 'self-signed'))
emit('ipv6_available', data.get('ipv6_available', True))
PY
}

write_trusttunnel_credentials() {
  local credentials_path="$1"
  local username="$2"
  local password="$3"

  mkdir -p "$(dirname "$credentials_path")"
  TRUSTTUNNEL_CREDENTIALS_PATH="$credentials_path" \
  TRUSTTUNNEL_CREDENTIALS_USERNAME="$username" \
  TRUSTTUNNEL_CREDENTIALS_PASSWORD="$password" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ['TRUSTTUNNEL_CREDENTIALS_PATH'])
username = os.environ['TRUSTTUNNEL_CREDENTIALS_USERNAME']
password = os.environ['TRUSTTUNNEL_CREDENTIALS_PASSWORD']
content = (
    '[[client]]\n'
    f'username = {json.dumps(username, ensure_ascii=False)}\n'
    f'password = {json.dumps(password, ensure_ascii=False)}\n'
)
path.write_text(content, encoding='utf-8')
path.chmod(0o600)
PY
}

write_trusttunnel_vpn_config() {
  local config_path="$1"
  local listen_addr="$2"
  local listen_port="$3"
  local ipv6_available="$4"

  mkdir -p "$(dirname "$config_path")"
  TRUSTTUNNEL_VPN_CONFIG_PATH="$config_path" \
  TRUSTTUNNEL_LISTEN_ADDR="$listen_addr" \
  TRUSTTUNNEL_LISTEN_PORT="$listen_port" \
  TRUSTTUNNEL_IPV6_AVAILABLE="$ipv6_available" \
  TRUSTTUNNEL_CREDENTIALS_CONFIG_PATH="$TRUSTTUNNEL_CREDENTIALS_PATH" \
  TRUSTTUNNEL_RULES_CONFIG_PATH="$TRUSTTUNNEL_RULES_PATH" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ['TRUSTTUNNEL_VPN_CONFIG_PATH'])
listen_address = f"{os.environ['TRUSTTUNNEL_LISTEN_ADDR']}:{int(os.environ['TRUSTTUNNEL_LISTEN_PORT'])}"
ipv6_available = os.environ['TRUSTTUNNEL_IPV6_AVAILABLE'] == 'true'
q = lambda value: json.dumps(value, ensure_ascii=False)

content = f'''listen_address = {q(listen_address)}
ipv6_available = {str(ipv6_available).lower()}
allow_private_network_connections = false
tls_handshake_timeout_secs = 10
client_listener_timeout_secs = 600
connection_establishment_timeout_secs = 30
tcp_connections_timeout_secs = 604800
udp_connections_timeout_secs = 300
credentials_file = {q(os.environ['TRUSTTUNNEL_CREDENTIALS_CONFIG_PATH'])}
rules_file = {q(os.environ['TRUSTTUNNEL_RULES_CONFIG_PATH'])}
speedtest_enable = false
ping_enable = false
auth_failure_status_code = 407

[forward_protocol]
direct = {{}}

[listen_protocols.http1]
upload_buffer_size = 32768

[listen_protocols.http2]
initial_connection_window_size = 8388608
initial_stream_window_size = 131072
max_concurrent_streams = 1000
max_frame_size = 16384
header_table_size = 65536
'''
path.write_text(content, encoding='utf-8')
path.chmod(0o600)
PY
}

write_trusttunnel_hosts_config() {
  local config_path="$1"
  local hostname="$2"
  local cert_path="$3"
  local key_path="$4"

  mkdir -p "$(dirname "$config_path")"
  TRUSTTUNNEL_HOSTS_CONFIG_PATH="$config_path" \
  TRUSTTUNNEL_MAIN_HOSTNAME="$hostname" \
  TRUSTTUNNEL_CERT_CHAIN_PATH="$cert_path" \
  TRUSTTUNNEL_PRIVATE_KEY_PATH="$key_path" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ['TRUSTTUNNEL_HOSTS_CONFIG_PATH'])
q = lambda value: json.dumps(value, ensure_ascii=False)
content = (
    '[[main_hosts]]\n'
    f'hostname = {q(os.environ["TRUSTTUNNEL_MAIN_HOSTNAME"])}\n'
    f'cert_chain_path = {q(os.environ["TRUSTTUNNEL_CERT_CHAIN_PATH"])}\n'
    f'private_key_path = {q(os.environ["TRUSTTUNNEL_PRIVATE_KEY_PATH"])}\n'
)
path.write_text(content, encoding='utf-8')
path.chmod(0o600)
PY
}

write_trusttunnel_rules_file() {
  mkdir -p "$(dirname "$TRUSTTUNNEL_RULES_PATH")"
  cat > "$TRUSTTUNNEL_RULES_PATH" <<'EOF'
# TrustTunnel rules are intentionally empty: connections are allowed by default.
EOF
  chmod 600 "$TRUSTTUNNEL_RULES_PATH"
}

generate_trusttunnel_self_signed_certificate() {
  local hostname="$1"
  local cert_path="$2"
  local key_path="$3"
  local san_type san_value openssl_config

  command -v openssl >/dev/null 2>&1 || die "生成 TrustTunnel 自签证书需要 openssl。"

  if [[ "$hostname" == *:* || "$hostname" =~ ^[0-9.]+$ ]]; then
    san_type="IP"
  else
    san_type="DNS"
  fi
  san_value="${san_type}:${hostname}"
  openssl_config="$(mktemp)"
  cat > "$openssl_config" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = ${hostname}

[v3_req]
subjectAltName = ${san_value}
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

  mkdir -p "$(dirname "$cert_path")" "$(dirname "$key_path")"
  if ! openssl req -x509 -nodes -newkey rsa:2048 \
    -days 3650 -keyout "$key_path" -out "$cert_path" \
    -config "$openssl_config" >/dev/null 2>&1; then
    rm -f "$openssl_config"
    die "生成 TrustTunnel 自签证书失败。"
  fi
  rm -f "$openssl_config"
  chmod 644 "$cert_path"
  chmod 600 "$key_path"
  ok "已生成 TrustTunnel 自签证书: ${cert_path}"
}

trusttunnel_service_exists() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  systemctl cat "$service_name" >/dev/null 2>&1
}

install_trusttunnel_endpoint() {
  local installer_path
  installer_path="$(mktemp)"

  info "正在下载 TrustTunnel 官方安装脚本。"
  if ! curl -fsSL "$TRUSTTUNNEL_INSTALL_SCRIPT_URL" -o "$installer_path"; then
    rm -f "$installer_path"
    die "下载 TrustTunnel 官方安装脚本失败。"
  fi

  if ! sh "$installer_path" -o "$TRUSTTUNNEL_INSTALL_DIR" -a y; then
    rm -f "$installer_path"
    die "TrustTunnel endpoint 安装失败。"
  fi
  rm -f "$installer_path"

  [[ -x "$TRUSTTUNNEL_ENDPOINT_BINARY" ]] || die "安装完成但未找到 TrustTunnel endpoint: ${TRUSTTUNNEL_ENDPOINT_BINARY}"
  ok "TrustTunnel endpoint 已安装: ${TRUSTTUNNEL_ENDPOINT_BINARY}"
}

write_trusttunnel_service_file() {
  local service_file
  service_file="$(service_unit_file_path "$TRUSTTUNNEL_SERVICE_NAME")"

  cat > "$service_file" <<EOF
[Unit]
Description=TrustTunnel endpoint
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${TRUSTTUNNEL_INSTALL_DIR}
ExecStart=${TRUSTTUNNEL_ENDPOINT_BINARY} ${TRUSTTUNNEL_VPN_CONFIG_PATH} ${TRUSTTUNNEL_HOSTS_CONFIG_PATH}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  ok "已写入 TrustTunnel 服务文件: ${service_file}"
}

extract_trusttunnel_config_details() {
  local vpn_path="$1"
  local hosts_path="$2"

  [[ -f "$vpn_path" && -f "$hosts_path" ]] || return 0
  TRUSTTUNNEL_VPN_CONFIG_PATH="$vpn_path" \
  TRUSTTUNNEL_HOSTS_CONFIG_PATH="$hosts_path" \
  python3 - <<'PY'
import json
import os
import re
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None

vpn_path = Path(os.environ['TRUSTTUNNEL_VPN_CONFIG_PATH'])
hosts_path = Path(os.environ['TRUSTTUNNEL_HOSTS_CONFIG_PATH'])

def emit(key, value):
    if isinstance(value, bool):
        value = 'true' if value else 'false'
    print(f"{key}\t{'' if value is None else value}")

def parse_simple_toml(path):
    top = {}
    arrays = {}
    current = top
    for raw_line in path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        array_match = re.fullmatch(r'\[\[([^]]+)\]\]', line)
        if array_match:
            name = array_match.group(1).strip()
            current = {}
            arrays.setdefault(name, []).append(current)
            continue
        if re.fullmatch(r'\[[^]]+\]', line):
            current = top
            continue
        value_match = re.match(r'^([A-Za-z0-9_-]+)\s*=\s*(.*?)\s*(?:#.*)?$', line)
        if not value_match:
            continue
        key, raw_value = value_match.groups()
        try:
            value = json.loads(raw_value)
        except Exception:
            if raw_value.lower() in ('true', 'false'):
                value = raw_value.lower() == 'true'
            else:
                try:
                    value = int(raw_value)
                except ValueError:
                    value = raw_value.strip('"\'')
        current[key] = value
    top.update(arrays)
    return top

def load_toml(path):
    if tomllib is not None:
        with path.open('rb') as fp:
            return tomllib.load(fp)
    return parse_simple_toml(path)

try:
    vpn = load_toml(vpn_path)
    hosts = load_toml(hosts_path)
except Exception:
    emit('found', 'false')
    raise SystemExit(0)

main_hosts = hosts.get('main_hosts') or []
main_host = main_hosts[0] if main_hosts and isinstance(main_hosts[0], dict) else {}
listen_address = str(vpn.get('listen_address') or '')
credentials_path = str(vpn.get('credentials_file') or '')
if credentials_path and not credentials_path.startswith('/'):
    credentials_path = str((vpn_path.parent / credentials_path).resolve())

username = ''
password = ''
if credentials_path:
    try:
        credentials = load_toml(Path(credentials_path))
        clients = credentials.get('client') or []
        client = clients[0] if clients and isinstance(clients[0], dict) else {}
        username = str(client.get('username') or '')
        password = str(client.get('password') or '')
    except Exception:
        pass

listen_port = ''
if ':' in listen_address:
    listen_port = listen_address.rsplit(':', 1)[-1]

emit('found', 'true' if listen_address and main_host.get('hostname') else 'false')
emit('listen_address', listen_address.rsplit(':', 1)[0] if listen_port else listen_address)
emit('listen_port', listen_port)
emit('hostname', main_host.get('hostname', ''))
emit('cert_chain_path', main_host.get('cert_chain_path', ''))
emit('private_key_path', main_host.get('private_key_path', ''))
emit('credentials_file', credentials_path)
emit('rules_file', vpn.get('rules_file', ''))
emit('ipv6_available', vpn.get('ipv6_available', True))
emit('username', username)
emit('password', password)
PY
}

trusttunnel_export_client() {
  local username="$1"
  local address="$2"
  local display_name="$3"
  local format="$4"
  local args=()

  [[ -x "$TRUSTTUNNEL_ENDPOINT_BINARY" ]] || return 1
  args=("$TRUSTTUNNEL_ENDPOINT_BINARY" "$TRUSTTUNNEL_VPN_CONFIG_PATH" "$TRUSTTUNNEL_HOSTS_CONFIG_PATH" --client_config "$username" --address "$address")
  if [[ -n "$display_name" ]]; then
    args+=(--name "$display_name")
  fi
  args+=(--format "$format")
  if [[ "$format" == "deeplink" ]]; then
    "${args[@]}" 2>/dev/null | sed -n '1p'
  else
    "${args[@]}" 2>/dev/null
  fi
}

write_trusttunnel_client_toml() {
  local service_name="$1"
  local username="$2"
  local address="$3"
  local display_name="$4"
  local service_base output_path

  service_base="$service_name"
  service_base="$(printf '%s' "$service_base" | sed 's/\.service$//')"
  output_path="${TRUSTTUNNEL_INSTALL_DIR}/${service_base}-client.toml"
  if ! trusttunnel_export_client "$username" "$address" "$display_name" "toml" > "$output_path"; then
    rm -f "$output_path"
    return 1
  fi
  chmod 600 "$output_path"
  printf "%s" "$output_path"
}

show_trusttunnel_parameters_for_service() {
  local service_name="$1"
  local parsed

  service_name="$(normalize_service_name "$service_name")"
  if ! trusttunnel_service_exists "$service_name"; then
    warn "未找到 TrustTunnel 服务: ${service_name}"
    return 1
  fi
  if [[ ! -f "$TRUSTTUNNEL_VPN_CONFIG_PATH" || ! -f "$TRUSTTUNNEL_HOSTS_CONFIG_PATH" ]]; then
    warn "未找到 TrustTunnel 配置文件。"
    return 1
  fi

  parsed="$(extract_trusttunnel_config_details "$TRUSTTUNNEL_VPN_CONFIG_PATH" "$TRUSTTUNNEL_HOSTS_CONFIG_PATH")"
  local found listen_addr listen_port hostname cert_path key_path ipv6_available username password
  found="false"
  listen_addr=""
  listen_port=""
  hostname=""
  cert_path=""
  key_path=""
  ipv6_available="true"
  username=""
  password=""

  while IFS=$'$\t' read -r key value; do
    case "$key" in
      found) found="$value" ;;
      listen_address) listen_addr="$value" ;;
      listen_port) listen_port="$value" ;;
      hostname) hostname="$value" ;;
      cert_chain_path) cert_path="$value" ;;
      private_key_path) key_path="$value" ;;
      ipv6_available) ipv6_available="$value" ;;
      username) username="$value" ;;
      password) password="$value" ;;
    esac
  done <<< "$parsed"

  if [[ "$found" != "true" ]]; then
    warn "TrustTunnel 配置解析失败: ${TRUSTTUNNEL_VPN_CONFIG_PATH}"
    return 1
  fi

  local client_server display_name cert_mode metadata_loaded
  client_server="$(default_server_identity)"
  display_name="$TRUSTTUNNEL_DEFAULT_DISPLAY_NAME"
  cert_mode="self-signed"
  metadata_loaded="$(load_trusttunnel_metadata "$service_name")"
  if [[ -n "$metadata_loaded" ]]; then
    while IFS=$'$\t' read -r key value; do
      case "$key" in
        client_server) [[ -n "$value" ]] && client_server="$value" ;;
        display_name) [[ -n "$value" ]] && display_name="$value" ;;
        cert_mode) [[ -n "$value" ]] && cert_mode="$value" ;;
      esac
    done <<< "$metadata_loaded"
  fi
  if ! validate_client_server "$client_server"; then
    client_server="$(default_server_identity)"
  fi

  local client_port client_address deep_link client_toml active_state enabled_state
  client_port="$(resolve_trusttunnel_client_port "$listen_port")"
  client_address="$(format_host_for_url "$client_server"):${client_port}"
  active_state="$(systemctl is-active "$service_name" 2>/dev/null || true)"
  enabled_state="$(systemctl is-enabled "$service_name" 2>/dev/null || true)"

  printf "\nTrustTunnel 参数：\n"
  printf "  服务名      : %s\n" "$service_name"
  printf "  状态        : active=%s | enabled=%s\n" "$active_state" "$enabled_state"
  printf "  二进制      : %s\n" "$TRUSTTUNNEL_ENDPOINT_BINARY"
  printf "  服务器      : %s\n" "$client_server"
  printf "  TLS 主机名  : %s\n" "$hostname"
  printf "  监听地址    : %s\n" "$listen_addr"
  printf "  端口        : %s\n" "$client_port"
  if [[ "$client_port" != "$listen_port" ]]; then
    printf "  内部监听    : %s:%s\n" "${listen_addr:-*}" "$listen_port"
  fi
  printf "  用户名      : %s\n" "$username"
  printf "  密码        : %s\n" "$password"
  printf "  IPv6 路由   : %s\n" "$ipv6_available"
  printf "  证书模式    : %s\n" "$cert_mode"
  printf "  证书        : %s\n" "$cert_path"
  printf "  私钥        : %s\n" "$key_path"
  printf "  配置文件    : %s\n" "$TRUSTTUNNEL_VPN_CONFIG_PATH"
  printf "  客户端地址  : %s\n" "$client_address"

  deep_link="$(trusttunnel_export_client "$username" "$client_address" "$display_name" "deeplink" || true)"
  if [[ -n "$deep_link" ]]; then
    printf "\nTrustTunnel 深链：\n"
    printf "  %s\n" "$deep_link"
  else
    warn "无法生成 TrustTunnel 深链，请检查 endpoint 配置和凭据。"
  fi

  client_toml="$(write_trusttunnel_client_toml "$service_name" "$username" "$client_address" "$display_name" || true)"
  if [[ -n "$client_toml" ]]; then
    printf "\nTrustTunnel TOML 客户端配置：\n"
    printf "  文件      : %s\n" "$client_toml"
    sed 's/^/  /' "$client_toml"
  fi
}

show_trusttunnel_parameters_flow() {
  show_trusttunnel_parameters_for_service "$TRUSTTUNNEL_SERVICE_NAME"
}

prompt_trusttunnel_port() {
  local default_value="$1"
  local value
  while true; do
    ask_text value tt_port "TrustTunnel 监听端口 [${default_value}]: "
    value="${value:-$default_value}"
    if validate_trusttunnel_port "$value"; then
      printf "%s" "$value"
      return 0
    fi
    warn "端口必须是 1-65535 的数字。"
  done
}

prompt_trusttunnel_hostname() {
  local default_value="$1"
  local value
  while true; do
    ask_text value tt_hostname "TrustTunnel TLS 主机名/SNI [${default_value}]: "
    value="${value:-$default_value}"
    if validate_trusttunnel_hostname "$value"; then
      printf "%s" "$value"
      return 0
    fi
    warn "主机名格式不合法，请输入域名或 IP 地址。"
  done
}

prompt_trusttunnel_server() {
  local default_value="$1"
  local value
  while true; do
    ask_text value tt_server "客户端连接地址/IP [${default_value}]: "
    value="${value:-$default_value}"
    if validate_client_server "$value"; then
      printf "%s" "$value"
      return 0
    fi
    warn "地址格式不合法，请输入域名或 IP，不要带协议头或端口。"
  done
}

prompt_trusttunnel_username() {
  local default_value="$1"
  local value
  while true; do
    ask_text value tt_username "TrustTunnel 用户名 [${default_value}]: "
    value="${value:-$default_value}"
    if validate_trusttunnel_username "$value"; then
      printf "%s" "$value"
      return 0
    fi
    warn "用户名只允许字母、数字、下划线、点、@ 和短横线。"
  done
}

prompt_trusttunnel_password() {
  local default_value="$1"
  local value
  ask_text value tt_password "TrustTunnel 密码（留空沿用或自动生成）: " secret
  value="${value:-$default_value}"
  if ! validate_trusttunnel_password "$value"; then
    die "TrustTunnel 密码不能为空且不能包含换行。"
  fi
  printf "%s" "$value"
}

prompt_trusttunnel_cert_mode() {
  local default_value="$1"
  local value
  ask_text value tt_cert_mode "证书方式 [1=自签证书, 2=使用已有证书] [${default_value}]: "
  value="${value:-$default_value}"
  case "$value" in
    1) printf "self-signed" ;;
    2) printf "existing" ;;
    *) warn "证书方式无效，使用自签证书。" >&2; printf "self-signed" ;;
  esac
}

prompt_trusttunnel_existing_path() {
  local label="$1"
  local default_value="$2"
  local key="${3:-tt_cert_path}"
  local value
  while true; do
    ask_text value "$key" "${label} [${default_value}]: "
    value="${value:-$default_value}"
    if validate_trusttunnel_path "$value" && [[ -f "$value" ]]; then
      printf "%s" "$value"
      return 0
    fi
    warn "文件不存在或路径不是绝对路径。"
  done
}

trusttunnel_generate_password() {
  if declare -F generate_password >/dev/null 2>&1; then
    generate_password
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr -d '=+/$\n' | cut -c1-32
    return
  fi
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

trusttunnel_wizard_flow() {
  if [[ ! -x "$TRUSTTUNNEL_ENDPOINT_BINARY" ]]; then
    if ! prompt_yes_no "未找到 TrustTunnel endpoint，现在安装官方版本？" "y" install_endpoint; then
      return 0
    fi
    install_trusttunnel_endpoint
  fi

  local service_name config_parsed existing_found existing_listen_addr existing_listen_port
  local existing_hostname existing_username existing_password existing_ipv6 existing_cert_path existing_key_path
  local existing_client_server existing_display_name existing_cert_mode metadata_loaded
  service_name="$(normalize_service_name "$TRUSTTUNNEL_SERVICE_NAME")"
  config_parsed=""
  existing_found="false"
  existing_listen_addr="$TRUSTTUNNEL_STANDARD_LISTEN_ADDR"
  existing_listen_port=""
  existing_hostname=""
  existing_username="$TRUSTTUNNEL_DEFAULT_USERNAME"
  existing_password=""
  existing_ipv6="$TRUSTTUNNEL_DEFAULT_IPV6_AVAILABLE"
  existing_cert_path="$TRUSTTUNNEL_CERT_PATH"
  existing_key_path="$TRUSTTUNNEL_KEY_PATH"
  existing_client_server="$(default_server_identity)"
  existing_display_name="$TRUSTTUNNEL_DEFAULT_DISPLAY_NAME"
  existing_cert_mode="self-signed"

  if [[ -f "$TRUSTTUNNEL_VPN_CONFIG_PATH" && -f "$TRUSTTUNNEL_HOSTS_CONFIG_PATH" ]]; then
    config_parsed="$(extract_trusttunnel_config_details "$TRUSTTUNNEL_VPN_CONFIG_PATH" "$TRUSTTUNNEL_HOSTS_CONFIG_PATH")"
    while IFS=$'$\t' read -r key value; do
      case "$key" in
        found) existing_found="$value" ;;
        listen_address) existing_listen_addr="${value:-$existing_listen_addr}" ;;
        listen_port) existing_listen_port="$value" ;;
        hostname) existing_hostname="$value" ;;
        username) existing_username="${value:-$existing_username}" ;;
        password) existing_password="$value" ;;
        ipv6_available) existing_ipv6="${value:-$existing_ipv6}" ;;
        cert_chain_path) existing_cert_path="${value:-$existing_cert_path}" ;;
        private_key_path) existing_key_path="${value:-$existing_key_path}" ;;
      esac
    done <<< "$config_parsed"
  fi

  metadata_loaded="$(load_trusttunnel_metadata "$service_name")"
  if [[ -n "$metadata_loaded" ]]; then
    while IFS=$'$\t' read -r key value; do
      case "$key" in
        client_server) [[ -n "$value" ]] && existing_client_server="$value" ;;
        hostname) [[ -n "$value" ]] && existing_hostname="$value" ;;
        username) [[ -n "$value" ]] && existing_username="$value" ;;
        display_name) [[ -n "$value" ]] && existing_display_name="$value" ;;
        cert_mode) [[ -n "$value" ]] && existing_cert_mode="$value" ;;
        ipv6_available) [[ -n "$value" ]] && existing_ipv6="$value" ;;
      esac
    done <<< "$metadata_loaded"
  fi

  if [[ "$existing_found" == "true" ]]; then
    info "检测到现有 TrustTunnel 配置: ${TRUSTTUNNEL_VPN_CONFIG_PATH}"
    if ! prompt_yes_no "重新配置 TrustTunnel？" "n" reconfigure; then
      show_trusttunnel_parameters_for_service "$service_name" || true
      return 0
    fi
  fi

  local listen_port
  if validate_trusttunnel_port "$existing_listen_port"; then
    if declare -F pick_existing_listen_port >/dev/null 2>&1 && trusttunnel_service_exists "$service_name"; then
      listen_port="$(pick_existing_listen_port "$service_name" "$existing_listen_port" "$TRUSTTUNNEL_FALLBACK_LISTEN_PORT" "$existing_listen_addr")"
    else
      listen_port="$existing_listen_port"
    fi
  elif ! listen_port="$(pick_available_listen_port "$TRUSTTUNNEL_STANDARD_LISTEN_PORT" "$TRUSTTUNNEL_FALLBACK_LISTEN_PORT" "$TRUSTTUNNEL_STANDARD_LISTEN_ADDR" 2>/dev/null)"; then
    warn "${TRUSTTUNNEL_STANDARD_LISTEN_PORT} 和 ${TRUSTTUNNEL_FALLBACK_LISTEN_PORT} 都已被占用，请指定其他监听端口。"
    listen_port=""
  fi
  listen_port="$(prompt_trusttunnel_port "$listen_port")"

  local client_server hostname username password display_name ipv6_available cert_mode cert_path key_path
  client_server="$(prompt_trusttunnel_server "$existing_client_server")"
  hostname="$(prompt_trusttunnel_hostname "${existing_hostname:-$client_server}")"
  username="$(prompt_trusttunnel_username "$existing_username")"
  password="$(prompt_trusttunnel_password "${existing_password:-$(trusttunnel_generate_password)}")"
  display_name="$existing_display_name"
  local display_name_input
  ask_text display_name_input tt_display_name "客户端显示名称 [${display_name}]: "
  display_name="${display_name_input:-$display_name}"

  if ! validate_trusttunnel_bool "$existing_ipv6"; then
    existing_ipv6="$TRUSTTUNNEL_DEFAULT_IPV6_AVAILABLE"
  fi
  local ipv6_default
  ipv6_default="n"
  [[ "$existing_ipv6" == "true" ]] && ipv6_default="y"
  ipv6_available="$existing_ipv6"
  if prompt_yes_no "客户端/服务端启用 IPv6 路由？" "$ipv6_default" tt_ipv6; then
    ipv6_available="true"
  else
    ipv6_available="false"
  fi

  local cert_default
  cert_default="1"
  if [[ "$existing_cert_mode" == "existing" && -f "$existing_cert_path" && -f "$existing_key_path" ]]; then
    cert_default="2"
  fi
  cert_mode="$(prompt_trusttunnel_cert_mode "$cert_default")"
  if [[ "$cert_mode" == "existing" ]]; then
    cert_path="$(prompt_trusttunnel_existing_path "证书链 PEM 路径" "$existing_cert_path" tt_cert_path)"
    key_path="$(prompt_trusttunnel_existing_path "私钥 PEM 路径" "$existing_key_path" tt_key_path)"
  else
    cert_path="$TRUSTTUNNEL_CERT_PATH"
    key_path="$TRUSTTUNNEL_KEY_PATH"
    if [[ ! -f "$cert_path" || ! -f "$key_path" ]] || ! prompt_yes_no "沿用现有 TrustTunnel 自签证书？" "y" reuse_cert; then
      generate_trusttunnel_self_signed_certificate "$hostname" "$cert_path" "$key_path"
    fi
  fi

  TRUSTTUNNEL_CREDENTIALS_PATH="${TRUSTTUNNEL_INSTALL_DIR}/credentials.toml"
  TRUSTTUNNEL_RULES_PATH="${TRUSTTUNNEL_INSTALL_DIR}/rules.toml"
  write_trusttunnel_credentials "$TRUSTTUNNEL_CREDENTIALS_PATH" "$username" "$password"
  write_trusttunnel_rules_file
  write_trusttunnel_vpn_config "$TRUSTTUNNEL_VPN_CONFIG_PATH" "$TRUSTTUNNEL_STANDARD_LISTEN_ADDR" "$listen_port" "$ipv6_available"
  write_trusttunnel_hosts_config "$TRUSTTUNNEL_HOSTS_CONFIG_PATH" "$hostname" "$cert_path" "$key_path"
  write_trusttunnel_service_file

  if ! apply_service_state_auto "$service_name"; then
    die "应用 TrustTunnel 服务状态失败，请检查: journalctl -u ${service_name} -e"
  fi

  save_trusttunnel_metadata "$service_name" "$client_server" "$hostname" "$username" "$display_name" "$cert_mode" "$ipv6_available"
  show_trusttunnel_parameters_for_service "$service_name" || true
}

update_trusttunnel_flow() {
  local was_active="false"
  if trusttunnel_service_exists "$TRUSTTUNNEL_SERVICE_NAME" && is_service_active "$TRUSTTUNNEL_SERVICE_NAME"; then
    was_active="true"
    systemctl stop "$TRUSTTUNNEL_SERVICE_NAME"
    ok "已停止 TrustTunnel 服务以更新 endpoint。"
  fi

  install_trusttunnel_endpoint

  if [[ "$was_active" == "true" ]]; then
    if ! systemctl start "$TRUSTTUNNEL_SERVICE_NAME"; then
      die "TrustTunnel endpoint 更新后启动失败，请检查服务日志。"
    fi
    ok "已重新启动 ${TRUSTTUNNEL_SERVICE_NAME}"
  fi
}

uninstall_trusttunnel_flow() {
  warn "将停止并卸载 TrustTunnel endpoint。"
  if ! prompt_yes_no "确认卸载 TrustTunnel？" "n" confirm; then
    return 0
  fi

  systemctl disable --now "$TRUSTTUNNEL_SERVICE_NAME" >/dev/null 2>&1 || true
  local service_file
  service_file="$(service_unit_file_path "$TRUSTTUNNEL_SERVICE_NAME")"
  if [[ -f "$service_file" ]]; then
    rm -f "$service_file"
    ok "已删除服务文件: ${service_file}"
  fi

  if prompt_yes_no "删除 TrustTunnel 二进制和安装目录中的配置？" "y" delete_files; then
    rm -f \
      "$TRUSTTUNNEL_ENDPOINT_BINARY" \
      "$TRUSTTUNNEL_SETUP_WIZARD" \
      "${TRUSTTUNNEL_INSTALL_DIR}/trusttunnel.service.template" \
      "${TRUSTTUNNEL_INSTALL_DIR}/LICENSE" \
      "$TRUSTTUNNEL_VPN_CONFIG_PATH" \
      "$TRUSTTUNNEL_HOSTS_CONFIG_PATH" \
      "$TRUSTTUNNEL_CREDENTIALS_PATH" \
      "$TRUSTTUNNEL_RULES_PATH" \
      "$TRUSTTUNNEL_CERT_PATH" \
      "$TRUSTTUNNEL_KEY_PATH" \
      "${TRUSTTUNNEL_INSTALL_DIR}/trusttunnel-client.toml"
    ok "已删除 TrustTunnel endpoint 文件和配置。"
  fi

  local metadata_path
  metadata_path="$(trusttunnel_metadata_path_for_service "$TRUSTTUNNEL_SERVICE_NAME")"
  if [[ -f "$metadata_path" ]] && prompt_yes_no "删除 TrustTunnel 参数元数据？" "y" delete_metadata; then
    rm -f "$metadata_path"
    ok "已删除元数据: ${metadata_path}"
  fi
  systemctl daemon-reload
  systemctl reset-failed >/dev/null 2>&1 || true
}
