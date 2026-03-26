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

PACKAGE_KIND=""

if [ "${EUID}" -ne 0 ]; then
  echo "install.sh: this installer must run as root" >&2
  echo "Try: curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | sudo bash" >&2
  exit 1
fi

if [ ! -r /etc/os-release ]; then
  echo "install.sh: cannot determine operating system" >&2
  echo "This installer only supports Debian-based and RPM-based systems." >&2
  exit 1
fi

. /etc/os-release

case "${ID:-}" in
  debian|ubuntu|linuxmint|pop|neon|elementary|kali|raspbian)
    PACKAGE_KIND="deb"
    ;;
  fedora|rhel|centos|rocky|almalinux|ol|amzn|opensuse*|sles)
    PACKAGE_KIND="rpm"
    ;;
esac

if [ -z "${PACKAGE_KIND}" ]; then
  case " ${ID_LIKE:-} " in
    *" debian "*)
      PACKAGE_KIND="deb"
      ;;
    *" rhel "*|*" fedora "*|*" suse "*)
      PACKAGE_KIND="rpm"
      ;;
    *)
      echo "install.sh: unsupported operating system: ${PRETTY_NAME:-unknown}" >&2
      echo "This installer only supports Debian-based and RPM-based systems." >&2
      exit 1
      ;;
  esac
fi

case "${PACKAGE_KIND}" in
  deb) require_cmd dpkg ;;
  rpm) require_cmd rpm ;;
esac

echo "Fetching latest release metadata for ${REPO}..."
curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${API_URL}" > "${TMP_DIR}/release.json"

PACKAGE_URL="$(
python3 - "${TMP_DIR}/release.json" "${PACKAGE_KIND}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

assets = data.get("assets", [])
package_kind = sys.argv[2]
preferred = None
fallback = None

for asset in assets:
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if package_kind == "deb":
        if name.endswith("_all.deb"):
            preferred = url
            break
        if name.endswith(".deb") and fallback is None:
            fallback = url
    elif package_kind == "rpm":
        if name.endswith(".noarch.rpm"):
            preferred = url
            break
        if name.endswith(".rpm") and fallback is None:
            fallback = url

print(preferred or fallback or "")
PY
)"

if [ -z "${PACKAGE_URL}" ]; then
  echo "install.sh: no ${PACKAGE_KIND} package asset found in the latest release" >&2
  exit 1
fi

PACKAGE_FILE="${TMP_DIR}/$(basename "${PACKAGE_URL}")"

echo "Downloading $(basename "${PACKAGE_URL}")..."
curl -fsSL "${PACKAGE_URL}" -o "${PACKAGE_FILE}"

echo "Installing $(basename "${PACKAGE_FILE}")..."
case "${PACKAGE_KIND}" in
  deb)
    dpkg -i "${PACKAGE_FILE}"
    ;;
  rpm)
    rpm -Uvh "${PACKAGE_FILE}"
    ;;
esac

echo "Installed $(basename "${PACKAGE_FILE}")"
