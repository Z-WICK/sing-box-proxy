#!/usr/bin/env bash

: "${DEFAULT_ANYTLS_PASSWORD_FILE:=/etc/sing-box/anytls_password.txt}"
: "${ANYTLS_STANDARD_SERVICE_NAME:=sing-box-anytls.service}"
: "${ANYTLS_STANDARD_CONFIG_PATH:=/etc/sing-box/anytls.json}"
: "${ANYTLS_STANDARD_LISTEN_ADDR:=::}"
: "${ANYTLS_STANDARD_LISTEN_PORT:=443}"
: "${ANYTLS_FALLBACK_LISTEN_PORT:=8443}"
: "${ANYTLS_STANDARD_CERT_PATH:=/etc/sing-box/cert.pem}"
: "${ANYTLS_STANDARD_KEY_PATH:=/etc/sing-box/key.pem}"
: "${ANYTLS_METADATA_DIR:=${DATA_DIR}/metadata}"
: "${CLIENT_IMPORT_DIR:=${DATA_DIR}/client-import}"
: "${CLIENT_IMPORT_PUBLISH_DIR:=${DATA_DIR}/client-import-publish}"
: "${CLIENT_IMPORT_HTTP_SERVICE:=sing-box-import-http.service}"
: "${CLIENT_IMPORT_HTTP_SCRIPT:=${TOOLS_DIR}/import-http-server.py}"
: "${CLIENT_IMPORT_HTTP_PORT:=18080}"

register_anytls_menu_items() {
  register_protocol_menu_item "AnyTLS" "配置向导" "anytls_wizard_flow"
  register_protocol_menu_item "AnyTLS" "查看参数" "show_anytls_parameters_flow"
}

metadata_path_for_service() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  printf "%s/%s.json" "$ANYTLS_METADATA_DIR" "${service_name%.service}"
}

save_anytls_client_metadata() {
  local service_name="$1"
  local client_server="$2"
  local client_sni="$3"
  local skip_cert_verify="$4"
  local publish_http_links="$5"
  local import_token="$6"

  local metadata_path
  metadata_path="$(metadata_path_for_service "$service_name")"

  mkdir -p "$ANYTLS_METADATA_DIR"

  METADATA_PATH="$metadata_path" \
  CLIENT_SERVER="$client_server" \
  CLIENT_SNI="$client_sni" \
  SKIP_CERT_VERIFY="$skip_cert_verify" \
  PUBLISH_HTTP_LINKS="$publish_http_links" \
  IMPORT_TOKEN="$import_token" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ['METADATA_PATH'])
payload = {
    'client_server': os.environ.get('CLIENT_SERVER', ''),
    'client_sni': os.environ.get('CLIENT_SNI', ''),
    'skip_cert_verify': os.environ.get('SKIP_CERT_VERIFY', 'false').lower() == 'true',
    'publish_http_links': os.environ.get('PUBLISH_HTTP_LINKS', 'false').lower() == 'true',
    'import_token': os.environ.get('IMPORT_TOKEN', ''),
}
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
}

load_anytls_client_metadata() {
  local service_name="$1"
  local metadata_path
  metadata_path="$(metadata_path_for_service "$service_name")"

  if [[ ! -f "$metadata_path" ]]; then
    return 0
  fi

  METADATA_PATH="$metadata_path" python3 - <<'PY'
import json
import os

path = os.environ['METADATA_PATH']
with open(path, 'r', encoding='utf-8') as fp:
    data = json.load(fp)

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

emit('client_server', data.get('client_server'))
emit('client_sni', data.get('client_sni'))
emit('skip_cert_verify', 'true' if data.get('skip_cert_verify') else 'false')
emit('publish_http_links', 'true' if data.get('publish_http_links', False) else 'false')
emit('import_token', data.get('import_token'))
PY
}

yaml_quote() {
  local text="$1"
  text="${text//\\/\\\\}"
  text="${text//\"/\\\"}"
  printf '"%s"' "$text"
}

url_encode() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse

print(urllib.parse.quote(sys.argv[1], safe=''))
PY
}

build_anytls_uri() {
  local server="$1"
  local port="$2"
  local password="$3"
  local tls_enabled="$4"
  local sni="$5"
  local skip_cert_verify="$6"
  local node_name="$7"

  BUILD_URI_SERVER="$server" \
  BUILD_URI_PORT="$port" \
  BUILD_URI_PASSWORD="$password" \
  BUILD_URI_TLS_ENABLED="$tls_enabled" \
  BUILD_URI_SNI="$sni" \
  BUILD_URI_SKIP_CERT_VERIFY="$skip_cert_verify" \
  BUILD_URI_NAME="$node_name" \
  python3 - <<'PY'
import os
import urllib.parse

server = os.environ['BUILD_URI_SERVER']
port = os.environ['BUILD_URI_PORT']
password = os.environ['BUILD_URI_PASSWORD']
tls_enabled = os.environ['BUILD_URI_TLS_ENABLED'].lower() == 'true'
sni = os.environ.get('BUILD_URI_SNI', '')
skip_cert_verify = os.environ.get('BUILD_URI_SKIP_CERT_VERIFY', 'false').lower() == 'true'
name = os.environ.get('BUILD_URI_NAME', 'AnyTLS')

params = {
    'type': 'tcp',
    'udp': '1',
}

if tls_enabled:
    params['security'] = 'tls'
    if sni:
        params['sni'] = sni
    if skip_cert_verify:
        params['insecure'] = '1'

query = urllib.parse.urlencode(params)
server_for_uri = server
if ':' in server and not server.startswith('['):
    server_for_uri = f'[{server}]'

uri = f"anytls://{urllib.parse.quote(password, safe='')}@{server_for_uri}:{port}?{query}#{urllib.parse.quote(name, safe='')}"
print(uri)
PY
}

write_client_import_profiles() {
  local service_name="$1"
  local server="$2"
  local port="$3"
  local password="$4"
  local tls_enabled="$5"
  local sni="$6"
  local skip_cert_verify="$7"
  local import_token="$8"

  local service_base file_base proxy_name
  service_base="${service_name%.service}"
  file_base="$service_base"
  if [[ -n "$import_token" ]]; then
    file_base="${service_base}-${import_token}"
  fi
  proxy_name="AnyTLS-${service_base}"

  local output_dir
  output_dir="$CLIENT_IMPORT_DIR"
  if [[ -n "$import_token" ]]; then
    output_dir="$CLIENT_IMPORT_PUBLISH_DIR"
  fi

  local surge_file clash_file loon_file egern_file
  surge_file="${output_dir}/${file_base}.surge.conf"
  clash_file="${output_dir}/${file_base}.clash.yaml"
  loon_file="${output_dir}/${file_base}.loon.conf"
  egern_file="${output_dir}/${file_base}.egern.uri"

  mkdir -p "$output_dir"

  local surge_line
  surge_line="${proxy_name} = anytls, ${server}, ${port}, password=${password}"
  if [[ "$tls_enabled" == "true" ]]; then
    if [[ -n "$sni" ]]; then
      surge_line+=", sni=${sni}"
    fi
    surge_line+=", skip-cert-verify=${skip_cert_verify}"
  fi
  surge_line+=", reuse=true"

  cat > "$surge_file" <<EOF
[General]
skip-proxy = 127.0.0.1, localhost

[Proxy]
${surge_line}

[Proxy Group]
PROXY = select, ${proxy_name}, DIRECT

[Rule]
FINAL,PROXY
EOF

  local server_yaml password_yaml sni_yaml proxy_yaml
  server_yaml="$(yaml_quote "$server")"
  password_yaml="$(yaml_quote "$password")"
  sni_yaml="$(yaml_quote "$sni")"
  proxy_yaml="$(yaml_quote "$proxy_name")"

  {
    printf "proxies:\n"
    printf "  - name: %s\n" "$proxy_yaml"
    printf "    type: anytls\n"
    printf "    server: %s\n" "$server_yaml"
    printf "    port: %s\n" "$port"
    printf "    password: %s\n" "$password_yaml"
    printf "    udp: true\n"
    printf "    client-fingerprint: chrome\n"
    if [[ "$tls_enabled" == "true" ]]; then
      printf "    sni: %s\n" "$sni_yaml"
      printf "    skip-cert-verify: %s\n" "$skip_cert_verify"
    fi
    printf "\nproxy-groups:\n"
    printf "  - name: PROXY\n"
    printf "    type: select\n"
    printf "    proxies:\n"
    printf "      - %s\n" "$proxy_yaml"
    printf "      - DIRECT\n"
    printf "\nrules:\n"
    printf "  - MATCH,PROXY\n"
  } > "$clash_file"

  local loon_line
  loon_line="${proxy_name} = AnyTLS,${server},${port},\"${password}\",idle-session-check-interval=30,idle-session-timeout=30,min-idle-session=1,max-stream-count=1"
  if [[ "$tls_enabled" == "true" ]]; then
    if [[ -n "$sni" ]]; then
      loon_line+=",sni=${sni}"
    fi
    loon_line+=",skip-cert-verify=${skip_cert_verify}"
  fi
  printf "%s\n" "$loon_line" > "$loon_file"

  local anytls_uri
  anytls_uri="$(build_anytls_uri "$server" "$port" "$password" "$tls_enabled" "$sni" "$skip_cert_verify" "$proxy_name")"
  printf "%s\n" "$anytls_uri" > "$egern_file"

  printf "surge_file\t%s\n" "$surge_file"
  printf "clash_file\t%s\n" "$clash_file"
  printf "loon_file\t%s\n" "$loon_file"
  printf "egern_file\t%s\n" "$egern_file"
  printf "file_base\t%s\n" "$file_base"
  printf "surge_line\t%s\n" "$surge_line"
  printf "loon_line\t%s\n" "$loon_line"
  printf "egern_uri\t%s\n" "$anytls_uri"
}

ensure_client_import_http_service() {
  local service_file python_cmd
  service_file="/etc/systemd/system/${CLIENT_IMPORT_HTTP_SERVICE}"
  python_cmd="$(command -v python3 || true)"

  if [[ -z "$python_cmd" ]]; then
    die "导入 HTTP 服务需要 python3"
  fi

  mkdir -p "$(dirname "$CLIENT_IMPORT_HTTP_SCRIPT")"
  mkdir -p "$CLIENT_IMPORT_PUBLISH_DIR"

  cat > "$CLIENT_IMPORT_HTTP_SCRIPT" <<'PY'
#!/usr/bin/env python3
import argparse
import functools
import http.server
import pathlib
import re
import socketserver
import urllib.parse

ALLOWED_FILE_RE = re.compile(r'^(?P<prefix>[A-Za-z0-9_.@-]+)-(?P<token>[A-Za-z0-9]{6,64})\.(surge\.conf|clash\.yaml|loon\.conf|egern\.uri)$')


class ImportFileHandler(http.server.SimpleHTTPRequestHandler):
    def _validated_name(self):
        parsed = urllib.parse.urlparse(self.path)
        requested = parsed.path.lstrip('/')
        if '/' in requested or requested in ('', '.', '..'):
            return None
        match = ALLOWED_FILE_RE.fullmatch(requested)
        if match is None:
            return None

        token_in_query = urllib.parse.parse_qs(parsed.query).get('token', [''])[0]
        if token_in_query != match.group('token'):
            return None
        return requested

    def list_directory(self, path):
        self.send_error(403, 'Directory listing is disabled')
        return None

    def do_GET(self):
        if self._validated_name() is None:
            self.send_error(404)
            return
        super().do_GET()

    def do_HEAD(self):
        if self._validated_name() is None:
            self.send_error(404)
            return
        super().do_HEAD()

    def log_message(self, format, *args):
        return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bind', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=18080)
    parser.add_argument('--directory', required=True)
    args = parser.parse_args()

    directory = pathlib.Path(args.directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)

    handler = functools.partial(ImportFileHandler, directory=str(directory))
    with socketserver.TCPServer((args.bind, args.port), handler) as httpd:
        httpd.serve_forever()


if __name__ == '__main__':
    main()
PY
  chmod 700 "$CLIENT_IMPORT_HTTP_SCRIPT"

  cat > "$service_file" <<EOF
[Unit]
Description=Static server for proxy client import files
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${python_cmd} ${CLIENT_IMPORT_HTTP_SCRIPT} --bind 0.0.0.0 --port ${CLIENT_IMPORT_HTTP_PORT} --directory ${CLIENT_IMPORT_PUBLISH_DIR}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$CLIENT_IMPORT_HTTP_SERVICE" >/dev/null 2>&1 || true
  if ! systemctl is-active --quiet "$CLIENT_IMPORT_HTTP_SERVICE"; then
    systemctl start "$CLIENT_IMPORT_HTTP_SERVICE"
  fi
}

cleanup_published_import_files_for_service() {
  local service_name="$1"
  local service_base removed_file
  service_base="${service_name%.service}"

  [[ -d "$CLIENT_IMPORT_PUBLISH_DIR" ]] || return 0

  while IFS= read -r removed_file; do
    [[ -n "$removed_file" ]] || continue
    ok "已删除发布导入文件: ${removed_file}"
  done < <(CLEAN_DIR="$CLIENT_IMPORT_PUBLISH_DIR" SERVICE_BASE="$service_base" python3 - <<'PY'
import os
import pathlib
import re

clean_dir = pathlib.Path(os.environ['CLEAN_DIR'])
service_base = os.environ['SERVICE_BASE']

pattern = re.compile(
    rf'^{re.escape(service_base)}-[A-Za-z0-9]{{6,64}}\.(surge\.conf|clash\.yaml|loon\.conf|egern\.uri)$'
)

if clean_dir.is_dir():
    for entry in clean_dir.iterdir():
        if not entry.is_file():
            continue
        if pattern.fullmatch(entry.name):
            entry.unlink(missing_ok=True)
            print(str(entry))
PY
)
}

extract_anytls_tls_info() {
  local config_path="$1"
  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    return 0
  fi

  ANYTLS_CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os

path = os.environ['ANYTLS_CONFIG_PATH']
with open(path, 'r', encoding='utf-8') as fp:
    data = json.load(fp)

inbounds = data.get('inbounds') or []
target = None
for inbound in inbounds:
    if isinstance(inbound, dict) and inbound.get('type') == 'anytls':
        target = inbound
        break

if target is None:
    print('has_anytls\tfalse')
    raise SystemExit(0)

tls = target.get('tls') if isinstance(target.get('tls'), dict) else {}
tls_enabled = bool(tls.get('enabled'))

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

emit('has_anytls', 'true')
emit('tls_enabled', 'true' if tls_enabled else 'false')
emit('certificate_path', tls.get('certificate_path'))
emit('key_path', tls.get('key_path'))
PY
}

extract_anytls_password_from_config() {
  local config_path="$1"
  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    printf ""
    return 0
  fi

  ANYTLS_CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os

path = os.environ['ANYTLS_CONFIG_PATH']

try:
    with open(path, 'r', encoding='utf-8') as fp:
        data = json.load(fp)
except Exception:
    print('')
    raise SystemExit(0)

for inbound in data.get('inbounds') or []:
    if not isinstance(inbound, dict) or inbound.get('type') != 'anytls':
        continue
    users = inbound.get('users') or []
    if users and isinstance(users[0], dict):
        password = users[0].get('password')
        print('' if password is None else str(password))
        raise SystemExit(0)

print('')
PY
}

extract_anytls_inbound_details() {
  local config_path="$1"
  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    return 0
  fi

  ANYTLS_CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os

path = os.environ['ANYTLS_CONFIG_PATH']
with open(path, 'r', encoding='utf-8') as fp:
    data = json.load(fp)

inbounds = data.get('inbounds') or []
target = None
for inbound in inbounds:
    if isinstance(inbound, dict) and inbound.get('type') == 'anytls':
        target = inbound
        break

if target is None:
    print('found\tfalse')
    raise SystemExit(0)

users = target.get('users') or []
password = ''
if users and isinstance(users[0], dict):
    password = str(users[0].get('password') or '')

tls = target.get('tls') if isinstance(target.get('tls'), dict) else {}
tls_enabled = bool(tls.get('enabled'))
padding_scheme = target.get('padding_scheme')

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

emit('found', 'true')
emit('listen', target.get('listen'))
emit('listen_port', target.get('listen_port'))
emit('password', password)
emit('tls_enabled', 'true' if tls_enabled else 'false')
emit('certificate_path', tls.get('certificate_path'))
emit('key_path', tls.get('key_path'))
emit('tls_server_name', tls.get('server_name'))
emit('padding_scheme_json', '' if padding_scheme is None else json.dumps(padding_scheme, ensure_ascii=False))
PY
}

config_has_anytls_inbound() {
  local config_path="$1"
  local parsed has_anytls
  has_anytls="false"

  parsed="$(extract_anytls_tls_info "$config_path")"
  if [[ -z "$parsed" ]]; then
    return 1
  fi

  while IFS=$'\t' read -r key value; do
    case "$key" in
      has_anytls)
        has_anytls="$value"
        ;;
    esac
  done <<< "$parsed"

  [[ "$has_anytls" == "true" ]]
}

cleanup_client_import_files_for_service() {
  local service_name="$1"
  local service_base base_dir removed_file
  service_base="${service_name%.service}"

  for base_dir in "$CLIENT_IMPORT_DIR" "$CLIENT_IMPORT_PUBLISH_DIR"; do
    [[ -d "$base_dir" ]] || continue

    while IFS= read -r removed_file; do
      [[ -n "$removed_file" ]] || continue
      ok "已删除客户端导入文件: ${removed_file}"
    done < <(CLEAN_DIR="$base_dir" SERVICE_BASE="$service_base" python3 - <<'PY'
import os
import pathlib
import re

clean_dir = pathlib.Path(os.environ['CLEAN_DIR'])
service_base = os.environ['SERVICE_BASE']

plain_pattern = re.compile(
    rf'^{re.escape(service_base)}\.(surge\.conf|clash\.yaml|loon\.conf|egern\.uri)$'
)
token_pattern = re.compile(
    rf'^{re.escape(service_base)}-[A-Za-z0-9]{{6,64}}\.(surge\.conf|clash\.yaml|loon\.conf|egern\.uri)$'
)

if clean_dir.is_dir():
    for entry in clean_dir.iterdir():
        if not entry.is_file():
            continue
        if plain_pattern.fullmatch(entry.name) or token_pattern.fullmatch(entry.name):
            entry.unlink(missing_ok=True)
            print(str(entry))
PY
)
  done
}

metadata_has_published_http_links() {
  METADATA_DIR="$ANYTLS_METADATA_DIR" python3 - <<'PY'
import glob
import json
import os
import sys

root = os.environ.get('METADATA_DIR', '')
if not root or not os.path.isdir(root):
    raise SystemExit(1)

for path in glob.glob(os.path.join(root, '*.json')):
    try:
        with open(path, 'r', encoding='utf-8') as fp:
            data = json.load(fp)
    except Exception:
        continue

    if bool(data.get('publish_http_links')):
        raise SystemExit(0)

raise SystemExit(1)
PY
}

disable_client_import_http_service_if_unused() {
  if ! systemctl cat "$CLIENT_IMPORT_HTTP_SERVICE" >/dev/null 2>&1; then
    return 0
  fi

  if metadata_has_published_http_links; then
    return 0
  fi

  systemctl disable --now "$CLIENT_IMPORT_HTTP_SERVICE" >/dev/null 2>&1 || true
}

uninstall_anytls_service_flow() {
  local service_name="$1"
  service_name="$(normalize_service_name "$service_name")"

  if ! service_exists "$service_name"; then
    warn "未找到服务: ${service_name}"
    return 1
  fi

  local unit_file config_path metadata_path
  unit_file="$(service_unit_file_path "$service_name")"
  config_path="$(extract_config_path_from_service "$service_name")"
  metadata_path="$(metadata_path_for_service "$service_name")"

  warn "将卸载 AnyTLS 服务: ${service_name}"
  if ! prompt_yes_no "继续吗？" "n"; then
    return 0
  fi

  local has_anytls tls_enabled cert_path key_path
  has_anytls="false"
  tls_enabled="false"
  cert_path=""
  key_path=""

  if [[ -n "$config_path" && -f "$config_path" ]]; then
    local tls_info
    tls_info="$(extract_anytls_tls_info "$config_path")"
    if [[ -n "$tls_info" ]]; then
      while IFS=$'\t' read -r key value; do
        case "$key" in
          has_anytls) has_anytls="$value" ;;
          tls_enabled) tls_enabled="$value" ;;
          certificate_path) cert_path="$value" ;;
          key_path) key_path="$value" ;;
        esac
      done <<< "$tls_info"
    fi
  fi

  systemctl disable --now "$service_name" >/dev/null 2>&1 || true
  ok "已停止并禁用服务: ${service_name}"

  if [[ -f "$unit_file" ]]; then
    if prompt_yes_no "删除 unit 文件 ${unit_file}？" "y"; then
      rm -f "$unit_file"
      ok "已删除 unit 文件: ${unit_file}"
    fi
  fi

  if [[ -n "$config_path" && -f "$config_path" ]]; then
    local remove_config_default
    remove_config_default="n"
    if is_safe_removal_path "$config_path"; then
      remove_config_default="y"
    fi

    if prompt_yes_no "删除配置文件 ${config_path}？" "$remove_config_default"; then
      rm -f "$config_path"
      ok "已删除配置文件: ${config_path}"
    fi
  fi

  if [[ "$has_anytls" == "true" && "$tls_enabled" == "true" ]]; then
    if [[ -n "$cert_path" && -f "$cert_path" ]]; then
      local remove_cert_default
      remove_cert_default="n"
      if is_safe_removal_path "$cert_path"; then
        remove_cert_default="y"
      fi
      if prompt_yes_no "删除证书文件 ${cert_path}？" "$remove_cert_default"; then
        rm -f "$cert_path"
        ok "已删除证书文件: ${cert_path}"
      fi
    fi
    if [[ -n "$key_path" && -f "$key_path" ]]; then
      local remove_key_default
      remove_key_default="n"
      if is_safe_removal_path "$key_path"; then
        remove_key_default="y"
      fi
      if prompt_yes_no "删除私钥文件 ${key_path}？" "$remove_key_default"; then
        rm -f "$key_path"
        ok "已删除私钥文件: ${key_path}"
      fi
    fi
  fi

  if [[ -f "$metadata_path" ]]; then
    if prompt_yes_no "删除元数据文件 ${metadata_path}？" "y"; then
      rm -f "$metadata_path"
      ok "已删除元数据文件: ${metadata_path}"
    fi
  fi

  cleanup_client_import_files_for_service "$service_name"
  disable_client_import_http_service_if_unused

  systemctl daemon-reload
  ok "AnyTLS 服务卸载完成: ${service_name}"
}

write_anytls_config() {
  local config_path="$1"
  local listen_addr="$2"
  local listen_port="$3"
  local anytls_password="$4"
  local tls_enabled="$5"
  local cert_path="$6"
  local key_path="$7"
  local tls_server_name="${8:-}"
  local padding_scheme_json="${9:-}"

  mkdir -p "$(dirname "$config_path")"

  ANYTLS_CONFIG_PATH="$config_path" \
  ANYTLS_LISTEN="$listen_addr" \
  ANYTLS_PORT="$listen_port" \
  ANYTLS_PASSWORD="$anytls_password" \
  ANYTLS_TLS_ENABLED="$tls_enabled" \
  ANYTLS_CERT_PATH="$cert_path" \
  ANYTLS_KEY_PATH="$key_path" \
  ANYTLS_TLS_SERVER_NAME="$tls_server_name" \
  ANYTLS_PADDING_SCHEME_JSON="$padding_scheme_json" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

config_path = Path(os.environ['ANYTLS_CONFIG_PATH'])
listen_addr = os.environ['ANYTLS_LISTEN']
listen_port = int(os.environ['ANYTLS_PORT'])
password = os.environ['ANYTLS_PASSWORD']
tls_enabled = os.environ['ANYTLS_TLS_ENABLED'].lower() == 'true'
cert_path = os.environ.get('ANYTLS_CERT_PATH', '')
key_path = os.environ.get('ANYTLS_KEY_PATH', '')
tls_server_name = os.environ.get('ANYTLS_TLS_SERVER_NAME', '')
padding_scheme_json = os.environ.get('ANYTLS_PADDING_SCHEME_JSON', '')

inbound = {
    'type': 'anytls',
    'tag': 'anytls-in',
    'listen': listen_addr,
    'listen_port': listen_port,
    'users': [
        {
            'password': password,
        }
    ],
}

if padding_scheme_json:
    inbound['padding_scheme'] = json.loads(padding_scheme_json)

if tls_enabled:
    inbound['tls'] = {
        'enabled': True,
        'certificate_path': cert_path,
        'key_path': key_path,
    }
    if tls_server_name:
        inbound['tls']['server_name'] = tls_server_name

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

config_path.write_text(json.dumps(config, indent=2) + '\n', encoding='utf-8')
PY

  chmod 600 "$config_path"
}

write_password_file() {
  local password_file="$1"
  local anytls_password="$2"

  mkdir -p "$(dirname "$password_file")"
  printf "%s\n" "$anytls_password" > "$password_file"
  chmod 600 "$password_file"
  ok "已写入密码文件: ${password_file}"
}

show_anytls_parameters_for_service() {
  local service_name="$1"
  local config_path

  service_name="$(normalize_service_name "$service_name")"
  if ! service_exists "$service_name"; then
    warn "未找到服务: ${service_name}"
    return 1
  fi

  config_path="$(extract_config_path_from_service "$service_name")"
  if [[ -z "$config_path" ]]; then
    warn "无法从服务中识别配置路径: ${service_name}"
    return 1
  fi

  if [[ ! -f "$config_path" ]]; then
    warn "未找到配置文件: ${config_path}"
    return 1
  fi

  local parsed
  parsed="$(ANYTLS_CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os

config_path = os.environ['ANYTLS_CONFIG_PATH']
with open(config_path, 'r', encoding='utf-8') as fp:
    data = json.load(fp)

inbounds = data.get('inbounds') or []
target = None
for inbound in inbounds:
    if isinstance(inbound, dict) and inbound.get('type') == 'anytls':
        target = inbound
        break

if target is None:
    print('found\tfalse')
    raise SystemExit(0)

users = target.get('users') or []
password = ''
if users and isinstance(users[0], dict):
    password = str(users[0].get('password') or '')

tls = target.get('tls') if isinstance(target.get('tls'), dict) else {}
tls_enabled = bool(tls.get('enabled'))

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

emit('found', 'true')
emit('tag', target.get('tag'))
emit('listen', target.get('listen'))
emit('listen_port', target.get('listen_port'))
emit('password', password)
emit('tls_enabled', 'true' if tls_enabled else 'false')
emit('certificate_path', tls.get('certificate_path'))
emit('key_path', tls.get('key_path'))
emit('tls_server_name', tls.get('server_name'))
emit('padding_scheme', target.get('padding_scheme'))
PY
)"

  local found tag listen_addr listen_port anytls_password tls_enabled cert_path key_path tls_server_name padding_scheme
  found=""
  tag=""
  listen_addr=""
  listen_port=""
  anytls_password=""
  tls_enabled="false"
  cert_path=""
  key_path=""
  tls_server_name=""
  padding_scheme=""

  while IFS=$'\t' read -r key value; do
    case "$key" in
      found) found="$value" ;;
      tag) tag="$value" ;;
      listen) listen_addr="$value" ;;
      listen_port) listen_port="$value" ;;
      password) anytls_password="$value" ;;
      tls_enabled) tls_enabled="$value" ;;
      certificate_path) cert_path="$value" ;;
      key_path) key_path="$value" ;;
      tls_server_name) tls_server_name="$value" ;;
      padding_scheme) padding_scheme="$value" ;;
    esac
  done <<< "$parsed"

  if [[ "$found" != "true" ]]; then
    warn "配置中未找到 AnyTLS inbound: ${config_path}"
    return 1
  fi

  local client_server client_sni skip_cert_verify publish_http_links import_token
  client_server="$(default_server_identity)"
  client_sni=""
  skip_cert_verify="false"
  publish_http_links="false"
  import_token=""

  if [[ "$tls_enabled" == "true" ]]; then
    client_sni="${tls_server_name:-$client_server}"
    skip_cert_verify="false"
  fi

  local metadata_loaded
  metadata_loaded="$(load_anytls_client_metadata "$service_name")"
  if [[ -n "$metadata_loaded" ]]; then
    while IFS=$'\t' read -r key value; do
      case "$key" in
        client_server)
          if [[ -n "$value" ]]; then
            client_server="$value"
          fi
          ;;
        client_sni)
          if [[ -n "$value" ]]; then
            client_sni="$value"
          fi
          ;;
        skip_cert_verify)
          if [[ -n "$value" ]]; then
            skip_cert_verify="$value"
          fi
          ;;
        publish_http_links)
          if [[ -n "$value" ]]; then
            publish_http_links="$value"
          fi
          ;;
        import_token)
          if [[ -n "$value" ]]; then
            import_token="$value"
          fi
          ;;
      esac
    done <<< "$metadata_loaded"
  fi

  if ! validate_client_server "$client_server"; then
    warn "元数据中的 client_server 无效，已回退为自动识别的地址。"
    client_server="$(default_server_identity)"
  fi

  if [[ -n "$import_token" ]] && ! validate_import_token "$import_token"; then
    warn "元数据中的 import_token 无效，启用发布时会重新生成 token。"
    import_token=""
  fi

  if [[ "$tls_enabled" != "true" ]]; then
    client_sni=""
    skip_cert_verify="false"
  fi

  if [[ "$publish_http_links" == "true" ]]; then
    if [[ -z "$import_token" ]]; then
      import_token="$(generate_token)"
      save_anytls_client_metadata "$service_name" "$client_server" "$client_sni" "$skip_cert_verify" "$publish_http_links" "$import_token"
    fi
    cleanup_published_import_files_for_service "$service_name"
  else
    import_token=""
  fi

  local profile_data
  profile_data="$(write_client_import_profiles "$service_name" "$client_server" "$listen_port" "$anytls_password" "$tls_enabled" "$client_sni" "$skip_cert_verify" "$import_token")"

  local surge_file clash_file loon_file egern_file file_base surge_line loon_line egern_uri
  surge_file=""
  clash_file=""
  loon_file=""
  egern_file=""
  file_base=""
  surge_line=""
  loon_line=""
  egern_uri=""

  while IFS=$'\t' read -r key value; do
    case "$key" in
      surge_file) surge_file="$value" ;;
      clash_file) clash_file="$value" ;;
      loon_file) loon_file="$value" ;;
      egern_file) egern_file="$value" ;;
      file_base) file_base="$value" ;;
      surge_line) surge_line="$value" ;;
      loon_line) loon_line="$value" ;;
      egern_uri) egern_uri="$value" ;;
    esac
  done <<< "$profile_data"

  local import_service_ready
  import_service_ready="false"
  if [[ "$publish_http_links" == "true" ]]; then
    import_service_ready="true"
    if ! ensure_client_import_http_service; then
      import_service_ready="false"
      warn "启动导入 HTTP 服务失败，已跳过链接生成。"
    fi
  fi

  local host_for_url service_base surge_profile_url clash_profile_url loon_profile_url egern_uri_url surge_import_link clash_import_link
  local import_query_suffix
  host_for_url="$(format_host_for_url "$client_server")"
  service_base="${service_name%.service}"
  if [[ -z "$file_base" ]]; then
    file_base="$service_base"
  fi
  import_query_suffix=""
  if [[ -n "$import_token" ]]; then
    import_query_suffix="?token=${import_token}"
  fi

  surge_profile_url="http://${host_for_url}:${CLIENT_IMPORT_HTTP_PORT}/${file_base}.surge.conf${import_query_suffix}"
  clash_profile_url="http://${host_for_url}:${CLIENT_IMPORT_HTTP_PORT}/${file_base}.clash.yaml${import_query_suffix}"
  loon_profile_url="http://${host_for_url}:${CLIENT_IMPORT_HTTP_PORT}/${file_base}.loon.conf${import_query_suffix}"
  egern_uri_url="http://${host_for_url}:${CLIENT_IMPORT_HTTP_PORT}/${file_base}.egern.uri${import_query_suffix}"
  surge_import_link="surge:///install-config?url=$(url_encode "$surge_profile_url")"
  clash_import_link="clash://install-config?url=$(url_encode "$clash_profile_url")&name=$(url_encode "$service_base")"

  printf "\nAnyTLS 导入参数：\n"
  printf "  服务器      : %s\n" "$client_server"
  printf "  端口        : %s\n" "$listen_port"
  printf "  密码        : %s\n" "$anytls_password"
  printf "  TLS         : %s\n" "$tls_enabled"
  if [[ "$tls_enabled" == "true" ]]; then
    printf "  SNI         : %s\n" "$client_sni"
    printf "  跳过验证    : %s\n" "$skip_cert_verify"
  fi

  printf "\nSurge:\n"
  printf "  代理参数    : %s\n" "$surge_line"
  printf "  配置文件    : %s\n" "$surge_file"
  if [[ "$import_service_ready" == "true" ]]; then
    printf "  配置链接    : %s\n" "$surge_profile_url"
    printf "  导入链接    : %s\n" "$surge_import_link"
  fi

  printf "\nLoon:\n"
  printf "  代理参数    : %s\n" "$loon_line"
  printf "  配置文件    : %s\n" "$loon_file"
  if [[ "$import_service_ready" == "true" ]]; then
    printf "  配置链接    : %s\n" "$loon_profile_url"
  fi

  printf "\nEgern:\n"
  printf "  AnyTLS URI   : %s\n" "$egern_uri"
  printf "  URI 文件    : %s\n" "$egern_file"
  if [[ "$import_service_ready" == "true" ]]; then
    printf "  URI 链接    : %s\n" "$egern_uri_url"
  fi

  printf "\nClash (Mihomo):\n"
  printf "  配置文件    : %s\n" "$clash_file"
  if [[ "$import_service_ready" == "true" ]]; then
    printf "  配置链接    : %s\n" "$clash_profile_url"
    printf "  导入链接    : %s\n" "$clash_import_link"
  fi

  if [[ "$publish_http_links" != "true" ]]; then
    cleanup_published_import_files_for_service "$service_name"
    disable_client_import_http_service_if_unused

    printf "\n元数据中已关闭一键导入链接。\n"
    if systemctl cat "$CLIENT_IMPORT_HTTP_SERVICE" >/dev/null 2>&1; then
      if systemctl is-active --quiet "$CLIENT_IMPORT_HTTP_SERVICE" || systemctl is-enabled --quiet "$CLIENT_IMPORT_HTTP_SERVICE"; then
        printf "警告：%s 当前处于运行/启用状态，可能暴露 %s 下的文件。\n" "$CLIENT_IMPORT_HTTP_SERVICE" "$CLIENT_IMPORT_PUBLISH_DIR"
        printf "可执行以下命令关闭：systemctl disable --now %s\n" "$CLIENT_IMPORT_HTTP_SERVICE"
      fi
    fi
  fi

  if [[ "$import_service_ready" == "true" ]]; then
    printf "\n通用导入链接（HTTP）：\n"
    printf "  Surge 配置 : %s\n" "$surge_profile_url"
    printf "  Clash 配置 : %s\n" "$clash_profile_url"
    printf "  Loon 配置  : %s\n" "$loon_profile_url"
    printf "  Egern URI   : %s\n" "$egern_uri_url"

    printf "\n导入 HTTP 服务：\n"
    printf "  服务名      : %s\n" "$CLIENT_IMPORT_HTTP_SERVICE"
    printf "  端口        : %s\n" "$CLIENT_IMPORT_HTTP_PORT"
    printf "  token       : %s\n" "$import_token"
    printf "\n安全提示：导入链接包含凭据和 token 参数，请勿外传。\n"
  fi
}

show_anytls_parameters_flow() {
  CURRENT_SERVICE_NAME="$(pick_default_service)"
  show_anytls_parameters_for_service "$CURRENT_SERVICE_NAME"
}

adopt_existing_anytls_flow() {
  local service_name="$1"
  local config_path

  service_name="$(normalize_service_name "$service_name")"
  if ! service_exists "$service_name"; then
    die "未找到服务: ${service_name}"
  fi

  config_path="$(extract_config_path_from_service "$service_name")"
  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    die "未找到配置文件: ${config_path}"
  fi

  if ! config_has_anytls_inbound "$config_path"; then
    die "配置中未找到 AnyTLS inbound: ${config_path}"
  fi

  local client_server client_sni skip_cert_verify publish_http_links import_token
  local metadata_loaded
  client_server="$(default_server_identity)"
  client_sni="$client_server"
  skip_cert_verify="false"
  publish_http_links="false"
  import_token=""

  metadata_loaded="$(load_anytls_client_metadata "$service_name")"
  if [[ -n "$metadata_loaded" ]]; then
    while IFS=$'\t' read -r key value; do
      case "$key" in
        client_server)
          if [[ -n "$value" ]]; then
            client_server="$value"
          fi
          ;;
        client_sni)
          if [[ -n "$value" ]]; then
            client_sni="$value"
          fi
          ;;
        skip_cert_verify)
          if [[ -n "$value" ]]; then
            skip_cert_verify="$value"
          fi
          ;;
        publish_http_links)
          if [[ -n "$value" ]]; then
            publish_http_links="$value"
          fi
          ;;
        import_token)
          if [[ -n "$value" ]]; then
            import_token="$value"
          fi
          ;;
      esac
    done <<< "$metadata_loaded"
  fi

  if ! validate_client_server "$client_server"; then
    client_server="$(default_server_identity)"
  fi

  if [[ -z "$client_sni" ]]; then
    client_sni="$client_server"
  fi

  if [[ -n "$import_token" ]] && ! validate_import_token "$import_token"; then
    import_token=""
  fi

  save_anytls_client_metadata "$service_name" "$client_server" "$client_sni" "$skip_cert_verify" "$publish_http_links" "$import_token"
  ok "已接管现有 AnyTLS 配置，未修改 ${config_path} 或 ${service_name}"

  show_anytls_parameters_for_service "$service_name" || true
}

migrate_existing_anytls_flow() {
  local service_name="$1"
  local config_path parsed

  service_name="$(normalize_service_name "$service_name")"
  if ! service_exists "$service_name"; then
    die "未找到服务: ${service_name}"
  fi

  config_path="$(extract_config_path_from_service "$service_name")"
  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    die "未找到配置文件: ${config_path}"
  fi

  parsed="$(extract_anytls_inbound_details "$config_path")"

  local found listen_addr listen_port anytls_password tls_enabled cert_path key_path tls_server_name padding_scheme_json
  found="false"
  listen_addr=""
  listen_port=""
  anytls_password=""
  tls_enabled="false"
  cert_path=""
  key_path=""
  tls_server_name=""
  padding_scheme_json=""

  while IFS=$'\t' read -r key value; do
    case "$key" in
      found) found="$value" ;;
      listen) listen_addr="$value" ;;
      listen_port) listen_port="$value" ;;
      password) anytls_password="$value" ;;
      tls_enabled) tls_enabled="$value" ;;
      certificate_path) cert_path="$value" ;;
      key_path) key_path="$value" ;;
      tls_server_name) tls_server_name="$value" ;;
      padding_scheme_json) padding_scheme_json="$value" ;;
    esac
  done <<< "$parsed"

  if [[ "$found" != "true" ]]; then
    die "配置中未找到 AnyTLS inbound: ${config_path}"
  fi

  listen_addr="${listen_addr:-$ANYTLS_STANDARD_LISTEN_ADDR}"
  listen_port="${listen_port:-$ANYTLS_STANDARD_LISTEN_PORT}"
  listen_port="$(pick_existing_anytls_listen_port "$service_name" "$listen_port" "$ANYTLS_FALLBACK_LISTEN_PORT" "$listen_addr")"

  if [[ -z "$anytls_password" ]]; then
    die "未能从现有配置中读取 AnyTLS 密码: ${config_path}"
  fi

  if [[ "$tls_enabled" == "true" ]]; then
    if [[ -z "$cert_path" || -z "$key_path" ]]; then
      die "现有 TLS 配置不完整，未找到证书或私钥路径。"
    fi
  else
    cert_path=""
    key_path=""
    tls_server_name=""
  fi

  local config_backup_path service_file service_backup_path
  config_backup_path="$(backup_file_if_exists "$config_path")"
  service_file="$(service_unit_file_path "$service_name")"
  service_backup_path="$(backup_file_if_exists "$service_file")"

  if [[ -n "$config_backup_path" ]]; then
    ok "已创建配置备份: ${config_backup_path}"
  fi
  if [[ -n "$service_backup_path" ]]; then
    ok "已创建服务备份: ${service_backup_path}"
  fi

  write_anytls_config "$config_path" "$listen_addr" "$listen_port" "$anytls_password" "$tls_enabled" "$cert_path" "$key_path" "$tls_server_name" "$padding_scheme_json"
  validate_config_file "$config_path" || die "生成的配置无效: ${config_path}"
  ok "已按现有参数重写 AnyTLS 配置: ${config_path}"

  write_service_file "$service_name" "$config_path"

  if ! apply_service_state_auto "$service_name"; then
    if [[ -n "$config_backup_path" && -f "$config_backup_path" ]]; then
      cp "$config_backup_path" "$config_path"
      warn "服务应用失败，已回滚配置文件: ${config_path}"
    fi
    if [[ -n "$service_backup_path" && -f "$service_backup_path" ]]; then
      cp "$service_backup_path" "$service_file"
      systemctl daemon-reload
      warn "服务应用失败，已回滚服务文件: ${service_file}"
    fi
    systemctl restart "$service_name" >/dev/null 2>&1 || true
    die "迁移现有 AnyTLS 失败，请检查日志。"
  fi

  ok "已使用脚本重配 ${service_name}，并保留原有 AnyTLS 参数"
  show_anytls_parameters_for_service "$service_name" || true
}

anytls_wizard_flow() {
  if [[ ! -x "$BINARY_PATH" ]]; then
    die "未找到 sing-box 二进制，请先执行安装。"
  fi

  CURRENT_SERVICE_NAME="$ANYTLS_STANDARD_SERVICE_NAME"

  local existing_config_path config_path
  existing_config_path=""
  if service_exists "$CURRENT_SERVICE_NAME"; then
    existing_config_path="$(extract_config_path_from_service "$CURRENT_SERVICE_NAME")"
  fi

  config_path="${existing_config_path:-$ANYTLS_STANDARD_CONFIG_PATH}"

  if [[ -n "$existing_config_path" && -f "$config_path" ]] && config_has_anytls_inbound "$config_path"; then
    local existing_listen_addr existing_port conflict_target_port conflict_target_addr
    existing_listen_addr="$(extract_anytls_inbound_details "$config_path" | awk -F '\t' '$1 == "listen" {print $2; exit}')"
    existing_port="$(extract_anytls_inbound_details "$config_path" | awk -F '\t' '$1 == "listen_port" {print $2; exit}')"
    conflict_target_addr="${existing_listen_addr:-$ANYTLS_STANDARD_LISTEN_ADDR}"
    conflict_target_port="${existing_port:-$ANYTLS_STANDARD_LISTEN_PORT}"
    info "检测到现有 AnyTLS 服务: ${CURRENT_SERVICE_NAME}"
    info "当前配置文件: ${config_path}"
    if is_listen_port_occupied "$conflict_target_addr" "$conflict_target_port" && ! service_owns_listen_port "$CURRENT_SERVICE_NAME" "$conflict_target_port"; then
      warn "检测到当前 AnyTLS 端口 ${conflict_target_port} 已被其他进程占用，保持不变会继续起不来。"
      if prompt_yes_no "按脚本重配当前 AnyTLS，并默认改用 ${ANYTLS_FALLBACK_LISTEN_PORT}？" "y"; then
        migrate_existing_anytls_flow "$CURRENT_SERVICE_NAME"
        return 0
      fi
    fi
    if prompt_yes_no "接管现有配置并保持当前 AnyTLS 不变？" "y"; then
      adopt_existing_anytls_flow "$CURRENT_SERVICE_NAME"
      return 0
    fi
    if prompt_yes_no "按脚本重配当前 AnyTLS，并沿用现有密码/端口/证书路径？" "y"; then
      migrate_existing_anytls_flow "$CURRENT_SERVICE_NAME"
      return 0
    fi
  fi

  local listen_addr listen_port
  listen_addr="$ANYTLS_STANDARD_LISTEN_ADDR"
  listen_port="$(pick_available_anytls_listen_port "$ANYTLS_STANDARD_LISTEN_PORT" "$ANYTLS_FALLBACK_LISTEN_PORT" "$listen_addr")"

  local anytls_password existing_password
  anytls_password="$(generate_password)"
  existing_password="$(extract_anytls_password_from_config "$config_path")"
  if [[ -n "$existing_password" ]]; then
    anytls_password="$existing_password"
    info "检测到现有 AnyTLS 密码，已沿用。"
  fi

  local tls_enabled cert_path key_path generated_self_signed
  tls_enabled="true"
  cert_path="$ANYTLS_STANDARD_CERT_PATH"
  key_path="$ANYTLS_STANDARD_KEY_PATH"
  generated_self_signed="false"

  if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
    local default_cn
    default_cn="$(default_server_identity)"
    generate_self_signed_cert "$cert_path" "$key_path" "$default_cn"
    generated_self_signed="true"
  fi

  local backup_path
  backup_path="$(backup_file_if_exists "$config_path")"
  if [[ -n "$backup_path" ]]; then
    ok "已创建配置备份: ${backup_path}"
  fi

  write_anytls_config "$config_path" "$listen_addr" "$listen_port" "$anytls_password" "$tls_enabled" "$cert_path" "$key_path"
  validate_config_file "$config_path" || die "生成的配置无效: ${config_path}"
  ok "已写入 AnyTLS 配置: ${config_path}"

  local client_server client_sni skip_cert_verify
  local publish_http_links import_token
  local metadata_loaded
  client_server="$(default_server_identity)"
  client_sni="$client_server"
  skip_cert_verify="false"

  metadata_loaded="$(load_anytls_client_metadata "$CURRENT_SERVICE_NAME")"
  if [[ -n "$metadata_loaded" ]]; then
    while IFS=$'\t' read -r key value; do
      case "$key" in
        client_server)
          if [[ -n "$value" ]]; then
            client_server="$value"
          fi
          ;;
        client_sni)
          if [[ -n "$value" ]]; then
            client_sni="$value"
          fi
          ;;
        skip_cert_verify)
          if [[ -n "$value" ]]; then
            skip_cert_verify="$value"
          fi
          ;;
      esac
    done <<< "$metadata_loaded"
  fi

  if ! validate_client_server "$client_server"; then
    client_server="localhost"
  fi

  if [[ -z "$client_sni" ]]; then
    client_sni="$client_server"
  fi

  if [[ "$generated_self_signed" == "true" ]]; then
    skip_cert_verify="true"
  fi

  publish_http_links="false"
  import_token=""

  save_anytls_client_metadata "$CURRENT_SERVICE_NAME" "$client_server" "$client_sni" "$skip_cert_verify" "$publish_http_links" "$import_token"
  write_password_file "$DEFAULT_ANYTLS_PASSWORD_FILE" "$anytls_password"

  write_service_file "$CURRENT_SERVICE_NAME" "$config_path"

  if [[ -n "$backup_path" ]]; then
    info "检测到历史配置，已按标准参数覆盖。"
  fi
  info "已应用标准参数：监听 ${listen_addr}:${listen_port}、启用 TLS、关闭一键导入发布。"

  if ! apply_service_state_auto "$CURRENT_SERVICE_NAME"; then
    if [[ -n "$backup_path" && -f "$backup_path" ]]; then
      cp "$backup_path" "$config_path"
      warn "服务应用失败，已回滚配置文件: ${config_path}"
      systemctl restart "$CURRENT_SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    die "应用 AnyTLS 服务状态失败，请检查日志。"
  fi

  show_anytls_parameters_for_service "$CURRENT_SERVICE_NAME" || true
}
