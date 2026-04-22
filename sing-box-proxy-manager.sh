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

TMP_SCRIPT="$(mktemp -t sing-box-proxy-manager.XXXXXX.sh)"
cleanup() {
  rm -f "${TMP_SCRIPT}"
}
trap cleanup EXIT

curl -fsSL "${RAW_BASE_URL}/scripts/sing-box-proxy-manager.sh" -o "${TMP_SCRIPT}"
chmod +x "${TMP_SCRIPT}"
exec "${TMP_SCRIPT}" "$@"
