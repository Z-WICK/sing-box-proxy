#!/usr/bin/env bash

: "${SOCKS5_STANDARD_SERVICE_NAME:=sing-box-socks5.service}"
: "${SOCKS5_STANDARD_CONFIG_PATH:=/etc/sing-box/socks5.json}"
: "${SOCKS5_STANDARD_LISTEN_ADDR:=0.0.0.0}"
: "${SOCKS5_STANDARD_LISTEN_PORT:=1080}"
: "${SOCKS5_FALLBACK_LISTEN_PORT:=1081}"
: "${SOCKS5_DEFAULT_USERNAME:=proxy}"
: "${SOCKS5_METADATA_DIR:=${DATA_DIR}/socks5-meta}"

register_socks5_menu_items() {
  register_protocol_menu_item "SOCKS5" "配置向导" "socks5_wizard_flow"
  register_protocol_menu_item "SOCKS5" "查看参数" "show_socks5_parameters_flow"
}

socks5_metadata_path_for_service() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  printf "%s/%s.json" "$SOCKS5_METADATA_DIR" "${service_name%.service}"
}

save_socks5_metadata() {
  local service_name="$1"
  local client_server="$2"

  local metadata_path
  metadata_path="$(socks5_metadata_path_for_service "$service_name")"
  mkdir -p "$SOCKS5_METADATA_DIR"

  SOCKS5_METADATA_PATH="$metadata_path" \
  SOCKS5_CLIENT_SERVER="$client_server" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ['SOCKS5_METADATA_PATH'])
payload = {
    'client_server': os.environ.get('SOCKS5_CLIENT_SERVER', ''),
}
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
}

load_socks5_metadata() {
  local service_name="$1"
  local metadata_path
  metadata_path="$(socks5_metadata_path_for_service "$service_name")"

  if [[ ! -f "$metadata_path" ]]; then
    return 0
  fi

  SOCKS5_METADATA_PATH="$metadata_path" python3 - <<'PY'
import json
import os

path = os.environ['SOCKS5_METADATA_PATH']
with open(path, 'r', encoding='utf-8') as fp:
    data = json.load(fp)

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

emit('client_server', data.get('client_server'))
PY
}

validate_socks5_username() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9_.@-]{1,64}$ ]]
}

build_socks5_uri() {
  local server="$1"
  local port="$2"
  local username="$3"
  local password="$4"
  local node_name="$5"

  SOCKS5_URI_SERVER="$server" \
  SOCKS5_URI_PORT="$port" \
  SOCKS5_URI_USERNAME="$username" \
  SOCKS5_URI_PASSWORD="$password" \
  SOCKS5_URI_NAME="$node_name" \
  python3 - <<'PY'
import os
import urllib.parse

server = os.environ['SOCKS5_URI_SERVER']
port = os.environ['SOCKS5_URI_PORT']
username = os.environ.get('SOCKS5_URI_USERNAME', '')
password = os.environ.get('SOCKS5_URI_PASSWORD', '')
name = os.environ.get('SOCKS5_URI_NAME', 'SOCKS5')

server_for_uri = server
if ':' in server and not server.startswith('['):
    server_for_uri = f'[{server}]'

auth = ''
if username or password:
    auth = f"{urllib.parse.quote(username, safe='')}:{urllib.parse.quote(password, safe='')}@"

print(f"socks5://{auth}{server_for_uri}:{port}#{urllib.parse.quote(name, safe='')}")
PY
}

build_socks5_curl_proxy() {
  local server="$1"
  local port="$2"
  local username="$3"
  local password="$4"

  SOCKS5_CURL_SERVER="$server" \
  SOCKS5_CURL_PORT="$port" \
  SOCKS5_CURL_USERNAME="$username" \
  SOCKS5_CURL_PASSWORD="$password" \
  python3 - <<'PY'
import os
import urllib.parse

server = os.environ['SOCKS5_CURL_SERVER']
port = os.environ['SOCKS5_CURL_PORT']
username = os.environ.get('SOCKS5_CURL_USERNAME', '')
password = os.environ.get('SOCKS5_CURL_PASSWORD', '')

server_for_uri = server
if ':' in server and not server.startswith('['):
    server_for_uri = f'[{server}]'

auth = ''
if username or password:
    auth = f"{urllib.parse.quote(username, safe='')}:{urllib.parse.quote(password, safe='')}@"

print(f"socks5h://{auth}{server_for_uri}:{port}")
PY
}

write_socks5_config() {
  local config_path="$1"
  local listen_addr="$2"
  local listen_port="$3"
  local username="$4"
  local password="$5"

  mkdir -p "$(dirname "$config_path")"

  SOCKS5_CONFIG_PATH="$config_path" \
  SOCKS5_LISTEN_ADDR="$listen_addr" \
  SOCKS5_LISTEN_PORT="$listen_port" \
  SOCKS5_USERNAME="$username" \
  SOCKS5_PASSWORD="$password" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

config_path = Path(os.environ['SOCKS5_CONFIG_PATH'])
listen_addr = os.environ['SOCKS5_LISTEN_ADDR']
listen_port = int(os.environ['SOCKS5_LISTEN_PORT'])
username = os.environ['SOCKS5_USERNAME']
password = os.environ['SOCKS5_PASSWORD']

inbound = {
    'type': 'socks',
    'tag': 'socks5-in',
    'listen': listen_addr,
    'listen_port': listen_port,
    'users': [
        {
            'username': username,
            'password': password,
        }
    ],
}

config = {
    'log': {
        'level': 'info',
        'timestamp': True,
    },
    'inbounds': [inbound],
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

extract_socks5_inbound_details() {
  local config_path="$1"

  SOCKS5_CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os

config_path = os.environ['SOCKS5_CONFIG_PATH']
with open(config_path, 'r', encoding='utf-8') as fp:
    data = json.load(fp)

target = None
for inbound in data.get('inbounds') or []:
    if isinstance(inbound, dict) and inbound.get('type') == 'socks':
        target = inbound
        break

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

if target is None:
    emit('found', 'false')
    raise SystemExit(0)

users = target.get('users') or []
username = ''
password = ''
if users and isinstance(users[0], dict):
    username = str(users[0].get('username') or '')
    password = str(users[0].get('password') or '')

emit('found', 'true')
emit('tag', target.get('tag'))
emit('listen', target.get('listen'))
emit('listen_port', target.get('listen_port'))
emit('username', username)
emit('password', password)
PY
}

config_has_socks5_inbound() {
  local config_path="$1"
  [[ -f "$config_path" ]] || return 1
  [[ "$(extract_socks5_inbound_details "$config_path" | awk -F '\t' '$1 == "found" {print $2; exit}')" == "true" ]]
}

show_socks5_parameters_for_service() {
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

  parsed="$(extract_socks5_inbound_details "$config_path")"

  local found listen_addr listen_port username password
  found="false"
  listen_addr=""
  listen_port=""
  username=""
  password=""

  while IFS=$'\t' read -r key value; do
    case "$key" in
      found) found="$value" ;;
      listen) listen_addr="$value" ;;
      listen_port) listen_port="$value" ;;
      username) username="$value" ;;
      password) password="$value" ;;
    esac
  done <<< "$parsed"

  if [[ "$found" != "true" ]]; then
    warn "配置中未找到 SOCKS5 inbound: ${config_path}"
    return 1
  fi

  local client_server metadata_loaded
  client_server="$(default_server_identity)"
  metadata_loaded="$(load_socks5_metadata "$service_name")"
  if [[ -n "$metadata_loaded" ]]; then
    while IFS=$'\t' read -r key value; do
      case "$key" in
        client_server)
          if [[ -n "$value" ]]; then
            client_server="$value"
          fi
          ;;
      esac
    done <<< "$metadata_loaded"
  fi

  if ! validate_client_server "$client_server"; then
    client_server="$(default_server_identity)"
  fi

  local service_base node_name socks_uri curl_proxy
  service_base="${service_name%.service}"
  node_name="SOCKS5-${service_base}"
  socks_uri="$(build_socks5_uri "$client_server" "$listen_port" "$username" "$password" "$node_name")"
  curl_proxy="$(build_socks5_curl_proxy "$client_server" "$listen_port" "$username" "$password")"

  printf "\nSOCKS5 参数：\n"
  printf "  服务名      : %s\n" "$service_name"
  printf "  服务器      : %s\n" "$client_server"
  printf "  监听地址    : %s\n" "$listen_addr"
  printf "  端口        : %s\n" "$listen_port"
  printf "  用户名      : %s\n" "$username"
  printf "  密码        : %s\n" "$password"
  printf "  配置文件    : %s\n" "$config_path"

  printf "\nSOCKS5 URI:\n"
  printf "  %s\n" "$socks_uri"

  printf "\n测试命令：\n"
  printf "  curl -x '%s' https://api.ipify.org\n" "$curl_proxy"
}

show_socks5_parameters_flow() {
  CURRENT_SERVICE_NAME="$SOCKS5_STANDARD_SERVICE_NAME"
  if ! service_exists "$CURRENT_SERVICE_NAME"; then
    warn "未找到服务: ${CURRENT_SERVICE_NAME}"
    return 1
  fi
  show_socks5_parameters_for_service "$CURRENT_SERVICE_NAME"
}

socks5_wizard_flow() {
  if [[ ! -x "$BINARY_PATH" ]]; then
    die "未找到 sing-box 二进制，请先执行安装。"
  fi

  CURRENT_SERVICE_NAME="$SOCKS5_STANDARD_SERVICE_NAME"

  local existing_config_path config_path
  existing_config_path=""
  if service_exists "$CURRENT_SERVICE_NAME"; then
    existing_config_path="$(extract_config_path_from_service "$CURRENT_SERVICE_NAME")"
  fi
  config_path="${existing_config_path:-$SOCKS5_STANDARD_CONFIG_PATH}"

  if [[ -n "$existing_config_path" && -f "$config_path" ]] && config_has_socks5_inbound "$config_path"; then
    info "检测到现有 SOCKS5 服务: ${CURRENT_SERVICE_NAME}"
    info "当前配置文件: ${config_path}"
    if prompt_yes_no "保持现有 SOCKS5 配置并查看参数？" "y"; then
      show_socks5_parameters_for_service "$CURRENT_SERVICE_NAME" || true
      return 0
    fi
  fi

  local listen_addr listen_port username password
  listen_addr="$SOCKS5_STANDARD_LISTEN_ADDR"
  listen_port="$(pick_available_listen_port "$SOCKS5_STANDARD_LISTEN_PORT" "$SOCKS5_FALLBACK_LISTEN_PORT" "$listen_addr")"
  username="$SOCKS5_DEFAULT_USERNAME"
  password="$(generate_password)"

  if ! validate_socks5_username "$username"; then
    die "SOCKS5 用户名不合法: ${username}"
  fi

  local backup_path
  backup_path="$(backup_file_if_exists "$config_path")"
  if [[ -n "$backup_path" ]]; then
    ok "已创建配置备份: ${backup_path}"
  fi

  write_socks5_config "$config_path" "$listen_addr" "$listen_port" "$username" "$password"
  validate_config_file "$config_path" || die "生成的配置无效: ${config_path}"
  ok "已写入 SOCKS5 配置: ${config_path}"

  save_socks5_metadata "$CURRENT_SERVICE_NAME" "$(default_server_identity)"
  write_service_file "$CURRENT_SERVICE_NAME" "$config_path"

  info "已应用 SOCKS5 参数：监听 ${listen_addr}:${listen_port}、启用用户名密码认证。"

  if ! apply_service_state_auto "$CURRENT_SERVICE_NAME"; then
    if [[ -n "$backup_path" && -f "$backup_path" ]]; then
      cp "$backup_path" "$config_path"
      warn "服务应用失败，已恢复配置文件: ${config_path}"
      systemctl restart "$CURRENT_SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    die "应用 SOCKS5 服务状态失败，请检查日志。"
  fi

  show_socks5_parameters_for_service "$CURRENT_SERVICE_NAME" || true
}
