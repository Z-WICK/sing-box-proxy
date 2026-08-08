#!/usr/bin/env bash

: "${SNELL_SERVICE_NAME:=snell-server.service}"
: "${SNELL_INSTALL_DIR:=/usr/local/bin}"
: "${SNELL_BINARY_PATH:=${SNELL_INSTALL_DIR}/snell-server}"
: "${SNELL_CONFIG_DIR:=/etc/snell}"
: "${SNELL_CONFIG_PATH:=${SNELL_CONFIG_DIR}/config.conf}"
: "${SNELL_VERSION_FILE:=${SNELL_CONFIG_DIR}/ver.txt}"
: "${SNELL_V4_RELEASE_VERSION:=4.1.1}"
: "${SNELL_V5_RELEASE_VERSION:=5.0.1}"
: "${SNELL_V6_RELEASE_VERSION:=6.0.0rc}"
: "${SNELL_RELEASE_NOTES_URL:=https://kb.nssurge.com/surge-knowledge-base/release-notes/snell.md}"
: "${SNELL_FETCH_LATEST_RELEASES:=true}"
: "${SNELL_DEFAULT_PROTOCOL_VERSION:=6}"
: "${SNELL_DEFAULT_LISTEN_PORT:=2345}"
: "${SNELL_FALLBACK_LISTEN_PORT:=2346}"
: "${SNELL_PUBLIC_LISTEN_PORT:=}"
: "${SNELL_DEFAULT_IPV6:=false}"
: "${SNELL_DEFAULT_OBFS:=off}"
: "${SNELL_DEFAULT_TFO:=true}"
: "${SNELL_DEFAULT_DNS:=1.1.1.1, 8.8.8.8, 2001:4860:4860::8888}"
: "${SNELL_DEFAULT_OBFS_HOST:=icloud.com}"
: "${SNELL_DEFAULT_MODE:=default}"
: "${SNELL_DEFAULT_DNS_IP_PREFERENCE:=default}"
: "${SNELL_TFO_SYSCTL_PATH:=/etc/sysctl.d/99-snell-tfo.conf}"

register_snell_menu_items() {
  register_protocol_menu_item "Snell" "配置向导" "snell_wizard_flow"
  register_protocol_menu_item "Snell" "查看参数" "show_snell_parameters_flow"
  register_protocol_menu_item "Snell" "升级到 Snell 6" "upgrade_snell_to_v6_flow"
  register_protocol_menu_item "Snell" "切换/更新服务端版本" "update_snell_server_flow"
  register_protocol_menu_item "Snell" "卸载 Snell Server" "uninstall_snell_flow"
}

resolve_snell_client_port() {
  local internal_port="$1"
  resolve_public_listen_port "$internal_port" "${SNELL_PUBLIC_LISTEN_PORT:-}" "${PUBLIC_HAPROXY_CONFIG_PATH:-/etc/haproxy/haproxy.cfg}"
}

validate_snell_port() {
  local port_value="$1"
  [[ "$port_value" =~ ^[0-9]+$ ]] || return 1
  (( port_value >= 1 && port_value <= 65535 ))
}

validate_snell_psk() {
  local value="$1"
  local protocol_version="${2:-}"
  local min_length=8
  local max_length=128

  if [[ "$protocol_version" == "6" ]]; then
    min_length=16
    max_length=255
  fi

  [[ "$value" =~ ^[A-Za-z0-9_.@:=+-]+$ ]] || return 1
  (( ${#value} >= min_length && ${#value} <= max_length ))
}

validate_snell_obfs() {
  local value="$1"
  [[ "$value" == "off" || "$value" == "tls" || "$value" == "http" ]]
}

validate_snell_version() {
  local value="$1"
  [[ "$value" == "4" || "$value" == "5" || "$value" == "6" ]]
}

validate_snell_mode() {
  local value="$1"
  [[ "$value" == "default" || "$value" == "unshaped" || "$value" == "unsafe-raw" ]]
}

validate_snell_dns_ip_preference() {
  local value="$1"
  case "$value" in
    default|prefer-ipv4|prefer-ipv6|ipv4-only|ipv6-only) return 0 ;;
    *) return 1 ;;
  esac
}

validate_snell_bool() {
  local value="$1"
  [[ "$value" == "true" || "$value" == "false" ]]
}

apply_snell_tfo_kernel_setting() {
  local tfo="$1"

  [[ "$tfo" == "true" ]] || return 0

  if (( EUID != 0 )); then
    warn "当前不是 root，无法写入 TCP Fast Open 内核参数；继续保留 Snell 配置中的 tfo=true。"
    return 0
  fi

  if ! command -v sysctl >/dev/null 2>&1; then
    warn "未找到 sysctl，无法启用 TCP Fast Open 内核参数；继续保留 Snell 配置中的 tfo=true。"
    return 0
  fi

  if ! sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1; then
    warn "内核不接受 net.ipv4.tcp_fastopen=3；继续保留 Snell 配置中的 tfo=true。"
    return 0
  fi

  local sysctl_dir
  sysctl_dir="$(dirname "$SNELL_TFO_SYSCTL_PATH")"
  if [[ ! -d "$sysctl_dir" ]]; then
    warn "未找到 sysctl 持久化目录: ${sysctl_dir}；本次运行已启用 TCP Fast Open。"
    return 0
  fi

  if [[ -e "$SNELL_TFO_SYSCTL_PATH" ]] && ! grep -Fq "managed by sing-box-proxy" "$SNELL_TFO_SYSCTL_PATH"; then
    warn "已存在非本脚本管理的 sysctl 文件: ${SNELL_TFO_SYSCTL_PATH}；仅应用本次运行的 TCP Fast Open 设置。"
    return 0
  fi

  {
    printf "# managed by sing-box-proxy\n"
    printf "net.ipv4.tcp_fastopen = 3\n"
  } > "$SNELL_TFO_SYSCTL_PATH"
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
  local fallback_version latest_version

  case "$protocol_version" in
    4) fallback_version="$SNELL_V4_RELEASE_VERSION" ;;
    5) fallback_version="$SNELL_V5_RELEASE_VERSION" ;;
    6) fallback_version="$SNELL_V6_RELEASE_VERSION" ;;
    *) die "不支持的 Snell 协议版本: ${protocol_version}" ;;
  esac

  if [[ "$SNELL_FETCH_LATEST_RELEASES" == "true" ]]; then
    latest_version="$(fetch_latest_snell_release_version "$protocol_version" || true)"
    if [[ -n "$latest_version" ]]; then
      printf "%s" "$latest_version"
      return 0
    fi
    warn "无法从官方发布页获取 Snell ${protocol_version} 最新版本，使用内置版本 v${fallback_version}。" >&2
  fi

  printf "%s" "$fallback_version"
}

extract_latest_snell_release_version() {
  local protocol_version="$1"
  local line release_version

  validate_snell_version "$protocol_version" || return 1
  while IFS= read -r line; do
    if [[ "$line" =~ snell-server-v([0-9]+\.[0-9]+\.[0-9]+([[:alpha:]]+[0-9]*)?)-linux-(amd64|i386|aarch64|armv7l)\.zip ]]; then
      release_version="${BASH_REMATCH[1]}"
      if [[ "$(snell_protocol_version_from_release "$release_version")" == "$protocol_version" ]]; then
        printf "%s" "$release_version"
        return 0
      fi
    fi
  done

  return 1
}

fetch_latest_snell_release_version() {
  local protocol_version="$1"
  local release_notes

  release_notes="$(curl -fsSL --retry 2 --connect-timeout 10 --max-time 20 "$SNELL_RELEASE_NOTES_URL" 2>/dev/null)" || return 1
  extract_latest_snell_release_version "$protocol_version" <<< "$release_notes"
}

snell_protocol_version_from_release() {
  local release_version
  release_version="$(normalize_snell_release_version "$1")"

  case "$release_version" in
    4.*) printf "4" ;;
    5.*) printf "5" ;;
    6.*) printf "6" ;;
    *) printf "" ;;
  esac
}

validate_snell_arch_for_release() {
  local release_version="$1"
  local arch="$2"
  local protocol_version

  protocol_version="$(snell_protocol_version_from_release "$release_version")"
  if [[ "$protocol_version" == "6" && "$arch" == "armv7l" ]]; then
    return 1
  fi
  return 0
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
  local output

  if [[ -f "$SNELL_VERSION_FILE" ]]; then
    normalize_snell_release_version "$(head -n1 "$SNELL_VERSION_FILE" | tr -d '[:space:]')"
    return 0
  fi

  if [[ -x "$SNELL_BINARY_PATH" ]]; then
    output="$("$SNELL_BINARY_PATH" -v 2>&1 || true)"
    if [[ "$output" =~ snell-server[[:space:]]+v([0-9]+\.[0-9]+\.[0-9]+([[:alpha:]]+[0-9]*)?) ]]; then
      normalize_snell_release_version "${BASH_REMATCH[1]}"
      return 0
    fi
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
  SNELL_LAST_BINARY_BACKUP=""
  if [[ ! -f "$SNELL_BINARY_PATH" ]]; then
    return 0
  fi

  local backup_path
  backup_path="${SNELL_BINARY_PATH}.bak-$(date +%Y%m%d%H%M%S)"
  cp "$SNELL_BINARY_PATH" "$backup_path"
  SNELL_LAST_BINARY_BACKUP="$backup_path"
  ok "已创建 Snell 二进制备份: ${backup_path}"
}

download_install_snell_binary() {
  local release_version="$1"
  local arch url temp_dir archive_path extracted_path

  release_version="$(normalize_snell_release_version "$release_version")"
  arch="$(detect_snell_arch)"
  if ! validate_snell_arch_for_release "$release_version" "$arch"; then
    die "Snell 6 官方暂不提供 armv7l 架构构建，请继续使用 Snell 4/5。"
  fi
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
  local mode="${10:-$SNELL_DEFAULT_MODE}"
  local dns_ip_preference="${11:-$SNELL_DEFAULT_DNS_IP_PREFERENCE}"
  local egress_interface="${12:-}"
  local custom_configs

  mkdir -p "$(dirname "$config_path")"
  custom_configs="$(extract_snell_custom_config_lines "$config_path" || true)"

  {
    printf "[snell-server]\n"
    printf "listen = ::0:%s\n" "$port"
    printf "psk = %s\n" "$psk"
    if [[ "$protocol_version" == "6" ]]; then
      printf "mode = %s\n" "$mode"
      printf "dns-ip-preference = %s\n" "$dns_ip_preference"
    else
      printf "ipv6 = %s\n" "$ipv6"
      printf "obfs = %s\n" "$obfs"
      if [[ "$obfs" != "off" ]]; then
        printf "obfs-host = %s\n" "$obfs_host"
      fi
    fi
    if [[ -n "$egress_interface" ]]; then
      printf "egress-interface = %s\n" "$egress_interface"
    fi
    printf "tfo = %s\n" "$tfo"
    printf "dns = %s\n" "$dns"
    if [[ "$protocol_version" != "6" ]]; then
      printf "version = %s\n" "$protocol_version"
    fi
  } > "$config_path"

  if [[ -n "$custom_configs" ]]; then
    {
      printf "\n# Preserved custom config\n"
      printf "%s\n" "$custom_configs"
    } >> "$config_path"
  fi

  chmod 600 "$config_path"
}

extract_snell_custom_config_lines() {
  local config_path="$1"

  [[ -f "$config_path" ]] || return 0

  SNELL_CONFIG_PATH_TO_PARSE="$config_path" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ['SNELL_CONFIG_PATH_TO_PARSE'])
known_keys = {
    'listen',
    'ipv6',
    'psk',
    'obfs',
    'obfs-host',
    'tfo',
    'dns',
    'dns-ip-preference',
    'mode',
    'version',
    'egress-interface',
}
section = 'snell-server'

for raw_line in path.read_text(encoding='utf-8').splitlines():
    line = raw_line.strip()
    if line.startswith('['):
        section = line[1:-1].strip()
        continue
    if section != 'snell-server' or not line or line.startswith('#') or '=' not in line:
        continue
    key = line.split('=', 1)[0].strip()
    if key not in known_keys:
        print(raw_line.rstrip())
PY
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
emit('mode', data.get('mode', ''))
emit('dns_ip_preference', data.get('dns-ip-preference', ''))
emit('egress_interface', data.get('egress-interface', ''))
PY
}

snell_dns_preference_from_ipv6() {
  local ipv6="$1"
  if [[ "$ipv6" == "true" ]]; then
    printf "default"
  else
    printf "ipv4-only"
  fi
}

migrate_snell_config_to_protocol() {
  local config_path="$1"
  local protocol_version="$2"
  local psk_override="${3:-}"
  local parsed

  validate_snell_version "$protocol_version" || return 1
  [[ -f "$config_path" ]] || return 1
  parsed="$(extract_snell_config_details "$config_path")"

  local found port psk obfs obfs_host ipv6 tfo dns mode dns_ip_preference egress_interface
  found="false"
  port=""
  psk=""
  obfs="$SNELL_DEFAULT_OBFS"
  obfs_host=""
  ipv6="$SNELL_DEFAULT_IPV6"
  tfo="$SNELL_DEFAULT_TFO"
  dns="$SNELL_DEFAULT_DNS"
  mode="$SNELL_DEFAULT_MODE"
  dns_ip_preference=""
  egress_interface=""

  while IFS=$'\t' read -r key value; do
    case "$key" in
      found) found="$value" ;;
      port) port="$value" ;;
      psk) psk="$value" ;;
      obfs) obfs="${value:-$SNELL_DEFAULT_OBFS}" ;;
      obfs_host) obfs_host="$value" ;;
      ipv6) ipv6="${value:-$SNELL_DEFAULT_IPV6}" ;;
      tfo) tfo="${value:-$SNELL_DEFAULT_TFO}" ;;
      dns) dns="${value:-$SNELL_DEFAULT_DNS}" ;;
      mode) mode="${value:-$SNELL_DEFAULT_MODE}" ;;
      dns_ip_preference) dns_ip_preference="$value" ;;
      egress_interface) egress_interface="$value" ;;
    esac
  done <<< "$parsed"

  [[ "$found" == "true" ]] || return 1
  validate_snell_port "$port" || return 1
  [[ -n "$psk_override" ]] && psk="$psk_override"
  validate_snell_psk "$psk" "$protocol_version" || return 1
  validate_snell_obfs "$obfs" || obfs="$SNELL_DEFAULT_OBFS"
  validate_snell_bool "$ipv6" || ipv6="$SNELL_DEFAULT_IPV6"
  validate_snell_bool "$tfo" || tfo="$SNELL_DEFAULT_TFO"
  validate_snell_dns_list "$dns" || dns="$SNELL_DEFAULT_DNS"
  validate_snell_mode "$mode" || mode="$SNELL_DEFAULT_MODE"
  if ! validate_snell_dns_ip_preference "$dns_ip_preference"; then
    dns_ip_preference="$(snell_dns_preference_from_ipv6 "$ipv6")"
  fi

  write_snell_config \
    "$config_path" "$port" "$psk" "$obfs" "$obfs_host" \
    "$ipv6" "$tfo" "$dns" "$protocol_version" "$mode" "$dns_ip_preference" "$egress_interface"
}

set_snell_config_protocol_version() {
  local config_path="$1"
  local protocol_version="$2"

  migrate_snell_config_to_protocol "$config_path" "$protocol_version"
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
  local mode="${9:-$SNELL_DEFAULT_MODE}"

  server="$(snell_format_host_for_client "$server")"

  local line
  line="${node_name} = snell, ${server}, ${port}, psk=${psk}, version=${protocol_version}, tfo=${tfo}"
  if [[ "$protocol_version" == "6" ]]; then
    line+=", mode=${mode}"
  elif [[ "$obfs" != "off" && -n "$obfs_host" ]]; then
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
  local protocol_version="${2:-}"
  local value
  local length_hint="8-128"

  if [[ "$protocol_version" == "6" ]]; then
    length_hint="16-255"
  fi

  while true; do
    read -r -p "PSK 密钥 [回车自动生成/保持当前]: " value
    value="${value:-$default_value}"

    if validate_snell_psk "$value" "$protocol_version"; then
      printf "%s" "$value"
      return 0
    fi

    warn "PSK 不合法。请使用 ${length_hint} 位字母、数字或 _ . @ : = + -。"
  done
}

prompt_snell_obfs() {
  local default_value="$1"
  local value

  while true; do
    printf "\nSnell OBFS：\n" >&2
    printf "1) off（默认，推荐）\n" >&2
    printf "2) tls\n" >&2
    printf "3) http\n\n" >&2
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
    read -r -p "Snell 协议版本 4/5/6 [${default_value}]: " value
    value="${value:-$default_value}"

    if validate_snell_version "$value"; then
      printf "%s" "$value"
      return 0
    fi

    warn "协议版本不合法。"
  done
}

prompt_snell_mode() {
  local default_value="$1"
  local value

  while true; do
    printf "\nSnell 6 模式：\n" >&2
    printf "1) default（混淆 + AES，推荐）\n" >&2
    printf "2) unshaped（仅 AES，吞吐更高）\n" >&2
    printf "3) unsafe-raw（明文，仅限安全内网）\n\n" >&2
    read -r -p "请选择模式 [${default_value}]: " value
    value="${value:-$default_value}"

    case "${value,,}" in
      1|default) printf "default"; return 0 ;;
      2|unshaped) printf "unshaped"; return 0 ;;
      3|unsafe-raw) printf "unsafe-raw"; return 0 ;;
      *) warn "无效 Snell 6 模式。" ;;
    esac
  done
}

prompt_snell_dns_ip_preference() {
  local default_value="$1"
  local value

  while true; do
    printf "\nSnell 6 DNS 地址族偏好：\n" >&2
    printf "1) default\n" >&2
    printf "2) prefer-ipv4\n" >&2
    printf "3) prefer-ipv6\n" >&2
    printf "4) ipv4-only\n" >&2
    printf "5) ipv6-only\n\n" >&2
    read -r -p "请选择 DNS 地址族偏好 [${default_value}]: " value
    value="${value:-$default_value}"

    case "${value,,}" in
      1|default) printf "default"; return 0 ;;
      2|prefer-ipv4) printf "prefer-ipv4"; return 0 ;;
      3|prefer-ipv6) printf "prefer-ipv6"; return 0 ;;
      4|ipv4-only) printf "ipv4-only"; return 0 ;;
      5|ipv6-only) printf "ipv6-only"; return 0 ;;
      *) warn "无效 DNS 地址族偏好。" ;;
    esac
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

  local found listen port psk obfs obfs_host ipv6 tfo dns protocol_version mode dns_ip_preference egress_interface
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
  mode="$SNELL_DEFAULT_MODE"
  dns_ip_preference=""
  egress_interface=""

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
      mode) mode="${value:-$SNELL_DEFAULT_MODE}" ;;
      dns_ip_preference) dns_ip_preference="$value" ;;
      egress_interface) egress_interface="$value" ;;
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

  local service_base node_name client_port surge_line installed_release active_state enabled_state
  installed_release="$(installed_snell_release_version)"
  if ! validate_snell_version "$protocol_version"; then
    protocol_version="$(snell_protocol_version_from_release "$installed_release")"
  fi
  protocol_version="${protocol_version:-$SNELL_DEFAULT_PROTOCOL_VERSION}"
  validate_snell_mode "$mode" || mode="$SNELL_DEFAULT_MODE"
  if ! validate_snell_dns_ip_preference "$dns_ip_preference"; then
    dns_ip_preference="$(snell_dns_preference_from_ipv6 "$ipv6")"
  fi

  service_base="${service_name%.service}"
  node_name="Snell-${service_base}"
  client_port="$(resolve_snell_client_port "$port")"
  surge_line="$(build_snell_surge_line "$node_name" "$client_server" "$client_port" "$psk" "$protocol_version" "$tfo" "$obfs" "$obfs_host" "$mode")"
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
  printf "  端口        : %s\n" "$client_port"
  if [[ "$client_port" != "$port" ]]; then
    printf "  内部监听    : %s:%s\n" "${listen:-*}" "$port"
  fi
  printf "  PSK         : %s\n" "$psk"
  printf "  协议版本    : %s\n" "$protocol_version"
  if [[ "$protocol_version" == "6" ]]; then
    printf "  模式        : %s\n" "$mode"
    printf "  DNS IP 偏好 : %s\n" "$dns_ip_preference"
  else
    printf "  OBFS        : %s\n" "$obfs"
    if [[ "$obfs" != "off" ]]; then
      printf "  OBFS Host   : %s\n" "$obfs_host"
    fi
    printf "  IPv6        : %s\n" "$ipv6"
  fi
  printf "  TFO         : %s\n" "$tfo"
  printf "  DNS         : %s\n" "$dns"
  if [[ -n "$egress_interface" ]]; then
    printf "  出口网卡    : %s\n" "$egress_interface"
  fi
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

  local existing_found existing_port existing_psk existing_obfs existing_obfs_host existing_ipv6 existing_tfo existing_dns existing_version existing_mode existing_dns_ip_preference existing_egress_interface
  existing_found="false"
  existing_port=""
  existing_psk=""
  existing_obfs="$SNELL_DEFAULT_OBFS"
  existing_obfs_host=""
  existing_ipv6="$SNELL_DEFAULT_IPV6"
  existing_tfo="$SNELL_DEFAULT_TFO"
  existing_dns="$SNELL_DEFAULT_DNS"
  existing_version=""
  existing_mode="$SNELL_DEFAULT_MODE"
  existing_dns_ip_preference=""
  existing_egress_interface=""

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
        version) existing_version="$value" ;;
        mode) existing_mode="${value:-$SNELL_DEFAULT_MODE}" ;;
        dns_ip_preference) existing_dns_ip_preference="$value" ;;
        egress_interface) existing_egress_interface="$value" ;;
      esac
    done <<< "$existing_parsed"
  fi

  if ! validate_snell_version "$existing_version"; then
    existing_version="$(snell_protocol_version_from_release "$(installed_snell_release_version)")"
  fi
  existing_version="${existing_version:-$SNELL_DEFAULT_PROTOCOL_VERSION}"

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

  local protocol_version release_version port psk obfs obfs_host ipv6 tfo dns mode dns_ip_preference
  protocol_version="$(prompt_snell_version "$existing_version")"
  release_version="$(snell_release_version_for_protocol "$protocol_version")"
  port="$(prompt_snell_port "$default_port")"

  if ! validate_snell_psk "$existing_psk" "$protocol_version"; then
    existing_psk="$(generate_snell_psk)"
  fi
  psk="$(prompt_snell_psk "$existing_psk" "$protocol_version")"

  obfs="$SNELL_DEFAULT_OBFS"
  obfs_host=""
  mode="$SNELL_DEFAULT_MODE"
  dns_ip_preference="$SNELL_DEFAULT_DNS_IP_PREFERENCE"
  if [[ "$protocol_version" == "6" ]]; then
    validate_snell_mode "$existing_mode" || existing_mode="$SNELL_DEFAULT_MODE"
    mode="$(prompt_snell_mode "$existing_mode")"
    if ! validate_snell_dns_ip_preference "$existing_dns_ip_preference"; then
      existing_dns_ip_preference="$(snell_dns_preference_from_ipv6 "$existing_ipv6")"
    fi
    dns_ip_preference="$(prompt_snell_dns_ip_preference "$existing_dns_ip_preference")"
    ipv6="$SNELL_DEFAULT_IPV6"
  else
    obfs="$(prompt_snell_obfs "$existing_obfs")"
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
    dns_ip_preference="$(snell_dns_preference_from_ipv6 "$ipv6")"
  fi

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

  write_snell_config "$config_path" "$port" "$psk" "$obfs" "$obfs_host" "$ipv6" "$tfo" "$dns" "$protocol_version" "$mode" "$dns_ip_preference" "$existing_egress_interface"
  apply_snell_tfo_kernel_setting "$tfo"
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

restore_snell_upgrade() {
  local config_path="$1"
  local config_backup="$2"
  local version_backup="$3"
  local version_file_existed="$4"
  local binary_backup="$5"
  local binary_file_existed="$6"

  if [[ -n "$config_backup" && -f "$config_backup" ]]; then
    cp "$config_backup" "$config_path"
    warn "已回滚 Snell 配置: ${config_path}"
  fi
  if [[ -n "$binary_backup" && -f "$binary_backup" ]]; then
    cp "$binary_backup" "$SNELL_BINARY_PATH"
    chmod 0755 "$SNELL_BINARY_PATH"
    warn "已回滚 Snell 二进制: ${SNELL_BINARY_PATH}"
  elif [[ "$binary_file_existed" != "true" ]]; then
    rm -f "$SNELL_BINARY_PATH"
  fi
  if [[ -n "$version_backup" && -f "$version_backup" ]]; then
    cp "$version_backup" "$SNELL_VERSION_FILE"
  elif [[ "$version_file_existed" != "true" ]]; then
    rm -f "$SNELL_VERSION_FILE"
  fi
}

install_snell_protocol_version() {
  local protocol_version="$1"
  local force_download="${2:-false}"
  local config_path release_version config_backup version_backup version_file_existed binary_file_existed
  local binary_changed service_was_active migration_psk parsed existing_psk tfo_value

  validate_snell_version "$protocol_version" || die "不支持的 Snell 协议版本: ${protocol_version}"
  release_version="$(snell_release_version_for_protocol "$protocol_version")"
  config_path="$(snell_config_path_for_service "$SNELL_SERVICE_NAME")"
  config_path="${config_path:-$SNELL_CONFIG_PATH}"
  config_backup="$(backup_file_if_exists "$config_path")"
  version_backup="$(backup_file_if_exists "$SNELL_VERSION_FILE")"
  version_file_existed="false"
  [[ -f "$SNELL_VERSION_FILE" ]] && version_file_existed="true"
  binary_file_existed="false"
  [[ -f "$SNELL_BINARY_PATH" ]] && binary_file_existed="true"
  binary_changed="false"
  service_was_active="false"
  migration_psk=""
  existing_psk=""
  tfo_value="$SNELL_DEFAULT_TFO"
  SNELL_LAST_BINARY_BACKUP=""

  if snell_service_exists "$SNELL_SERVICE_NAME" && is_service_active "$SNELL_SERVICE_NAME"; then
    service_was_active="true"
  fi

  if [[ "$force_download" == "true" ]] || ! snell_binary_matches_release "$release_version"; then
    download_install_snell_binary "$release_version"
    binary_changed="true"
  else
    ok "Snell Server 已是目标版本: v${release_version}"
  fi

  if [[ -f "$config_path" ]]; then
    parsed="$(extract_snell_config_details "$config_path")"
    while IFS=$'\t' read -r key value; do
      case "$key" in
        psk) existing_psk="$value" ;;
        tfo) tfo_value="${value:-$SNELL_DEFAULT_TFO}" ;;
      esac
    done <<< "$parsed"

    if ! validate_snell_psk "$existing_psk" "$protocol_version"; then
      if [[ "$protocol_version" == "6" ]]; then
        warn "现有 PSK 不符合 Snell 6 的 16-255 位要求，将提示输入新 PSK。"
        migration_psk="$(prompt_snell_psk "$(generate_snell_psk)" "$protocol_version")"
      fi
    fi

    if ! migrate_snell_config_to_protocol "$config_path" "$protocol_version" "$migration_psk"; then
      restore_snell_upgrade "$config_path" "$config_backup" "$version_backup" "$version_file_existed" "$SNELL_LAST_BINARY_BACKUP" "$binary_file_existed"
      die "Snell 配置迁移失败，已恢复升级前状态。"
    fi
    if [[ -n "$migration_psk" ]]; then
      ok "已迁移 Snell 配置到协议版本 ${protocol_version}，端口保持不变，PSK 已按协议要求更新。"
    else
      ok "已迁移 Snell 配置到协议版本 ${protocol_version}，端口与 PSK 保持不变。"
    fi
    apply_snell_tfo_kernel_setting "$tfo_value"
  fi

  if [[ "$service_was_active" == "true" ]]; then
    if ! systemctl restart "$SNELL_SERVICE_NAME"; then
      restore_snell_upgrade "$config_path" "$config_backup" "$version_backup" "$version_file_existed" "$SNELL_LAST_BINARY_BACKUP" "$binary_file_existed"
      systemctl restart "$SNELL_SERVICE_NAME" >/dev/null 2>&1 || true
      die "Snell 升级后启动失败，已回滚二进制和配置。"
    fi
    ok "已重启 ${SNELL_SERVICE_NAME}"
  elif [[ "$binary_changed" == "true" ]]; then
    info "Snell 服务当前未运行，已完成文件升级但未自动启动服务。"
  fi

  ok "Snell Server 已切换到 v${release_version}（协议版本 ${protocol_version}）。"
  if [[ "$protocol_version" == "6" && "$release_version" =~ [[:alpha:]] ]]; then
    info "Snell 6 当前为预发布版本；Surge 客户端需使用 version=6，并与服务端保持相同 mode。"
  fi
}

upgrade_snell_to_v6_flow() {
  local release_version
  release_version="$(snell_release_version_for_protocol 6)"

  warn "升级会保留现有监听端口、PSK、DNS 和 TFO，并迁移 v4/v5 配置。"
  if ! prompt_yes_no "确认升级到 Snell v${release_version}？" "y"; then
    return 0
  fi

  install_snell_protocol_version "6" "false"
  show_snell_parameters_for_service "$SNELL_SERVICE_NAME" || true
}

update_snell_server_flow() {
  local config_path parsed protocol_version installed_release
  config_path="$(snell_config_path_for_service "$SNELL_SERVICE_NAME")"
  protocol_version=""

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

  installed_release="$(installed_snell_release_version)"
  if ! validate_snell_version "$protocol_version"; then
    protocol_version="$(snell_protocol_version_from_release "$installed_release")"
  fi
  protocol_version="${protocol_version:-$SNELL_DEFAULT_PROTOCOL_VERSION}"
  protocol_version="$(prompt_snell_version "$protocol_version")"

  install_snell_protocol_version "$protocol_version" "true"
  show_snell_parameters_for_service "$SNELL_SERVICE_NAME" || true
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
