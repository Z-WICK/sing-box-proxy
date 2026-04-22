#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd -- "$(dirname "${SOURCE_PATH}")" && pwd)"
LOCAL_SCRIPT="${SCRIPT_DIR}/scripts/sing-box-proxy-manager.sh"
RAW_BASE_URL="${SING_BOX_PROXY_RAW_BASE:-https://raw.githubusercontent.com/Z-WICK/sing-box-proxy/main}"

if [[ -f "${LOCAL_SCRIPT}" ]]; then
  exec "${LOCAL_SCRIPT}" "$@"
fi

if ! command -v curl >/dev/null 2>&1; then
  printf "缺少 curl，无法下载主脚本。\n" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d -t sing-box-proxy-manager.XXXXXX)"
TMP_SCRIPT_DIR="${TMP_ROOT}/scripts"
TMP_MODULE_DIR="${TMP_SCRIPT_DIR}/modules"
TMP_SCRIPT="${TMP_SCRIPT_DIR}/sing-box-proxy-manager.sh"
TMP_MODULE="${TMP_MODULE_DIR}/vless_reality.sh"
cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TMP_MODULE_DIR}"

curl -fsSL "${RAW_BASE_URL}/scripts/sing-box-proxy-manager.sh" -o "${TMP_SCRIPT}"
if ! curl -fsSL "${RAW_BASE_URL}/scripts/modules/vless_reality.sh" -o "${TMP_MODULE}"; then
  printf "警告：下载 VLESS Reality 模块失败，仅可使用 AnyTLS 功能。\n" >&2
  rm -f "${TMP_MODULE}"
fi
chmod +x "${TMP_SCRIPT}"
exec "${TMP_SCRIPT}" "$@"
