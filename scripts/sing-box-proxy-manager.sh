#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="v1"
GITHUB_REPO="SagerNet/sing-box"
PROJECT_ROOT="/root/sing-box-proxy"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
TOOLS_DIR="${PROJECT_ROOT}/tools"
DATA_DIR="${PROJECT_ROOT}/data"
INSTALL_DIR="/usr/local/bin"
BINARY_PATH="${INSTALL_DIR}/sing-box"
DEFAULT_SERVICE_NAME="sing-box.service"
DEFAULT_CONFIG_PATH="/etc/sing-box/config.json"
DEFAULT_ANYTLS_PASSWORD_FILE="/etc/sing-box/anytls_password.txt"
ANYTLS_STANDARD_SERVICE_NAME="sing-box-anytls.service"
ANYTLS_STANDARD_CONFIG_PATH="/etc/sing-box/anytls.json"
ANYTLS_STANDARD_LISTEN_ADDR="::"
ANYTLS_STANDARD_LISTEN_PORT="443"
ANYTLS_FALLBACK_LISTEN_PORT="8443"
ANYTLS_STANDARD_CERT_PATH="/etc/sing-box/cert.pem"
ANYTLS_STANDARD_KEY_PATH="/etc/sing-box/key.pem"
ANYTLS_METADATA_DIR="${DATA_DIR}/metadata"
CLIENT_IMPORT_DIR="${DATA_DIR}/client-import"
CLIENT_IMPORT_PUBLISH_DIR="${DATA_DIR}/client-import-publish"
CLIENT_IMPORT_HTTP_SERVICE="sing-box-import-http.service"
CLIENT_IMPORT_HTTP_SCRIPT="${TOOLS_DIR}/import-http-server.py"
CLIENT_IMPORT_HTTP_PORT="18080"

COLOR_RESET='\033[0m'
COLOR_RED='\033[31m'
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_BLUE='\033[34m'

CURRENT_SERVICE_NAME=""

validate_service_name() {
  local service_name="$1"
  [[ "$service_name" =~ ^[A-Za-z0-9_.@-]+$ ]]
}

info() {
  printf "%b[INFO]%b %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$*" >&2
}

warn() {
  printf "%b[WARN]%b %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

ok() {
  printf "%b[ OK ]%b %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$*" >&2
}

die() {
  printf "%b[ERR ]%b %s\n" "$COLOR_RED" "$COLOR_RESET" "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请以 root 身份运行。"
  fi
}

require_commands() {
  local missing=()
  local cmd
  for cmd in curl tar install awk sed grep mktemp uname systemctl find head cp date python3 realpath; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "缺少依赖命令: ${missing[*]}"
  fi
}

pause() {
  read -r -p "按回车继续..." _
}

normalize_service_name() {
  local value="$1"
  if [[ "$value" != *.service ]]; then
    value="${value}.service"
  fi

  if ! validate_service_name "$value"; then
    die "服务名不合法: ${value}"
  fi

  printf "%s" "$value"
}

detect_arch() {
  local machine
  machine="$(uname -m)"

  case "$machine" in
    x86_64|amd64) printf "amd64" ;;
    aarch64|arm64) printf "arm64" ;;
    armv7l|armv7) printf "armv7" ;;
    armv6l|armv6) printf "armv6" ;;
    i386|i686) printf "386" ;;
    *) die "不支持的架构: ${machine}" ;;
  esac
}

normalize_version() {
  local version="$1"
  version="${version#v}"
  printf "%s" "$version"
}

default_server_identity() {
  local host_value ip_value
  host_value="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
  ip_value="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"

  if [[ -n "$ip_value" ]]; then
    printf "%s" "$ip_value"
    return 0
  fi

  if [[ -n "$host_value" ]]; then
    printf "%s" "$host_value"
    return 0
  fi

  printf "localhost"
}

is_listen_port_occupied() {
  local listen_addr="$1"
  local listen_port="$2"

  LISTEN_ADDR="$listen_addr" LISTEN_PORT="$listen_port" python3 - <<'PY'
import errno
import os
import socket

listen_addr = os.environ.get('LISTEN_ADDR', '').strip()
listen_port = int(os.environ['LISTEN_PORT'])

candidates = []
if not listen_addr or listen_addr == '::':
    candidates.append((socket.AF_INET6, '::', False))
elif ':' in listen_addr:
    candidates.append((socket.AF_INET6, listen_addr, True))
else:
    candidates.append((socket.AF_INET, listen_addr, True))

if not candidates:
    raise SystemExit(1)

for family, host, v6only in candidates:
    sock = None
    try:
        sock = socket.socket(family, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if family == socket.AF_INET6 and hasattr(socket, 'IPPROTO_IPV6') and hasattr(socket, 'IPV6_V6ONLY'):
            sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1 if v6only else 0)
        if family == socket.AF_INET6:
            sock.bind((host, listen_port, 0, 0))
        else:
            sock.bind((host, listen_port))
        raise SystemExit(1)
    except OSError as exc:
        if exc.errno == errno.EADDRINUSE:
            raise SystemExit(0)
        if family == socket.AF_INET6 and exc.errno in (errno.EAFNOSUPPORT, errno.EADDRNOTAVAIL):
            continue
        raise
    finally:
        if sock is not None:
            sock.close()

if listen_addr in ('', '::'):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(('0.0.0.0', listen_port))
        sock.close()
        raise SystemExit(1)
    except OSError as exc:
        if exc.errno == errno.EADDRINUSE:
            raise SystemExit(0)
        raise

raise SystemExit(1)
PY
}

pick_available_anytls_listen_port() {
  local preferred_port="${1:-$ANYTLS_STANDARD_LISTEN_PORT}"
  local fallback_port="${2:-$ANYTLS_FALLBACK_LISTEN_PORT}"
  local listen_addr="${3:-$ANYTLS_STANDARD_LISTEN_ADDR}"

  if ! is_listen_port_occupied "$listen_addr" "$preferred_port"; then
    printf "%s" "$preferred_port"
    return 0
  fi

  warn "检测到 ${listen_addr}:${preferred_port} 已被占用，默认改用 ${fallback_port}"

  if ! is_listen_port_occupied "$listen_addr" "$fallback_port"; then
    printf "%s" "$fallback_port"
    return 0
  fi

  die "检测到 ${preferred_port} 和 ${fallback_port} 都已被占用，请先处理端口冲突。"
}

validate_client_server() {
  local value="$1"

  CLIENT_SERVER="$value" python3 - <<'PY'
import ipaddress
import os
import re
import sys

value = os.environ.get('CLIENT_SERVER', '').strip()
if not value:
    raise SystemExit(1)

for forbidden in ('://', '/', ' ', '?', '#', '@'):
    if forbidden in value:
        raise SystemExit(1)

host = value
if host.startswith('[') and host.endswith(']'):
    host = host[1:-1]

if ':' in host:
    try:
        ipaddress.IPv6Address(host)
    except ValueError:
        raise SystemExit(1)
    raise SystemExit(0)

try:
    ipaddress.IPv4Address(host)
    raise SystemExit(0)
except ValueError:
    pass

domain_pattern = re.compile(r'^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))*$')
if domain_pattern.fullmatch(host):
    raise SystemExit(0)

raise SystemExit(1)
PY
}

validate_import_token() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9]{6,64}$ ]]
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-32
    return 0
  fi

  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 6
    return 0
  fi

  tr -dc 'a-f0-9' </dev/urandom | head -c 12
}

format_host_for_url() {
  local host="$1"
  if [[ "$host" == *:* && "$host" != \[*\] ]]; then
    printf "[%s]" "$host"
    return 0
  fi
  printf "%s" "$host"
}

is_safe_removal_path() {
  local path="$1"
  local resolved

  if [[ -z "$path" ]]; then
    return 1
  fi

  resolved="$(realpath -m "$path" 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    return 1
  fi

  case "$resolved" in
    /etc/sing-box/*|/root/sing-box-proxy/*|/root/proxy/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

backup_file_if_exists() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    printf ""
    return 0
  fi

  local backup_path
  backup_path="${file_path}.bak-$(date +%Y%m%d%H%M%S)"
  cp "$file_path" "$backup_path"
  printf "%s" "$backup_path"
}

validate_config_file() {
  local config_path="$1"
  "$BINARY_PATH" check -c "$config_path" >/dev/null
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

fetch_latest_version() {
  local api_url json version
  api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

  json="$(curl -fsSL "$api_url")" || die "从 GitHub API 获取最新版本失败。"
  version="$(printf "%s" "$json" | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^\"]+)".*/\1/')"

  if [[ -z "$version" ]]; then
    die "无法解析 GitHub API 返回的最新版本号。"
  fi

  printf "%s" "$version"
}

current_version() {
  if [[ ! -x "$BINARY_PATH" ]]; then
    printf ""
    return 0
  fi

  "$BINARY_PATH" version 2>/dev/null | head -n1 | sed -E 's/.*version[[:space:]]+([^[:space:]]+).*/\1/'
}

download_release() {
  local version="$1"
  local arch="$2"
  local workspace="$3"
  local archive_url archive_path extracted_bin

  archive_url="https://github.com/${GITHUB_REPO}/releases/download/v${version}/sing-box-${version}-linux-${arch}.tar.gz"
  archive_path="${workspace}/sing-box-${version}.tar.gz"

  info "正在下载: ${archive_url}"
  curl -fL --retry 3 --connect-timeout 10 "$archive_url" -o "$archive_path" || die "下载失败。"

  tar -xzf "$archive_path" -C "$workspace" || die "解压失败。"

  extracted_bin="$(find "$workspace" -type f -name sing-box | head -n1 || true)"
  if [[ -z "$extracted_bin" ]]; then
    die "解压后未找到 sing-box 可执行文件。"
  fi

  printf "%s" "$extracted_bin"
}

backup_existing_binary() {
  if [[ ! -f "$BINARY_PATH" ]]; then
    return 0
  fi

  local backup_path
  backup_path="${BINARY_PATH}.bak-$(date +%Y%m%d%H%M%S)"
  cp "$BINARY_PATH" "$backup_path"
  ok "已创建备份: ${backup_path}"
}

install_binary_file() {
  local source_path="$1"
  mkdir -p "$INSTALL_DIR"
  install -m 0755 "$source_path" "$BINARY_PATH"
  ok "已安装二进制: ${BINARY_PATH}"
}

install_or_update_version() {
  local target_version="$1"
  target_version="$(normalize_version "$target_version")"

  local arch temp_dir extracted_bin final_version
  arch="$(detect_arch)"
  temp_dir="$(mktemp -d)"

  extracted_bin="$(download_release "$target_version" "$arch" "$temp_dir")"
  backup_existing_binary
  install_binary_file "$extracted_bin"

  rm -rf "$temp_dir"

  final_version="$(current_version)"
  if [[ -z "$final_version" ]]; then
    die "安装完成但无法读取 sing-box 版本。"
  fi

  ok "sing-box 版本: ${final_version}"
}

list_service_candidates() {
  systemctl list-unit-files --type=service --no-legend 2>/dev/null \
    | awk '{print $1}' \
    | grep -E '^sing-box.*\.service$' || true
}

service_exists() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  systemctl cat "$service_name" >/dev/null 2>&1
}

extract_config_path_from_service() {
  local service_name exec_line
  service_name="$(normalize_service_name "$1")"

  exec_line="$(systemctl cat "$service_name" 2>/dev/null | grep -E '^ExecStart=' | tail -n1 || true)"
  if [[ -z "$exec_line" ]]; then
    printf ""
    return 0
  fi

  if [[ "$exec_line" =~ -c[[:space:]]+([^[:space:]]+) ]]; then
    printf "%s" "${BASH_REMATCH[1]}"
  else
    printf ""
  fi
}

is_service_active() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  systemctl is-active --quiet "$service_name"
}

is_service_enabled() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  systemctl is-enabled --quiet "$service_name"
}

prompt_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local answer

  while true; do
    if [[ "$default_value" == "y" ]]; then
      read -r -p "${prompt} [Y/n]: " answer
      answer="${answer:-y}"
    else
      read -r -p "${prompt} [y/N]: " answer
      answer="${answer:-n}"
    fi

    case "${answer,,}" in
      y|yes|是|shi) return 0 ;;
      n|no|否|fou) return 1 ;;
      *) warn "请输入 y 或 n。" ;;
    esac
  done
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

service_unit_file_path() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  printf "/etc/systemd/system/%s" "$service_name"
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

uninstall_singbox_full_flow() {
  warn "完整卸载将删除 sing-box 二进制和全部 sing-box 服务。"
  if ! prompt_yes_no "确认继续完整卸载吗？" "n"; then
    return 0
  fi

  local confirm
  read -r -p "输入 UNINSTALL（或“卸载”）继续: " confirm
  if [[ "$confirm" != "UNINSTALL" && "$confirm" != "卸载" ]]; then
    warn "确认口令不匹配，已取消。"
    return 0
  fi

  local services unit service
  services="$(list_service_candidates)"

  local config_paths=()
  while IFS= read -r service; do
    [[ -z "$service" ]] && continue
    if service_exists "$service"; then
      local cfg
      cfg="$(extract_config_path_from_service "$service")"
      if [[ -n "$cfg" ]]; then
        config_paths+=("$cfg")
      fi
    fi
  done <<< "$services"

  while IFS= read -r service; do
    [[ -z "$service" ]] && continue
    if ! prompt_yes_no "卸载服务 ${service}？" "y"; then
      continue
    fi
    systemctl disable --now "$service" >/dev/null 2>&1 || true
    ok "已停止并禁用服务: ${service}"
    unit="$(service_unit_file_path "$service")"
    if [[ -f "$unit" ]]; then
      rm -f "$unit"
      ok "已删除 unit 文件: ${unit}"
    fi
  done <<< "$services"

  if systemctl cat "$CLIENT_IMPORT_HTTP_SERVICE" >/dev/null 2>&1; then
    systemctl disable --now "$CLIENT_IMPORT_HTTP_SERVICE" >/dev/null 2>&1 || true
    ok "已停止并禁用服务: ${CLIENT_IMPORT_HTTP_SERVICE}"
    unit="$(service_unit_file_path "$CLIENT_IMPORT_HTTP_SERVICE")"
    if [[ -f "$unit" ]]; then
      rm -f "$unit"
      ok "已删除 unit 文件: ${unit}"
    fi
  fi

  if prompt_yes_no "删除 sing-box 二进制 ${BINARY_PATH}？" "y"; then
    if [[ -f "$BINARY_PATH" ]]; then
      rm -f "$BINARY_PATH"
      ok "已删除二进制: ${BINARY_PATH}"
    fi
  fi

  if prompt_yes_no "删除备份二进制 ${BINARY_PATH}.bak-* ?" "n"; then
    find "$INSTALL_DIR" -maxdepth 1 -type f -name 'sing-box.bak-*' -print -delete || true
    ok "已删除 ${INSTALL_DIR} 下的备份二进制"
  fi

  if prompt_yes_no "删除服务引用的配置文件？" "y"; then
    local cfg_path
    for cfg_path in "${config_paths[@]}"; do
      if [[ -f "$cfg_path" ]]; then
        local remove_cfg_default
        remove_cfg_default="n"
        if is_safe_removal_path "$cfg_path"; then
          remove_cfg_default="y"
        fi
        if prompt_yes_no "删除配置文件 ${cfg_path}？" "$remove_cfg_default"; then
          rm -f "$cfg_path"
          ok "已删除配置文件: ${cfg_path}"
        fi
      fi
    done
  fi

  if prompt_yes_no "删除 /etc/sing-box 目录？" "n"; then
    if [[ -d "/etc/sing-box" ]]; then
      rm -rf "/etc/sing-box"
      ok "已删除目录: /etc/sing-box"
    fi
  fi

  if prompt_yes_no "删除 AnyTLS 元数据和客户端导入文件？" "y"; then
    rm -rf "$ANYTLS_METADATA_DIR" "$CLIENT_IMPORT_DIR" "$CLIENT_IMPORT_PUBLISH_DIR"
    ok "已删除 ${ANYTLS_METADATA_DIR}、${CLIENT_IMPORT_DIR} 和 ${CLIENT_IMPORT_PUBLISH_DIR}"
  fi

  systemctl daemon-reload
  systemctl reset-failed >/dev/null 2>&1 || true
  ok "sing-box 完整卸载完成"
}

uninstall_menu_flow() {
  while true; do
    printf "\n卸载选项：\n"
    printf "1) 卸载单个 AnyTLS 服务\n"
    printf "2) 完整卸载 sing-box\n"
    printf "0) 返回\n\n"

    local choice
    read -r -p "请选择卸载操作: " choice

    case "$choice" in
      1)
        prompt_service_name
        uninstall_anytls_service_flow "$CURRENT_SERVICE_NAME"
        return 0
        ;;
      2)
        uninstall_singbox_full_flow
        return 0
        ;;
      0)
        return 0
        ;;
      *)
        warn "无效选项。"
        ;;
    esac
  done
}

pick_default_service() {
  local candidates
  candidates="$(list_service_candidates)"

  if printf "%s\n" "$candidates" | grep -qx 'sing-box-anytls.service'; then
    printf "sing-box-anytls.service"
    return 0
  fi

  if [[ -n "$candidates" ]]; then
    printf "%s\n" "$candidates" | head -n1
    return 0
  fi

  printf "%s" "$DEFAULT_SERVICE_NAME"
}

prompt_service_name() {
  local default_service user_input
  default_service="$(pick_default_service)"

  if [[ -n "$CURRENT_SERVICE_NAME" ]]; then
    default_service="$CURRENT_SERVICE_NAME"
  fi

  read -r -p "服务名 [${default_service}]: " user_input
  user_input="${user_input:-$default_service}"
  CURRENT_SERVICE_NAME="$(normalize_service_name "$user_input")"
}

write_default_config_if_missing() {
  local config_path="$1"
  if [[ -f "$config_path" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$config_path")"
  cat > "$config_path" <<'JSON'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
JSON

  ok "已创建默认配置: ${config_path}"
}

write_service_file() {
  local service_name="$1"
  local config_path="$2"
  local service_file

  service_name="$(normalize_service_name "$service_name")"
  service_file="/etc/systemd/system/${service_name}"

  cat > "$service_file" <<EOF
[Unit]
Description=sing-box Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BINARY_PATH} run -c ${config_path}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  ok "已写入服务文件: ${service_file}"
}

apply_service_state() {
  local service_name="$1"
  service_name="$(normalize_service_name "$service_name")"

  if prompt_yes_no "开机自启 ${service_name}？" "y"; then
    systemctl enable "$service_name"
    ok "已启用 ${service_name}"
  fi

  if is_service_active "$service_name"; then
    if prompt_yes_no "立即重启运行中的服务 ${service_name}？" "y"; then
      systemctl restart "$service_name"
      ok "已重启 ${service_name}"
    fi
  else
    if prompt_yes_no "立即启动 ${service_name}？" "y"; then
      systemctl start "$service_name"
      ok "已启动 ${service_name}"
    fi
  fi
}

apply_service_state_auto() {
  local service_name="$1"
  service_name="$(normalize_service_name "$service_name")"

  if systemctl enable "$service_name" >/dev/null 2>&1; then
    ok "已启用 ${service_name}"
  else
    warn "启用开机自启失败: ${service_name}"
  fi

  if is_service_active "$service_name"; then
    if systemctl restart "$service_name"; then
      ok "已重启 ${service_name}"
    else
      warn "重启服务失败: ${service_name}"
      return 1
    fi
  else
    if systemctl start "$service_name"; then
      ok "已启动 ${service_name}"
    else
      warn "启动服务失败: ${service_name}"
      return 1
    fi
  fi
}

is_valid_port() {
  local port_value="$1"
  [[ "$port_value" =~ ^[0-9]+$ ]] || return 1
  (( port_value >= 1 && port_value <= 65535 ))
}

generate_self_signed_cert() {
  local cert_path="$1"
  local key_path="$2"
  local common_name="$3"

  command -v openssl >/dev/null 2>&1 || die "生成自签证书需要 openssl。"

  mkdir -p "$(dirname "$cert_path")"
  mkdir -p "$(dirname "$key_path")"

  openssl req -x509 -nodes -newkey rsa:2048 \
    -days 3650 \
    -keyout "$key_path" \
    -out "$cert_path" \
    -subj "/CN=${common_name}" >/dev/null 2>&1 || die "生成自签证书失败。"

  chmod 644 "$cert_path"
  chmod 600 "$key_path"
  ok "已生成自签证书: ${cert_path}"
  ok "已生成私钥: ${key_path}"
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
    info "检测到现有 AnyTLS 服务: ${CURRENT_SERVICE_NAME}"
    info "当前配置文件: ${config_path}"
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

configure_service_flow() {
  if [[ ! -x "$BINARY_PATH" ]]; then
    die "未找到 sing-box 二进制，请先执行安装。"
  fi

  prompt_service_name

  local existing_config_path default_config_path config_path
  existing_config_path=""
  if service_exists "$CURRENT_SERVICE_NAME"; then
    existing_config_path="$(extract_config_path_from_service "$CURRENT_SERVICE_NAME")"
  fi

  default_config_path="${existing_config_path:-$DEFAULT_CONFIG_PATH}"
  read -r -p "配置路径 [${default_config_path}]: " config_path
  config_path="${config_path:-$default_config_path}"

  if [[ ! -f "$config_path" ]]; then
    warn "未找到配置: ${config_path}"
    if prompt_yes_no "现在创建默认配置？" "y"; then
      write_default_config_if_missing "$config_path"
    else
      die "启动服务需要配置文件。"
    fi
  fi

  write_service_file "$CURRENT_SERVICE_NAME" "$config_path"
  apply_service_state "$CURRENT_SERVICE_NAME"
}

show_status() {
  local version default_service

  version="$(current_version)"
  if [[ -n "$version" ]]; then
    printf "sing-box 二进制 : %s\n" "$BINARY_PATH"
    printf "sing-box 版本   : %s\n" "$version"
  else
    printf "sing-box 二进制 : 未安装\n"
  fi

  printf "\n已发现的 sing-box 服务：\n"
  local units
  units="$(list_service_candidates)"
  if [[ -z "$units" ]]; then
    printf "  （无）\n"
  else
    while IFS= read -r unit; do
      [[ -z "$unit" ]] && continue
      printf "  - %s | active=%s | enabled=%s\n" \
        "$unit" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done <<< "$units"
  fi

  default_service="$(pick_default_service)"
  printf "\n当前脚本默认服务: %s\n" "$default_service"
}

install_flow() {
  local latest_version target_version

  latest_version="$(fetch_latest_version)"
  read -r -p "目标版本 [${latest_version}]: " target_version
  target_version="${target_version:-$latest_version}"

  install_or_update_version "$target_version"

  if prompt_yes_no "现在配置 systemd 服务？" "y"; then
    configure_service_flow
  fi
}

update_flow() {
  local installed latest_version target_version
  installed="$(current_version)"

  if [[ -z "$installed" ]]; then
    warn "当前未安装 sing-box，切换到安装流程。"
    install_flow
    return 0
  fi

  latest_version="$(fetch_latest_version)"
  printf "当前版本: %s\n" "$installed"
  printf "最新版本: %s\n" "$latest_version"

  read -r -p "目标版本 [${latest_version}]: " target_version
  target_version="${target_version:-$latest_version}"

  if [[ "$(normalize_version "$target_version")" == "$(normalize_version "$installed")" ]]; then
    if ! prompt_yes_no "目标版本与当前版本一致，仍要重装吗？" "n"; then
      return 0
    fi
  fi

  install_or_update_version "$target_version"

  prompt_service_name
  if service_exists "$CURRENT_SERVICE_NAME"; then
    if prompt_yes_no "更新后重启 ${CURRENT_SERVICE_NAME}？" "y"; then
      if is_service_active "$CURRENT_SERVICE_NAME"; then
        systemctl restart "$CURRENT_SERVICE_NAME"
        ok "已重启 ${CURRENT_SERVICE_NAME}"
      else
        warn "${CURRENT_SERVICE_NAME} 当前未运行。"
        if prompt_yes_no "立即启动 ${CURRENT_SERVICE_NAME}？" "y"; then
          systemctl start "$CURRENT_SERVICE_NAME"
          ok "已启动 ${CURRENT_SERVICE_NAME}"
        fi
      fi
    fi
  else
    warn "未找到服务: ${CURRENT_SERVICE_NAME}"
    if prompt_yes_no "现在创建服务？" "y"; then
      configure_service_flow
    fi
  fi
}

print_header() {
  printf "\n"
  printf "sing-box 代理管理脚本 %s\n" "$SCRIPT_VERSION"
  printf "二进制路径: %s\n" "$BINARY_PATH"
  printf "\n"
}

main_menu() {
  while true; do
    print_header
    printf "1) 安装 sing-box\n"
    printf "2) 更新 sing-box\n"
    printf "3) 配置 systemd 服务\n"
    printf "4) 查看状态\n"
    printf "5) AnyTLS 配置向导\n"
    printf "6) 查看 AnyTLS 参数\n"
    printf "7) 卸载\n"
    printf "0) 退出\n\n"

    read -r -p "请选择操作: " choice

    case "$choice" in
      1)
        install_flow
        pause
        ;;
      2)
        update_flow
        pause
        ;;
      3)
        configure_service_flow
        pause
        ;;
      4)
        show_status
        pause
        ;;
      5)
        anytls_wizard_flow
        pause
        ;;
      6)
        show_anytls_parameters_flow
        pause
        ;;
      7)
        uninstall_menu_flow
        pause
        ;;
      0)
        ok "已退出。"
        exit 0
        ;;
      *)
        warn "无效选项。"
        pause
        ;;
    esac
  done
}

main() {
  require_root
  require_commands
  main_menu
}

main "$@"
