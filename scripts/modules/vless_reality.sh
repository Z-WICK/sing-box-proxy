#!/usr/bin/env bash

: "${VLESS_REALITY_STANDARD_SERVICE_NAME:=sing-box-vless-reality.service}"
: "${VLESS_REALITY_STANDARD_CONFIG_PATH:=/etc/sing-box/vless-reality.json}"
: "${VLESS_REALITY_STANDARD_LISTEN_ADDR:=::}"
: "${VLESS_REALITY_STANDARD_LISTEN_PORT:=443}"
: "${VLESS_REALITY_FALLBACK_LISTEN_PORT:=8443}"
: "${VLESS_REALITY_DEFAULT_FLOW:=xtls-rprx-vision}"
: "${VLESS_REALITY_METADATA_DIR:=${DATA_DIR}/vless-reality-meta}"

register_vless_reality_menu_items() {
  register_protocol_menu_item "VLESS" "Reality 配置向导" "vless_reality_wizard_flow"
  register_protocol_menu_item "VLESS" "查看 Reality 参数" "show_vless_reality_parameters_flow"
}

generate_uuid_string() {
  local uuid_value
  uuid_value="$("$BINARY_PATH" generate uuid 2>/dev/null | head -n1 | tr -d '\r')"
  if [[ "$uuid_value" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    printf "%s" "${uuid_value,,}"
    return 0
  fi

  uuid_value="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  printf "%s" "${uuid_value,,}"
}

validate_uuid_value() {
  local uuid_value="$1"
  [[ "$uuid_value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

generate_reality_short_id() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 8
    return 0
  fi

  tr -dc 'a-f0-9' </dev/urandom | head -c 16
}

validate_reality_short_id() {
  local short_id="$1"
  [[ "$short_id" =~ ^[0-9a-fA-F]{1,16}$ ]]
}

generate_reality_keypair() {
  local keypair_output private_key public_key
  keypair_output="$("$BINARY_PATH" generate reality-keypair 2>/dev/null)" || die "生成 Reality 密钥失败。"
  private_key="$(printf "%s\n" "$keypair_output" | awk -F': ' '/^PrivateKey:/{print $2; exit}')"
  public_key="$(printf "%s\n" "$keypair_output" | awk -F': ' '/^PublicKey:/{print $2; exit}')"

  if [[ -z "$private_key" || -z "$public_key" ]]; then
    die "解析 Reality 密钥失败。"
  fi

  printf "private_key\t%s\n" "$private_key"
  printf "public_key\t%s\n" "$public_key"
}

validate_reality_server_name() {
  local server_name="$1"

  REALITY_SERVER_NAME="$server_name" python3 - <<'PY'
import ipaddress
import os
import re

name = os.environ.get('REALITY_SERVER_NAME', '').strip().lower()
if not name:
    raise SystemExit(1)

if any(ch in name for ch in (' ', '/', ':', '?', '#', '@')):
    raise SystemExit(1)

try:
    ipaddress.ip_address(name)
    raise SystemExit(1)
except ValueError:
    pass

pattern = re.compile(r'^(?=.{1,253}$)(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))+$')
if not pattern.fullmatch(name):
    raise SystemExit(1)
PY
}

is_disallowed_reality_server_name() {
  local server_name="$1"

  REALITY_SERVER_NAME="$server_name" python3 - <<'PY'
import os

name = os.environ.get('REALITY_SERVER_NAME', '').strip().lower().rstrip('.')
blocked = (
    'cloudflare.com',
    'cdn.cloudflare.net',
    'google.com',
    'googleapis.com',
    'gstatic.com',
    'youtube.com',
    'ytimg.com',
    'microsoft.com',
    'live.com',
    'office.com',
    'apple.com',
    'icloud.com',
    'amazon.com',
    'aws.amazon.com',
    'facebook.com',
    'fbcdn.net',
    'instagram.com',
    'x.com',
    'twitter.com',
    'tiktok.com',
    'bytecdn.com',
)

for suffix in blocked:
    if name == suffix or name.endswith('.' + suffix):
        raise SystemExit(0)

raise SystemExit(1)
PY
}

prompt_reality_server_name() {
  local default_value="$1"
  local user_input

  while true; do
    if [[ -n "$default_value" ]]; then
      read -r -p "伪装域名（REALITY server_name）[${default_value}]: " user_input
      user_input="${user_input:-$default_value}"
    else
      read -r -p "伪装域名（REALITY server_name）: " user_input
    fi

    user_input="${user_input,,}"
    user_input="${user_input%.}"

    if ! validate_reality_server_name "$user_input"; then
      warn "域名不合法，请输入真实可解析的域名。"
      continue
    fi

    if is_disallowed_reality_server_name "$user_input"; then
      warn "不建议使用大厂域名做 REALITY 伪装（容易触发 CDN 流量风险），请换域名。"
      continue
    fi

    printf "%s" "$user_input"
    return 0
  done
}

vless_reality_metadata_path_for_service() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  printf "%s/%s.json" "$VLESS_REALITY_METADATA_DIR" "${service_name%.service}"
}

save_vless_reality_metadata() {
  local service_name="$1"
  local client_server="$2"
  local public_key="$3"

  local metadata_path
  metadata_path="$(vless_reality_metadata_path_for_service "$service_name")"
  mkdir -p "$VLESS_REALITY_METADATA_DIR"

  VLESS_METADATA_PATH="$metadata_path" \
  VLESS_CLIENT_SERVER="$client_server" \
  VLESS_PUBLIC_KEY="$public_key" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ['VLESS_METADATA_PATH'])
payload = {
    'client_server': os.environ.get('VLESS_CLIENT_SERVER', ''),
    'public_key': os.environ.get('VLESS_PUBLIC_KEY', ''),
}
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
}

load_vless_reality_metadata() {
  local service_name="$1"
  local metadata_path
  metadata_path="$(vless_reality_metadata_path_for_service "$service_name")"

  if [[ ! -f "$metadata_path" ]]; then
    return 0
  fi

  VLESS_METADATA_PATH="$metadata_path" python3 - <<'PY'
import json
import os

path = os.environ['VLESS_METADATA_PATH']
with open(path, 'r', encoding='utf-8') as fp:
    data = json.load(fp)

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

emit('client_server', data.get('client_server'))
emit('public_key', data.get('public_key'))
PY
}

build_vless_reality_uri() {
  local server="$1"
  local port="$2"
  local uuid="$3"
  local server_name="$4"
  local public_key="$5"
  local short_id="$6"
  local flow="$7"
  local node_name="$8"

  VLESS_URI_SERVER="$server" \
  VLESS_URI_PORT="$port" \
  VLESS_URI_UUID="$uuid" \
  VLESS_URI_SERVER_NAME="$server_name" \
  VLESS_URI_PUBLIC_KEY="$public_key" \
  VLESS_URI_SHORT_ID="$short_id" \
  VLESS_URI_FLOW="$flow" \
  VLESS_URI_NAME="$node_name" \
  python3 - <<'PY'
import os
import urllib.parse

server = os.environ['VLESS_URI_SERVER']
port = os.environ['VLESS_URI_PORT']
uuid = os.environ['VLESS_URI_UUID']
server_name = os.environ['VLESS_URI_SERVER_NAME']
public_key = os.environ['VLESS_URI_PUBLIC_KEY']
short_id = os.environ['VLESS_URI_SHORT_ID']
flow = os.environ['VLESS_URI_FLOW']
name = os.environ['VLESS_URI_NAME']

server_for_uri = server
if ':' in server and not server.startswith('['):
    server_for_uri = f'[{server}]'

params = {
    'encryption': 'none',
    'flow': flow,
    'security': 'reality',
    'sni': server_name,
    'fp': 'chrome',
    'pbk': public_key,
    'sid': short_id,
    'type': 'tcp',
}

query = urllib.parse.urlencode(params)
uri = f"vless://{uuid}@{server_for_uri}:{port}?{query}#{urllib.parse.quote(name, safe='')}"
print(uri)
PY
}

extract_vless_reality_inbound_details() {
  local config_path="$1"
  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    return 0
  fi

  VLESS_CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os

path = os.environ['VLESS_CONFIG_PATH']
with open(path, 'r', encoding='utf-8') as fp:
    data = json.load(fp)

target = None
for inbound in data.get('inbounds') or []:
    if not isinstance(inbound, dict) or inbound.get('type') != 'vless':
        continue
    tls = inbound.get('tls') if isinstance(inbound.get('tls'), dict) else {}
    reality = tls.get('reality') if isinstance(tls.get('reality'), dict) else {}
    if reality.get('enabled'):
        target = inbound
        break

if target is None:
    print('found\tfalse')
    raise SystemExit(0)

users = target.get('users') or []
user = users[0] if users and isinstance(users[0], dict) else {}
tls = target.get('tls') if isinstance(target.get('tls'), dict) else {}
reality = tls.get('reality') if isinstance(tls.get('reality'), dict) else {}
handshake = reality.get('handshake') if isinstance(reality.get('handshake'), dict) else {}
short_ids = reality.get('short_id') if isinstance(reality.get('short_id'), list) else []
short_id = short_ids[0] if short_ids else ''

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

emit('found', 'true')
emit('listen', target.get('listen'))
emit('listen_port', target.get('listen_port'))
emit('uuid', user.get('uuid'))
emit('flow', user.get('flow'))
emit('server_name', tls.get('server_name'))
emit('private_key', reality.get('private_key'))
emit('short_id', short_id)
emit('handshake_server', handshake.get('server'))
emit('handshake_server_port', handshake.get('server_port'))
PY
}

config_has_vless_reality_inbound() {
  local config_path="$1"
  local parsed found
  found="false"

  parsed="$(extract_vless_reality_inbound_details "$config_path")"
  if [[ -z "$parsed" ]]; then
    return 1
  fi

  while IFS=$'\t' read -r key value; do
    case "$key" in
      found)
        found="$value"
        ;;
    esac
  done <<< "$parsed"

  [[ "$found" == "true" ]]
}

write_vless_reality_config() {
  local config_path="$1"
  local listen_addr="$2"
  local listen_port="$3"
  local uuid_value="$4"
  local flow_value="$5"
  local server_name="$6"
  local private_key="$7"
  local short_id="$8"

  mkdir -p "$(dirname "$config_path")"

  VLESS_CONFIG_PATH="$config_path" \
  VLESS_LISTEN_ADDR="$listen_addr" \
  VLESS_LISTEN_PORT="$listen_port" \
  VLESS_UUID="$uuid_value" \
  VLESS_FLOW="$flow_value" \
  VLESS_SERVER_NAME="$server_name" \
  VLESS_PRIVATE_KEY="$private_key" \
  VLESS_SHORT_ID="$short_id" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

config_path = Path(os.environ['VLESS_CONFIG_PATH'])
listen_addr = os.environ['VLESS_LISTEN_ADDR']
listen_port = int(os.environ['VLESS_LISTEN_PORT'])
uuid = os.environ['VLESS_UUID']
flow = os.environ['VLESS_FLOW']
server_name = os.environ['VLESS_SERVER_NAME']
private_key = os.environ['VLESS_PRIVATE_KEY']
short_id = os.environ['VLESS_SHORT_ID']

config = {
    'log': {
        'level': 'info',
        'timestamp': True,
    },
    'inbounds': [
        {
            'type': 'vless',
            'tag': 'vless-reality-in',
            'listen': listen_addr,
            'listen_port': listen_port,
            'users': [
                {
                    'uuid': uuid,
                    'flow': flow,
                }
            ],
            'tls': {
                'enabled': True,
                'server_name': server_name,
                'reality': {
                    'enabled': True,
                    'handshake': {
                        'server': server_name,
                        'server_port': 443,
                    },
                    'private_key': private_key,
                    'short_id': [short_id],
                },
            },
        }
    ],
    'outbounds': [
        {
            'type': 'direct',
            'tag': 'direct',
        }
    ],
    'route': {
        'final': 'direct',
    },
}

config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY

  chmod 600 "$config_path"
}

show_vless_reality_parameters_for_service() {
  local service_name="$1"
  local config_path parsed

  service_name="$(normalize_service_name "$service_name")"
  if ! service_exists "$service_name"; then
    warn "未找到服务: ${service_name}"
    return 1
  fi

  config_path="$(extract_config_path_from_service "$service_name")"
  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    warn "未找到配置文件: ${config_path}"
    return 1
  fi

  parsed="$(extract_vless_reality_inbound_details "$config_path")"

  local found listen_addr listen_port uuid_value flow_value server_name private_key short_id handshake_server handshake_server_port
  found="false"
  listen_addr=""
  listen_port=""
  uuid_value=""
  flow_value=""
  server_name=""
  private_key=""
  short_id=""
  handshake_server=""
  handshake_server_port=""

  while IFS=$'\t' read -r key value; do
    case "$key" in
      found) found="$value" ;;
      listen) listen_addr="$value" ;;
      listen_port) listen_port="$value" ;;
      uuid) uuid_value="$value" ;;
      flow) flow_value="$value" ;;
      server_name) server_name="$value" ;;
      private_key) private_key="$value" ;;
      short_id) short_id="$value" ;;
      handshake_server) handshake_server="$value" ;;
      handshake_server_port) handshake_server_port="$value" ;;
    esac
  done <<< "$parsed"

  if [[ "$found" != "true" ]]; then
    warn "配置中未找到 VLESS Reality inbound: ${config_path}"
    return 1
  fi

  local client_server public_key metadata_loaded
  client_server="$(default_server_identity)"
  public_key=""

  metadata_loaded="$(load_vless_reality_metadata "$service_name")"
  if [[ -n "$metadata_loaded" ]]; then
    while IFS=$'\t' read -r key value; do
      case "$key" in
        client_server)
          if [[ -n "$value" ]]; then
            client_server="$value"
          fi
          ;;
        public_key)
          if [[ -n "$value" ]]; then
            public_key="$value"
          fi
          ;;
      esac
    done <<< "$metadata_loaded"
  fi

  if ! validate_client_server "$client_server"; then
    client_server="$(default_server_identity)"
  fi

  local service_base node_name vless_uri
  service_base="${service_name%.service}"
  node_name="VLESS-Reality-${service_base}"
  vless_uri=""
  if [[ -n "$public_key" && -n "$short_id" ]]; then
    vless_uri="$(build_vless_reality_uri "$client_server" "$listen_port" "$uuid_value" "$server_name" "$public_key" "$short_id" "$flow_value" "$node_name")"
  fi

  printf "\nVLESS Reality 参数：\n"
  printf "  服务名      : %s\n" "$service_name"
  printf "  服务器      : %s\n" "$client_server"
  printf "  监听地址    : %s\n" "$listen_addr"
  printf "  端口        : %s\n" "$listen_port"
  printf "  UUID        : %s\n" "$uuid_value"
  printf "  Flow        : %s\n" "$flow_value"
  printf "  SNI         : %s\n" "$server_name"
  printf "  Short ID    : %s\n" "$short_id"
  printf "  Handshake   : %s:%s\n" "$handshake_server" "$handshake_server_port"
  printf "  配置文件    : %s\n" "$config_path"

  if [[ -n "$public_key" ]]; then
    printf "  Public Key  : %s\n" "$public_key"
  else
    printf "  Public Key  : （未记录，无法直接生成 URI）\n"
  fi

  if [[ -n "$vless_uri" ]]; then
    printf "\nVLESS URI:\n"
    printf "  %s\n" "$vless_uri"
  fi
}

show_vless_reality_parameters_flow() {
  CURRENT_SERVICE_NAME="$VLESS_REALITY_STANDARD_SERVICE_NAME"
  if ! service_exists "$CURRENT_SERVICE_NAME"; then
    warn "未找到服务: ${CURRENT_SERVICE_NAME}"
    return 1
  fi
  show_vless_reality_parameters_for_service "$CURRENT_SERVICE_NAME"
}

vless_reality_wizard_flow() {
  if [[ ! -x "$BINARY_PATH" ]]; then
    die "未找到 sing-box 二进制，请先执行安装。"
  fi

  CURRENT_SERVICE_NAME="$VLESS_REALITY_STANDARD_SERVICE_NAME"

  local existing_config_path config_path
  existing_config_path=""
  if service_exists "$CURRENT_SERVICE_NAME"; then
    existing_config_path="$(extract_config_path_from_service "$CURRENT_SERVICE_NAME")"
  fi
  config_path="${existing_config_path:-$VLESS_REALITY_STANDARD_CONFIG_PATH}"

  local existing_found existing_listen_addr existing_listen_port existing_uuid existing_flow existing_server_name existing_private_key existing_short_id
  existing_found="false"
  existing_listen_addr=""
  existing_listen_port=""
  existing_uuid=""
  existing_flow=""
  existing_server_name=""
  existing_private_key=""
  existing_short_id=""

  if [[ -f "$config_path" ]]; then
    local existing_parsed
    existing_parsed="$(extract_vless_reality_inbound_details "$config_path")"
    while IFS=$'\t' read -r key value; do
      case "$key" in
        found) existing_found="$value" ;;
        listen) existing_listen_addr="$value" ;;
        listen_port) existing_listen_port="$value" ;;
        uuid) existing_uuid="$value" ;;
        flow) existing_flow="$value" ;;
        server_name) existing_server_name="$value" ;;
        private_key) existing_private_key="$value" ;;
        short_id) existing_short_id="$value" ;;
      esac
    done <<< "$existing_parsed"
  fi

  if [[ "$existing_found" == "true" ]]; then
    info "检测到现有 VLESS Reality 服务: ${CURRENT_SERVICE_NAME}"
    info "当前配置文件: ${config_path}"
    if prompt_yes_no "接管现有 VLESS Reality 配置并保持不变？" "y"; then
      show_vless_reality_parameters_for_service "$CURRENT_SERVICE_NAME" || true
      return 0
    fi
  fi

  local listen_addr listen_port
  listen_addr="${existing_listen_addr:-$VLESS_REALITY_STANDARD_LISTEN_ADDR}"
  if [[ "$existing_found" == "true" ]]; then
    listen_port="$(pick_existing_anytls_listen_port "$CURRENT_SERVICE_NAME" "${existing_listen_port:-$VLESS_REALITY_STANDARD_LISTEN_PORT}" "$VLESS_REALITY_FALLBACK_LISTEN_PORT" "$listen_addr")"
  else
    listen_port="$(pick_available_anytls_listen_port "$VLESS_REALITY_STANDARD_LISTEN_PORT" "$VLESS_REALITY_FALLBACK_LISTEN_PORT" "$listen_addr")"
  fi

  local reality_server_name
  reality_server_name="$(prompt_reality_server_name "$existing_server_name")"

  local uuid_value
  uuid_value="${existing_uuid,,}"
  if ! validate_uuid_value "$uuid_value"; then
    uuid_value="$(generate_uuid_string)"
  fi

  local flow_value
  flow_value="$VLESS_REALITY_DEFAULT_FLOW"
  if [[ -n "$existing_flow" && "$existing_flow" != "$VLESS_REALITY_DEFAULT_FLOW" ]]; then
    warn "检测到旧 flow=${existing_flow}，已统一使用 ${VLESS_REALITY_DEFAULT_FLOW}"
  fi

  local short_id
  short_id="${existing_short_id,,}"
  if ! validate_reality_short_id "$short_id"; then
    short_id="$(generate_reality_short_id)"
  fi

  local client_server public_key metadata_loaded
  client_server="$(default_server_identity)"
  public_key=""
  metadata_loaded="$(load_vless_reality_metadata "$CURRENT_SERVICE_NAME")"
  if [[ -n "$metadata_loaded" ]]; then
    while IFS=$'\t' read -r key value; do
      case "$key" in
        client_server)
          if [[ -n "$value" ]]; then
            client_server="$value"
          fi
          ;;
        public_key)
          if [[ -n "$value" ]]; then
            public_key="$value"
          fi
          ;;
      esac
    done <<< "$metadata_loaded"
  fi
  if ! validate_client_server "$client_server"; then
    client_server="$(default_server_identity)"
  fi

  local private_key
  private_key="$existing_private_key"
  if [[ -n "$private_key" ]]; then
    if ! prompt_yes_no "沿用现有 Reality 私钥？" "y"; then
      private_key=""
    fi
  fi

  if [[ -z "$private_key" ]]; then
    local keypair
    keypair="$(generate_reality_keypair)"
    while IFS=$'\t' read -r key value; do
      case "$key" in
        private_key) private_key="$value" ;;
        public_key) public_key="$value" ;;
      esac
    done <<< "$keypair"
  else
    if [[ -z "$public_key" ]]; then
      warn "当前未记录对应的 Reality 公钥，参数输出里将不显示完整 URI。"
    fi
  fi

  local backup_path service_file service_backup_path
  backup_path="$(backup_file_if_exists "$config_path")"
  service_file="$(service_unit_file_path "$CURRENT_SERVICE_NAME")"
  service_backup_path="$(backup_file_if_exists "$service_file")"

  if [[ -n "$backup_path" ]]; then
    ok "已创建配置备份: ${backup_path}"
  fi
  if [[ -n "$service_backup_path" ]]; then
    ok "已创建服务备份: ${service_backup_path}"
  fi

  write_vless_reality_config "$config_path" "$listen_addr" "$listen_port" "$uuid_value" "$flow_value" "$reality_server_name" "$private_key" "$short_id"
  validate_config_file "$config_path" || die "生成的配置无效: ${config_path}"
  ok "已写入 VLESS Reality 配置: ${config_path}"

  write_service_file "$CURRENT_SERVICE_NAME" "$config_path"

  if ! apply_service_state_auto "$CURRENT_SERVICE_NAME"; then
    if [[ -n "$backup_path" && -f "$backup_path" ]]; then
      cp "$backup_path" "$config_path"
      warn "服务应用失败，已回滚配置文件: ${config_path}"
    fi
    if [[ -n "$service_backup_path" && -f "$service_backup_path" ]]; then
      cp "$service_backup_path" "$service_file"
      systemctl daemon-reload
      warn "服务应用失败，已回滚服务文件: ${service_file}"
    fi
    systemctl restart "$CURRENT_SERVICE_NAME" >/dev/null 2>&1 || true
    die "应用 VLESS Reality 服务状态失败，请检查日志。"
  fi

  save_vless_reality_metadata "$CURRENT_SERVICE_NAME" "$client_server" "$public_key"
  show_vless_reality_parameters_for_service "$CURRENT_SERVICE_NAME" || true
}
