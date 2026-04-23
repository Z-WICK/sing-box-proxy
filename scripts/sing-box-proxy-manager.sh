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
VLESS_REALITY_STANDARD_SERVICE_NAME="sing-box-vless-reality.service"
VLESS_REALITY_STANDARD_CONFIG_PATH="/etc/sing-box/vless-reality.json"
VLESS_REALITY_STANDARD_LISTEN_ADDR="::"
VLESS_REALITY_STANDARD_LISTEN_PORT="443"
VLESS_REALITY_FALLBACK_LISTEN_PORT="8443"
VLESS_REALITY_DEFAULT_FLOW="xtls-rprx-vision"
VLESS_REALITY_METADATA_DIR="${DATA_DIR}/vless-reality-meta"
CLIENT_IMPORT_DIR="${DATA_DIR}/client-import"
CLIENT_IMPORT_PUBLISH_DIR="${DATA_DIR}/client-import-publish"
CLIENT_IMPORT_HTTP_SERVICE="sing-box-import-http.service"
CLIENT_IMPORT_HTTP_SCRIPT="${TOOLS_DIR}/import-http-server.py"
CLIENT_IMPORT_HTTP_PORT="18080"
SCRIPT_SOURCE_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd -- "$(dirname "${SCRIPT_SOURCE_PATH}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

COLOR_RESET='\033[0m'
COLOR_RED='\033[31m'
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_BLUE='\033[34m'

CURRENT_SERVICE_NAME=""
ANYTLS_MODULE_LOADED="false"
VLESS_REALITY_MODULE_LOADED="false"
PROTOCOL_MENU_LABELS=()
PROTOCOL_MENU_HANDLERS=()

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

register_protocol_menu_item() {
  local label="$1"
  local handler="$2"
  PROTOCOL_MENU_LABELS+=("$label")
  PROTOCOL_MENU_HANDLERS+=("$handler")
}

load_protocol_module() {
  local module_file="$1"
  local loaded_var="$2"
  local register_func="$3"
  local module_label="$4"
  local module_path
  module_path="${MODULES_DIR}/${module_file}"

  printf -v "$loaded_var" "false"
  if [[ ! -f "$module_path" ]]; then
    warn "未找到模块: ${module_path}，${module_label} 功能已禁用。"
    return 1
  fi

  # shellcheck source=/dev/null
  source "$module_path"
  printf -v "$loaded_var" "true"

  if declare -F "$register_func" >/dev/null 2>&1; then
    "$register_func"
  fi
  return 0
}

load_protocol_modules() {
  PROTOCOL_MENU_LABELS=()
  PROTOCOL_MENU_HANDLERS=()
  load_protocol_module "anytls.sh" "ANYTLS_MODULE_LOADED" "register_anytls_menu_items" "AnyTLS" || true
  load_protocol_module "vless_reality.sh" "VLESS_REALITY_MODULE_LOADED" "register_vless_reality_menu_items" "VLESS Reality" || true
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

service_owns_listen_port() {
  local service_name="$1"
  local listen_port="$2"

  SERVICE_NAME="$service_name" LISTEN_PORT="$listen_port" python3 - <<'PY'
import glob
import os
import pathlib
import re

service_name = os.environ['SERVICE_NAME']
listen_port = int(os.environ['LISTEN_PORT'])

status_path = pathlib.Path('/run/systemd/system')
if not status_path.exists():
    raise SystemExit(1)

try:
    import subprocess
    main_pid_text = subprocess.check_output(
        ['systemctl', 'show', '-p', 'MainPID', '--value', service_name],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()
except Exception:
    raise SystemExit(1)

if not main_pid_text.isdigit():
    raise SystemExit(1)

main_pid = int(main_pid_text)
if main_pid <= 0:
    raise SystemExit(1)

socket_inodes = set()
for fd_path in glob.glob(f'/proc/{main_pid}/fd/*'):
    try:
        target = os.readlink(fd_path)
    except OSError:
        continue
    match = re.fullmatch(r'socket:\[(\d+)\]', target)
    if match:
        socket_inodes.add(match.group(1))

if not socket_inodes:
    raise SystemExit(1)

def owns_listener(table_path: str) -> bool:
    try:
        with open(table_path, 'r', encoding='utf-8') as fp:
            lines = fp.readlines()[1:]
    except OSError:
        return False

    for line in lines:
        parts = line.split()
        if len(parts) < 10:
            continue
        local_address = parts[1]
        state = parts[3]
        inode = parts[9]
        if state != '0A':
            continue
        try:
            port = int(local_address.split(':', 1)[1], 16)
        except Exception:
            continue
        if port == listen_port and inode in socket_inodes:
            return True
    return False

if owns_listener('/proc/net/tcp') or owns_listener('/proc/net/tcp6'):
    raise SystemExit(0)

raise SystemExit(1)
PY
}

pick_existing_anytls_listen_port() {
  local service_name="$1"
  local preferred_port="${2:-$ANYTLS_STANDARD_LISTEN_PORT}"
  local fallback_port="${3:-$ANYTLS_FALLBACK_LISTEN_PORT}"
  local listen_addr="${4:-$ANYTLS_STANDARD_LISTEN_ADDR}"

  if ! is_listen_port_occupied "$listen_addr" "$preferred_port"; then
    printf "%s" "$preferred_port"
    return 0
  fi

  if service_owns_listen_port "$service_name" "$preferred_port"; then
    printf "%s" "$preferred_port"
    return 0
  fi

  warn "检测到 ${listen_addr}:${preferred_port} 已被其他进程占用，默认改用 ${fallback_port}"

  if ! is_listen_port_occupied "$listen_addr" "$fallback_port"; then
    printf "%s" "$fallback_port"
    return 0
  fi

  if service_owns_listen_port "$service_name" "$fallback_port"; then
    printf "%s" "$fallback_port"
    return 0
  fi

  die "检测到 ${preferred_port} 和 ${fallback_port} 都不可用，请先处理端口冲突。"
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

service_unit_file_path() {
  local service_name
  service_name="$(normalize_service_name "$1")"
  printf "/etc/systemd/system/%s" "$service_name"
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

  if prompt_yes_no "删除 AnyTLS/VLESS 元数据和客户端导入文件？" "y"; then
    rm -rf "$ANYTLS_METADATA_DIR" "$VLESS_REALITY_METADATA_DIR" "$CLIENT_IMPORT_DIR" "$CLIENT_IMPORT_PUBLISH_DIR"
    ok "已删除 ${ANYTLS_METADATA_DIR}、${VLESS_REALITY_METADATA_DIR}、${CLIENT_IMPORT_DIR} 和 ${CLIENT_IMPORT_PUBLISH_DIR}"
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
        if [[ "$ANYTLS_MODULE_LOADED" != "true" ]]; then
          warn "AnyTLS 模块缺失，无法执行该功能。"
          return 0
        fi
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

proxy_menu_flow() {
  while true; do
    local i handler

    printf "\nProxy 菜单：\n"

    if (( ${#PROTOCOL_MENU_LABELS[@]} == 0 )); then
      printf "  （当前没有可用协议模块）\n"
    else
      for i in "${!PROTOCOL_MENU_LABELS[@]}"; do
        printf "%d) %s\n" "$((i + 1))" "${PROTOCOL_MENU_LABELS[$i]}"
      done
    fi

    printf "0) 返回\n\n"
    read -r -p "请选择 Proxy 操作: " choice

    if [[ "$choice" == "0" ]]; then
      return 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      warn "无效选项。"
      continue
    fi

    if (( choice < 1 || choice > ${#PROTOCOL_MENU_HANDLERS[@]} )); then
      warn "无效选项。"
      continue
    fi

    handler="${PROTOCOL_MENU_HANDLERS[$((choice - 1))]}"
    if ! declare -F "$handler" >/dev/null 2>&1; then
      warn "菜单处理函数不存在: ${handler}"
      continue
    fi

    "$handler"
    pause
  done
}

main_menu() {
  while true; do
    print_header
    printf "1) 安装 sing-box\n"
    printf "2) 更新 sing-box\n"
    printf "3) 配置 systemd 服务\n"
    printf "4) 查看状态\n"
    printf "5) Proxy\n"
    printf "6) 卸载\n"
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
        proxy_menu_flow
        ;;
      6)
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
  load_protocol_modules
  main_menu
}

main "$@"
