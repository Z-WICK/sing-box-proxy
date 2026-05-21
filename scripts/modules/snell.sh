#!/usr/bin/env bash

: "${SNELL_SERVICE_NAME:=snell-server.service}"
: "${SNELL_INSTALL_DIR:=/usr/local/bin}"
: "${SNELL_BINARY_PATH:=${SNELL_INSTALL_DIR}/snell-server}"
: "${SNELL_CONFIG_DIR:=/etc/snell}"
: "${SNELL_CONFIG_PATH:=${SNELL_CONFIG_DIR}/config.conf}"
: "${SNELL_VERSION_FILE:=${SNELL_CONFIG_DIR}/ver.txt}"
: "${SNELL_V4_RELEASE_VERSION:=4.1.1}"
: "${SNELL_V5_RELEASE_VERSION:=5.0.1}"
: "${SNELL_DEFAULT_PROTOCOL_VERSION:=5}"
: "${SNELL_DEFAULT_LISTEN_PORT:=2345}"
: "${SNELL_FALLBACK_LISTEN_PORT:=2346}"
: "${SNELL_DEFAULT_IPV6:=false}"
: "${SNELL_DEFAULT_OBFS:=off}"
: "${SNELL_DEFAULT_TFO:=true}"
: "${SNELL_DEFAULT_DNS:=1.1.1.1, 8.8.8.8, 2001:4860:4860::8888}"
: "${SNELL_DEFAULT_OBFS_HOST:=icloud.com}"

register_snell_menu_items() {
  register_protocol_menu_item "Snell" "配置向导" "snell_wizard_flow"
  register_protocol_menu_item "Snell" "查看参数" "show_snell_parameters_flow"
  register_protocol_menu_item "Snell" "更新服务端二进制" "update_snell_server_flow"
  register_protocol_menu_item "Snell" "卸载 Snell Server" "uninstall_snell_flow"
}

validate_snell_port() {
  local port_value="$1"
  [[ "$port_value" =~ ^[0-9]+$ ]] || return 1
  (( port_value >= 1 && port_value <= 65535 ))
}

validate_snell_psk() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9_.@:=+-]{8,128}$ ]]
}

validate_snell_obfs() {
  local value="$1"
  [[ "$value" == "off" || "$value" == "tls" || "$value" == "http" ]]
}

validate_snell_version() {
  local value="$1"
  [[ "$value" == "4" || "$value" == "5" ]]
}

validate_snell_bool() {
  local value="$1"
  [[ "$value" == "true" || "$value" == "false" ]]
}

validate_snell_obfs_host() {
  local host="$1"

  SNELL_OBFS_HOST="$host" python3 - <<'PY'
import os
import re

host = os.environ.get('SNELL_OBFS_HOST', '').strip().lower().rstrip('.')
if not host:
    raise SystemExit(1)

if any(ch in host for ch in (' ', '/', ':', '?', '#', '@', ',')):
    raise SystemExit(1)

pattern = re.compile(r'^(?=.{1,253}$)(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))+$')
raise SystemExit(0 if pattern.fullmatch(host) else 1)
PY
}

validate_snell_dns_list() {
  local value="$1"

  SNELL_DNS_LIST="$value" python3 - <<'PY'
import ipaddress
import os

items = [item.strip() for item in os.environ.get('SNELL_DNS_LIST', '').split(',')]
items = [item for item in items if item]
if not items:
    raise SystemExit(1)

for item in items:
    try:
        ipaddress.ip_address(item)
    except ValueError:
        raise SystemExit(1)

raise SystemExit(0)
PY
}

generate_snell_psk() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16 | cut -c1-24
    return 0
  fi

  python3 - <<'PY'
import secrets

print(secrets.token_hex(12))
PY
}

detect_snell_arch() {
  local machine
  machine="$(uname -m)"

  case "$machine" in
    x86_64|amd64) printf "amd64" ;;
    aarch64|arm64) printf "aarch64" ;;
    armv7l|armv7|armv6l|armv6) printf "armv7l" ;;
    i386|i686) printf "i386" ;;
    *) die "Snell Server 不支持当前架构: ${machine}" ;;
  esac
}

snell_release_version_for_protocol() {
  local protocol_version="$1"

  case "$protocol_version" in
    4) printf "%s" "$SNELL_V4_RELEASE_VERSION" ;;
    5) printf "%s" "$SNELL_V5_RELEASE_VERSION" ;;
    *) die "不支持的 Snell 协议版本: ${protocol_version}" ;;
  esac
}

snell_download_url() {
  local release_version="$1"
  local arch="$2"
  printf "https://dl.nssurge.com/snell/snell-server-v%s-linux-%s.zip" "$release_version" "$arch"
}

normalize_snell_release_version() {
  local value="$1"
  value="${value#v}"
  printf "%s" "$value"
}

installed_snell_release_version() {
  if [[ -f "$SNELL_VERSION_FILE" ]]; then
    normalize_snell_release_version "$(head -n1 "$SNELL_VERSION_FILE" | tr -d '[:space:]')"
    return 0
  fi

  printf ""
}

snell_binary_matches_release() {
  local release_version="$1"
  local installed

  [[ -x "$SNELL_BINARY_PATH" ]] || return 1
  installed="$(installed_snell_release_version)"
  [[ -n "$installed" && "$installed" == "$(normalize_snell_release_version "$release_version")" ]]
}

backup_snell_binary_if_exists() {
  if [[ ! -f "$SNELL_BINARY_PATH" ]]; then
    return 0
  fi

  local backup_path
  backup_path="${SNELL_BINARY_PATH}.bak-$(date +%Y%m%d%H%M%S)"
  cp "$SNELL_BINARY_PATH" "$backup_path"
  ok "已创建 Snell 二进制备份: ${backup_path}"
}

download_install_snell_binary() {
  local release_version="$1"
  local arch url temp_dir archive_path extracted_path

  release_version="$(normalize_snell_release_version "$release_version")"
  arch="$(detect_snell_arch)"
  url="$(snell_download_url "$release_version" "$arch")"
  temp_dir="$(mktemp -d)"
  archive_path="${temp_dir}/snell-server.zip"
  extracted_path="${temp_dir}/snell-server"

  info "正在下载 Snell Server: ${url}"
  if ! curl -fL --retry 3 --connect-timeout 10 "$url" -o "$archive_path"; then
    rm -rf "$temp_dir"
    die "下载 Snell Server 失败。"
  fi

  SNELL_ARCHIVE_PATH="$archive_path" \
  SNELL_EXTRACTED_PATH="$extracted_path" \
  python3 - <<'PY' || {
import os
import stat
import zipfile
from pathlib import Path

archive_path = Path(os.environ['SNELL_ARCHIVE_PATH'])
output_path = Path(os.environ['SNELL_EXTRACTED_PATH'])

with zipfile.ZipFile(archive_path) as archive:
    members = [
        name for name in archive.namelist()
        if not name.endswith('/') and name.rstrip('/').split('/')[-1] == 'snell-server'
    ]
    if not members:
        raise SystemExit(1)

    output_path.write_bytes(archive.read(members[0]))
    output_path.chmod(output_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PY
    rm -rf "$temp_dir"
    die "解压 Snell Server 失败。"
  }

  backup_snell_binary_if_exists
  mkdir -p "$SNELL_INSTALL_DIR"
  install -m 0755 "$extracted_path" "$SNELL_BINARY_PATH"
  mkdir -p "$SNELL_CONFIG_DIR"
  printf "v%s\n" "$release_version" > "$SNELL_VERSION_FILE"
  rm -rf "$temp_dir"

  ok "已安装 Snell Server: ${SNELL_BINARY_PATH}"
}

ensure_snell_binary_for_protocol() {
  local protocol_version="$1"
  local release_version

  release_version="$(snell_release_version_for_protocol "$protocol_version")"
  if snell_binary_matches_release "$release_version"; then
    ok "Snell Server 已是目标版本: v${release_version}"
    return 0
  fi

  download_install_snell_binary "$release_version"
}

write_snell_config() {
  local config_path="$1"
  local port="$2"
  local psk="$3"
  local obfs="$4"
  local obfs_host="$5"
  local ipv6="$6"
  local tfo="$7"
  local dns="$8"
  local protocol_version="$9"

  mkdir -p "$(dirname "$config_path")"

  {
    printf "[snell-server]\n"
    printf "listen = ::0:%s\n" "$port"
    printf "ipv6 = %s\n" "$ipv6"
    printf "psk = %s\n" "$psk"
    printf "obfs = %s\n" "$obfs"
    if [[ "$obfs" != "off" ]]; then
      printf "obfs-host = %s\n" "$obfs_host"
    fi
    printf "tfo = %s\n" "$tfo"
    printf "dns = %s\n" "$dns"
    printf "version = %s\n" "$protocol_version"
  } > "$config_path"

  chmod 600 "$config_path"
}

extract_snell_config_details() {
  local config_path="$1"

  SNELL_CONFIG_PATH_TO_PARSE="$config_path" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ['SNELL_CONFIG_PATH_TO_PARSE'])
if not path.is_file():
    print('found\tfalse')
    raise SystemExit(0)

data = {}
for raw_line in path.read_text(encoding='utf-8').splitlines():
    line = raw_line.strip()
    if not line or line.startswith('#') or line.startswith('['):
        continue
    if '=' not in line:
        continue
    key, value = line.split('=', 1)
    data[key.strip()] = value.strip()

listen = data.get('listen', '')
port = ''
if ':' in listen:
    port = listen.rsplit(':', 1)[-1].strip()

def emit(key, value):
    text = '' if value is None else str(value)
    print(f'{key}\t{text}')

emit('found', 'true')
emit('listen', listen)
emit('port', port)
emit('psk', data.get('psk', ''))
emit('obfs', data.get('obfs', 'off') or 'off')
emit('obfs_host', data.get('obfs-host', ''))
emit('ipv6', data.get('ipv6', 'false') or 'false')
emit('tfo', data.get('tfo', 'true') or 'true')
emit('dns', data.get('dns', ''))
emit('version', data.get('version', ''))
PY
}

set_snell_config_protocol_version() {
  local config_path="$1"
  local protocol_version="$2"

  validate_snell_version "$protocol_version" || return 1
  [[ -f "$config_path" ]] || return 1

  SNELL_CONFIG_PATH_TO_UPDATE="$config_path" \
  SNELL_PROTOCOL_VERSION_TO_UPDATE="$protocol_version" \
  python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ['SNELL_CONFIG_PATH_TO_UPDATE'])
protocol_version = os.environ['SNELL_PROTOCOL_VERSION_TO_UPDATE']
lines = path.read_text(encoding='utf-8').splitlines()

updated = False
next_lines = []
for line in lines:
    if line.strip().startswith('version') and '=' in line:
        next_lines.append(f'version = {protocol_version}')
        updated = True
    else:
        next_lines.append(line)

if not updated:
    next_lines.append(f'version = {protocol_version}')

path.write_text('\n'.join(next_lines) + '\n', encoding='utf-8')
path.chmod(0o600)
PY
}

snell_config_path_for_service() {
  local service_name="$1"
  local exec_line config_path

  if command -v systemctl >/dev/null 2>&1; then
    exec_line="$(systemctl cat "$service_name" 2>/dev/null | grep -E '^ExecStart=' | tail -n1 || true)"
    if [[ "$exec_line" =~ -c[[:space:]]+([^[:space:]]+) ]]; then
      config_path="${BASH_REMATCH[1]}"
      if [[ -n "$config_path" ]]; then
        printf "%s" "$config_path"
        return 0
      fi
    fi
  fi

  printf "%s" "$SNELL_CONFIG_PATH"
}

snell_service_exists() {
  local service_name="$1"
  if declare -F service_exists >/dev/null 2>&1; then
    service_exists "$service_name"
    return $?
  fi

  systemctl cat "$service_name" >/dev/null 2>&1
}

write_snell_service_file() {
  local service_name="$1"
  local config_path="$2"
  local service_file

  service_name="$(normalize_service_name "$service_name")"
  service_file="$(service_unit_file_path "$service_name")"

  cat > "$service_file" <<EOF
[Unit]
Description=Snell Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SNELL_BINARY_PATH} -c ${config_path}
Restart=on-failure
RestartSec=5
LimitNOFILE=32767

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  ok "已写入 Snell 服务文件: ${service_file}"
}

snell_format_host_for_client() {
  local host="$1"
  if [[ "$host" == *:* && "$host" != \[*\] ]]; then
    printf "[%s]" "$host"
    return 0
  fi
  printf "%s" "$host"
}

build_snell_surge_line() {
  local node_name="$1"
  local server="$2"
  local port="$3"
  local psk="$4"
  local protocol_version="$5"
  local tfo="$6"
  local obfs="$7"
  local obfs_host="$8"

  server="$(snell_format_host_for_client "$server")"

  local line
  line="${node_name} = snell, ${server}, ${port}, psk=${psk}, version=${protocol_version}, tfo=${tfo}"
  if [[ "$obfs" != "off" && -n "$obfs_host" ]]; then
    line+=", obfs=${obfs}, obfs-host=${obfs_host}"
  fi
  line+=", reuse=true, ecn=true"
  printf "%s" "$line"
}

prompt_snell_bool_value() {
  local prompt="$1"
  local default_value="$2"

  if prompt_yes_no "$prompt" "$( [[ "$default_value" == "true" ]] && printf "y" || printf "n" )"; then
    printf "true"
  else
    printf "false"
  fi
}

prompt_snell_port() {
  local default_port="$1"
  local value

  while true; do
    read -r -p "监听端口 [${default_port}]: " value
    value="${value:-$default_port}"

    if ! validate_snell_port "$value"; then
      warn "端口不合法，请输入 1-65535。"
      continue
    fi

    if declare -F is_listen_port_occupied >/dev/null 2>&1 && is_listen_port_occupied "::" "$value"; then
      if ! service_owns_listen_port "$SNELL_SERVICE_NAME" "$value"; then
        warn "端口 ${value} 已被其他进程占用，请换一个。"
        continue
      fi
    fi

    printf "%s" "$value"
    return 0
  done
}

prompt_snell_psk() {
  local default_value="$1"
  local value

  while true; do
    read -r -p "PSK 密钥 [回车自动生成/保持当前]: " value
    value="${value:-$default_value}"

    if validate_snell_psk "$value"; then
      printf "%s" "$value"
      return 0
    fi

    warn "PSK 不合法。请使用 8-128 位字母、数字或 _ . @ : = + -。"
  done
}

prompt_snell_obfs() {
  local default_value="$1"
  local value

  while true; do
    printf "\nSnell OBFS：\n"
    printf "1) off（默认，推荐）\n"
    printf "2) tls\n"
    printf "3) http\n\n"
    read -r -p "请选择 OBFS [${default_value}]: " value
    value="${value:-$default_value}"

    case "${value,,}" in
      1|off) printf "off"; return 0 ;;
      2|tls) printf "tls"; return 0 ;;
      3|http) printf "http"; return 0 ;;
      *) warn "无效 OBFS 选项。" ;;
    esac
  done
}

prompt_snell_obfs_host() {
  local default_value="$1"
  local value

  while true; do
    read -r -p "OBFS 域名 [${default_value}]: " value
    value="${value:-$default_value}"
    value="${value,,}"
    value="${value%.}"

    if validate_snell_obfs_host "$value"; then
      printf "%s" "$value"
      return 0
    fi

    warn "OBFS 域名不合法，请输入真实域名。"
  done
}

prompt_snell_version() {
  local default_value="$1"
  local value

  while true; do
    read -r -p "Snell 协议版本 4/5 [${default_value}]: " value
    value="${value:-$default_value}"

    if validate_snell_version "$value"; then
      printf "%s" "$value"
      return 0
    fi

    warn "协议版本不合法。"
  done
}

prompt_snell_dns() {
  local default_value="$1"
  local value

  while true; do
    read -r -p "DNS [${default_value}]: " value
    value="${value:-$default_value}"

    if validate_snell_dns_list "$value"; then
      printf "%s" "$value"
      return 0
    fi

    warn "DNS 格式不合法，多条记录请用英文逗号分隔。"
  done
}

show_snell_parameters_for_service() {
  local service_name="$1"
  local config_path parsed

  service_name="$(normalize_service_name "$service_name")"
  if ! snell_service_exists "$service_name"; then
    warn "未找到服务: ${service_name}"
    return 1
  fi

  config_path="$(snell_config_path_for_service "$service_name")"
  if [[ -z "$config_path" || ! -f "$config_path" ]]; then
    warn "未找到 Snell 配置文件: ${config_path}"
    return 1
  fi

  parsed="$(extract_snell_config_details "$config_path")"

  local found listen port psk obfs obfs_host ipv6 tfo dns protocol_version
  found="false"
  listen=""
  port=""
  psk=""
  obfs="off"
  obfs_host=""
  ipv6="false"
  tfo="true"
  dns=""
  protocol_version=""

  while IFS=$'\t' read -r key value; do
    case "$key" in
      found) found="$value" ;;
      listen) listen="$value" ;;
      port) port="$value" ;;
      psk) psk="$value" ;;
      obfs) obfs="$value" ;;
      obfs_host) obfs_host="$value" ;;
      ipv6) ipv6="$value" ;;
      tfo) tfo="$value" ;;
      dns) dns="$value" ;;
      version) protocol_version="$value" ;;
    esac
  done <<< "$parsed"

  if [[ "$found" != "true" ]]; then
    warn "配置中未找到 Snell Server 配置: ${config_path}"
    return 1
  fi

  local client_server
  client_server="$(default_server_identity)"
  if ! validate_client_server "$client_server"; then
    client_server="localhost"
  fi

  local service_base node_name surge_line installed_release active_state enabled_state
  service_base="${service_name%.service}"
  node_name="Snell-${service_base}"
  surge_line="$(build_snell_surge_line "$node_name" "$client_server" "$port" "$psk" "$protocol_version" "$tfo" "$obfs" "$obfs_host")"
  installed_release="$(installed_snell_release_version)"
  active_state="$(systemctl is-active "$service_name" 2>/dev/null || true)"
  enabled_state="$(systemctl is-enabled "$service_name" 2>/dev/null || true)"

  printf "\nSnell 参数：\n"
  printf "  服务名      : %s\n" "$service_name"
  printf "  状态        : active=%s | enabled=%s\n" "$active_state" "$enabled_state"
  printf "  二进制      : %s\n" "$SNELL_BINARY_PATH"
  if [[ -n "$installed_release" ]]; then
    printf "  服务端版本  : v%s\n" "$installed_release"
  fi
  printf "  服务器      : %s\n" "$client_server"
  printf "  监听        : %s\n" "$listen"
  printf "  端口        : %s\n" "$port"
  printf "  PSK         : %s\n" "$psk"
  printf "  协议版本    : %s\n" "$protocol_version"
  printf "  OBFS        : %s\n" "$obfs"
  if [[ "$obfs" != "off" ]]; then
    printf "  OBFS Host   : %s\n" "$obfs_host"
  fi
  printf "  IPv6        : %s\n" "$ipv6"
  printf "  TFO         : %s\n" "$tfo"
  printf "  DNS         : %s\n" "$dns"
  printf "  配置文件    : %s\n" "$config_path"

  printf "\nSurge 配置：\n"
  printf "  %s\n" "$surge_line"
}

show_snell_parameters_flow() {
  show_snell_parameters_for_service "$SNELL_SERVICE_NAME"
}

snell_load_existing_details() {
  local config_path="$1"
  extract_snell_config_details "$config_path"
}

snell_wizard_flow() {
  SNELL_SERVICE_NAME="$(normalize_service_name "$SNELL_SERVICE_NAME")"

  local config_path existing_parsed
  config_path="$(snell_config_path_for_service "$SNELL_SERVICE_NAME")"
  config_path="${config_path:-$SNELL_CONFIG_PATH}"

  local existing_found existing_port existing_psk existing_obfs existing_obfs_host existing_ipv6 existing_tfo existing_dns existing_version
  existing_found="false"
  existing_port=""
  existing_psk=""
  existing_obfs="$SNELL_DEFAULT_OBFS"
  existing_obfs_host=""
  existing_ipv6="$SNELL_DEFAULT_IPV6"
  existing_tfo="$SNELL_DEFAULT_TFO"
  existing_dns="$SNELL_DEFAULT_DNS"
  existing_version="$SNELL_DEFAULT_PROTOCOL_VERSION"

  if [[ -f "$config_path" ]]; then
    existing_parsed="$(snell_load_existing_details "$config_path")"
    while IFS=$'\t' read -r key value; do
      case "$key" in
        found) existing_found="$value" ;;
        port) existing_port="$value" ;;
        psk) existing_psk="$value" ;;
        obfs) existing_obfs="${value:-$SNELL_DEFAULT_OBFS}" ;;
        obfs_host) existing_obfs_host="$value" ;;
        ipv6) existing_ipv6="${value:-$SNELL_DEFAULT_IPV6}" ;;
        tfo) existing_tfo="${value:-$SNELL_DEFAULT_TFO}" ;;
        dns) existing_dns="${value:-$SNELL_DEFAULT_DNS}" ;;
        version) existing_version="${value:-$SNELL_DEFAULT_PROTOCOL_VERSION}" ;;
      esac
    done <<< "$existing_parsed"
  fi

  if [[ "$existing_found" == "true" && -x "$SNELL_BINARY_PATH" ]] && snell_service_exists "$SNELL_SERVICE_NAME"; then
    info "检测到现有 Snell Server 服务: ${SNELL_SERVICE_NAME}"
    info "当前配置文件: ${config_path}"
    if prompt_yes_no "保持现有 Snell 配置并查看参数？" "y"; then
      show_snell_parameters_for_service "$SNELL_SERVICE_NAME" || true
      return 0
    fi
  fi

  local default_port
  if validate_snell_port "$existing_port"; then
    default_port="$existing_port"
  elif declare -F pick_available_listen_port >/dev/null 2>&1; then
    default_port="$(pick_available_listen_port "$SNELL_DEFAULT_LISTEN_PORT" "$SNELL_FALLBACK_LISTEN_PORT" "::")"
  else
    default_port="$SNELL_DEFAULT_LISTEN_PORT"
  fi

  local protocol_version release_version port psk obfs obfs_host ipv6 tfo dns
  protocol_version="$(prompt_snell_version "$existing_version")"
  release_version="$(snell_release_version_for_protocol "$protocol_version")"
  port="$(prompt_snell_port "$default_port")"

  if ! validate_snell_psk "$existing_psk"; then
    existing_psk="$(generate_snell_psk)"
  fi
  psk="$(prompt_snell_psk "$existing_psk")"

  obfs="$(prompt_snell_obfs "$existing_obfs")"
  obfs_host=""
  if [[ "$obfs" != "off" ]]; then
    if ! validate_snell_obfs_host "$existing_obfs_host"; then
      existing_obfs_host="$SNELL_DEFAULT_OBFS_HOST"
    fi
    obfs_host="$(prompt_snell_obfs_host "$existing_obfs_host")"
  fi

  if ! validate_snell_bool "$existing_ipv6"; then
    existing_ipv6="$SNELL_DEFAULT_IPV6"
  fi
  ipv6="$(prompt_snell_bool_value "开启 IPv6 解析？" "$existing_ipv6")"

  if ! validate_snell_bool "$existing_tfo"; then
    existing_tfo="$SNELL_DEFAULT_TFO"
  fi
  tfo="$(prompt_snell_bool_value "开启 TCP Fast Open？" "$existing_tfo")"

  if ! validate_snell_dns_list "$existing_dns"; then
    existing_dns="$SNELL_DEFAULT_DNS"
  fi
  dns="$(prompt_snell_dns "$existing_dns")"

  if ! snell_binary_matches_release "$release_version"; then
    if ! prompt_yes_no "安装/更新 Snell Server 官方二进制到 v${release_version}？" "y"; then
      die "Snell Server 二进制未就绪，已取消配置。"
    fi
    download_install_snell_binary "$release_version"
  else
    ok "Snell Server 二进制已就绪: v${release_version}"
  fi

  local backup_path service_file service_backup_path
  backup_path="$(backup_file_if_exists "$config_path")"
  service_file="$(service_unit_file_path "$SNELL_SERVICE_NAME")"
  service_backup_path="$(backup_file_if_exists "$service_file")"

  if [[ -n "$backup_path" ]]; then
    ok "已创建 Snell 配置备份: ${backup_path}"
  fi
  if [[ -n "$service_backup_path" ]]; then
    ok "已创建 Snell 服务备份: ${service_backup_path}"
  fi

  write_snell_config "$config_path" "$port" "$psk" "$obfs" "$obfs_host" "$ipv6" "$tfo" "$dns" "$protocol_version"
  ok "已写入 Snell 配置: ${config_path}"

  write_snell_service_file "$SNELL_SERVICE_NAME" "$config_path"

  if ! apply_service_state_auto "$SNELL_SERVICE_NAME"; then
    if [[ -n "$backup_path" && -f "$backup_path" ]]; then
      cp "$backup_path" "$config_path"
      warn "服务应用失败，已回滚配置文件: ${config_path}"
    fi
    if [[ -n "$service_backup_path" && -f "$service_backup_path" ]]; then
      cp "$service_backup_path" "$service_file"
      systemctl daemon-reload
      warn "服务应用失败，已回滚服务文件: ${service_file}"
    fi
    systemctl restart "$SNELL_SERVICE_NAME" >/dev/null 2>&1 || true
    die "应用 Snell Server 服务状态失败，请检查日志。"
  fi

  show_snell_parameters_for_service "$SNELL_SERVICE_NAME" || true
}

update_snell_server_flow() {
  local config_path parsed protocol_version release_version
  config_path="$(snell_config_path_for_service "$SNELL_SERVICE_NAME")"
  protocol_version="$SNELL_DEFAULT_PROTOCOL_VERSION"

  if [[ -f "$config_path" ]]; then
    parsed="$(extract_snell_config_details "$config_path")"
    while IFS=$'\t' read -r key value; do
      case "$key" in
        version)
          if validate_snell_version "$value"; then
            protocol_version="$value"
          fi
          ;;
      esac
    done <<< "$parsed"
  fi

  protocol_version="$(prompt_snell_version "$protocol_version")"
  release_version="$(snell_release_version_for_protocol "$protocol_version")"
  download_install_snell_binary "$release_version"

  if [[ -f "$config_path" ]]; then
    set_snell_config_protocol_version "$config_path" "$protocol_version"
    ok "已同步 Snell 配置协议版本: ${protocol_version}"
  fi

  if snell_service_exists "$SNELL_SERVICE_NAME" && is_service_active "$SNELL_SERVICE_NAME"; then
    systemctl restart "$SNELL_SERVICE_NAME"
    ok "已重启 ${SNELL_SERVICE_NAME}"
  fi
}

uninstall_snell_flow() {
  warn "将停止并删除 Snell Server 服务，可选择是否删除二进制和配置。"
  if ! prompt_yes_no "确认卸载 Snell Server？" "n"; then
    return 0
  fi

  if snell_service_exists "$SNELL_SERVICE_NAME"; then
    systemctl disable --now "$SNELL_SERVICE_NAME" >/dev/null 2>&1 || true
    ok "已停止并禁用服务: ${SNELL_SERVICE_NAME}"

    local service_file
    service_file="$(service_unit_file_path "$SNELL_SERVICE_NAME")"
    if [[ -f "$service_file" ]]; then
      rm -f "$service_file"
      ok "已删除服务文件: ${service_file}"
    fi
  fi

  if prompt_yes_no "删除 Snell 二进制 ${SNELL_BINARY_PATH}？" "y"; then
    rm -f "$SNELL_BINARY_PATH"
    ok "已删除 Snell 二进制: ${SNELL_BINARY_PATH}"
  fi

  if prompt_yes_no "删除 Snell 配置目录 ${SNELL_CONFIG_DIR}？" "n"; then
    rm -rf "$SNELL_CONFIG_DIR"
    ok "已删除 Snell 配置目录: ${SNELL_CONFIG_DIR}"
  fi

  systemctl daemon-reload
  systemctl reset-failed >/dev/null 2>&1 || true
}
