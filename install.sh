#!/usr/bin/env bash
set -euo pipefail

REPO="leoustc/agent-runner"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "install.sh: missing required command: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd python3

if [ "${EUID}" -ne 0 ]; then
  echo "install.sh: this installer must run as root" >&2
  echo "Try: curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | sudo bash" >&2
  exit 1
fi

if [ ! -r /etc/os-release ]; then
  echo "install.sh: cannot determine operating system" >&2
  echo "This installer only supports Debian-based systems." >&2
  exit 1
fi

. /etc/os-release

case "${ID:-}" in
  debian|ubuntu|linuxmint|pop|neon|elementary|kali|raspbian)
    ;;
  *)
    case " ${ID_LIKE:-} " in
      *" debian "*)
        ;;
      *)
        echo "install.sh: unsupported operating system: ${PRETTY_NAME:-unknown}" >&2
        echo "This installer only supports Debian-based systems." >&2
        exit 1
        ;;
    esac
    ;;
esac

require_cmd dpkg

echo "Fetching latest release metadata for ${REPO}..."
curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${API_URL}" > "${TMP_DIR}/release.json"

DEB_URL="$(
python3 - "${TMP_DIR}/release.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

assets = data.get("assets", [])
preferred = None
fallback = None

for asset in assets:
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name.endswith("_all.deb"):
        preferred = url
        break
    if name.endswith(".deb") and fallback is None:
        fallback = url

print(preferred or fallback or "")
PY
)"

if [ -z "${DEB_URL}" ]; then
  echo "install.sh: no .deb asset found in the latest release" >&2
  exit 1
fi

DEB_FILE="${TMP_DIR}/$(basename "${DEB_URL}")"

echo "Downloading $(basename "${DEB_URL}")..."
curl -fsSL "${DEB_URL}" -o "${DEB_FILE}"

echo "Installing $(basename "${DEB_FILE}")..."
dpkg -i "${DEB_FILE}"

echo "Installed $(basename "${DEB_FILE}")"
