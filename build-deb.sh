#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
PKG_NAME="agent-runner"
ARCH="all"
BUILD_DIR="${ROOT_DIR}/build/${PKG_NAME}_${VERSION}"
DIST_DIR="${ROOT_DIR}/dist"

rm -rf "${BUILD_DIR}"
mkdir -p \
  "${BUILD_DIR}/DEBIAN" \
  "${BUILD_DIR}/usr/local/bin" \
  "${BUILD_DIR}/lib/systemd/system" \
  "${BUILD_DIR}/etc/agent-runner" \
  "${BUILD_DIR}/usr/share/doc/agent-runner" \
  "${DIST_DIR}"

install -m 0755 "${ROOT_DIR}/scripts/agent_runner.sh" "${BUILD_DIR}/usr/local/bin/agent-runner"
cat > "${BUILD_DIR}/usr/local/bin/agent-runner-service" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <agent-name>" >&2
  exit 1
fi

AGENT_NAME="$1"
CONFIG_FILE="/etc/agent-runner/config"
CONFIG_SAMPLE="/etc/agent-runner/config.sample"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "agent-runner-service: config file not found: ${CONFIG_FILE}" >&2
  echo "Copy ${CONFIG_SAMPLE} to ${CONFIG_FILE} and update it first." >&2
  exit 1
fi

SECTION_FOUND=0
CURRENT_SECTION=""
INBOX=""
WAITTIME=""
ROLE=""
CLI=""

while IFS= read -r RAW_LINE || [ -n "${RAW_LINE}" ]; do
  LINE="${RAW_LINE#"${RAW_LINE%%[![:space:]]*}"}"
  LINE="${LINE%"${LINE##*[![:space:]]}"}"
  if [ -z "${LINE}" ] || [[ "${LINE}" == \#* ]] || [[ "${LINE}" == \;* ]]; then
    continue
  fi
  if [[ "${LINE}" =~ ^\[(.+)\]$ ]]; then
    CURRENT_SECTION="${BASH_REMATCH[1]}"
    if [ "${CURRENT_SECTION}" = "${AGENT_NAME}" ]; then
      SECTION_FOUND=1
    fi
    continue
  fi
  if [ "${CURRENT_SECTION}" != "${AGENT_NAME}" ]; then
    continue
  fi
  KEY="${LINE%%=*}"
  VALUE="${LINE#*=}"
  KEY="${KEY%"${KEY##*[![:space:]]}"}"
  VALUE="${VALUE#"${VALUE%%[![:space:]]*}"}"
  VALUE="${VALUE%"${VALUE##*[![:space:]]}"}"
  if [ "${#VALUE}" -ge 2 ] && { [ "${VALUE:0:1}" = '"' ] && [ "${VALUE: -1}" = '"' ]; }; then
    VALUE="${VALUE:1:${#VALUE}-2}"
  fi
  case "${KEY}" in
    INBOX) INBOX="${VALUE}" ;;
    WAITTIME) WAITTIME="${VALUE}" ;;
    ROLE) ROLE="${VALUE}" ;;
    CLI) CLI="${VALUE}" ;;
  esac
done < "${CONFIG_FILE}"

if [ "${SECTION_FOUND}" -ne 1 ]; then
  echo "agent-runner-service: section [${AGENT_NAME}] not found in ${CONFIG_FILE}" >&2
  exit 1
fi

if [ -z "${INBOX}" ] || [ -z "${WAITTIME}" ] || [ -z "${CLI}" ]; then
  echo "agent-runner-service: section [${AGENT_NAME}] must define INBOX, WAITTIME, and CLI" >&2
  exit 1
fi

eval "set -- ${CLI}"
if [ -n "${ROLE}" ]; then
  exec /usr/local/bin/agent-runner "${INBOX}" "${WAITTIME}" --role "${ROLE}" "$@"
fi
exec /usr/local/bin/agent-runner "${INBOX}" "${WAITTIME}" "$@"
EOF
chmod 0755 "${BUILD_DIR}/usr/local/bin/agent-runner-service"

cat > "${BUILD_DIR}/usr/local/bin/agent-runner-manager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <start|stop|restart>" >&2
  exit 1
fi

ACTION="$1"
CONFIG_FILE="/etc/agent-runner/config"
CONFIG_SAMPLE="/etc/agent-runner/config.sample"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "agent-runner-manager: config file not found: ${CONFIG_FILE}" >&2
  echo "Copy ${CONFIG_SAMPLE} to ${CONFIG_FILE} and update it first." >&2
  exit 1
fi

read_agents() {
  while IFS= read -r RAW_LINE || [ -n "${RAW_LINE}" ]; do
    LINE="${RAW_LINE#"${RAW_LINE%%[![:space:]]*}"}"
    LINE="${LINE%"${LINE##*[![:space:]]}"}"
    if [[ "${LINE}" =~ ^\[(.+)\]$ ]]; then
      echo "${BASH_REMATCH[1]}"
    fi
  done < "${CONFIG_FILE}"
}

mapfile -t AGENTS < <(read_agents)

if [ "${#AGENTS[@]}" -eq 0 ]; then
  echo "agent-runner-manager: no agent sections found in ${CONFIG_FILE}" >&2
  exit 1
fi

for AGENT in "${AGENTS[@]}"; do
  case "${ACTION}" in
    start) systemctl start "agent-runner@${AGENT}.service" ;;
    stop) systemctl stop "agent-runner@${AGENT}.service" ;;
    restart) systemctl restart "agent-runner@${AGENT}.service" ;;
    *)
      echo "agent-runner-manager: unsupported action: ${ACTION}" >&2
      exit 1
      ;;
  esac
done
EOF
chmod 0755 "${BUILD_DIR}/usr/local/bin/agent-runner-manager"

cat > "${BUILD_DIR}/usr/local/bin/agent-runner-update" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "agent-runner-update: must run as root" >&2
  echo "Try: curl -fsSL https://raw.githubusercontent.com/leoustc/agent-runner/main/install.sh | sudo bash" >&2
  exit 1
fi

curl -fsSL https://raw.githubusercontent.com/leoustc/agent-runner/main/install.sh | bash
EOF
chmod 0755 "${BUILD_DIR}/usr/local/bin/agent-runner-update"

cat > "${BUILD_DIR}/lib/systemd/system/agent-runner.service" <<'EOF'
[Unit]
Description=Agent Runner (all configured agents)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/agent-runner-manager start
ExecStop=/usr/local/bin/agent-runner-manager stop
ExecReload=/usr/local/bin/agent-runner-manager start

[Install]
WantedBy=multi-user.target
EOF

cat > "${BUILD_DIR}/lib/systemd/system/agent-runner@.service" <<'EOF'
[Unit]
Description=Agent Runner (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/agent-runner-service %i
WorkingDirectory=/
Restart=always
RestartSec=5
KillMode=control-group
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

install -m 0644 "${ROOT_DIR}/config.samples" "${BUILD_DIR}/etc/agent-runner/config.sample"
install -m 0644 "${ROOT_DIR}/SKILL.md" "${BUILD_DIR}/etc/agent-runner/SKILL.md"
install -m 0644 "${ROOT_DIR}/PROMPT.md" "${BUILD_DIR}/etc/agent-runner/PROMPT.md"
install -m 0644 "${ROOT_DIR}/config.samples" "${BUILD_DIR}/usr/share/doc/agent-runner/config.samples"

cat > "${BUILD_DIR}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: bash, inotify-tools, curl
Maintainer: li
Description: Standalone inbox-based agent runner shell script
 A small Debian package that installs the agent-runner CLI and systemd template service
 for inbox-driven agent work.
EOF

cat > "${BUILD_DIR}/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

systemctl daemon-reload || true
EOF

cat > "${BUILD_DIR}/DEBIAN/prerm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

true
EOF

cat > "${BUILD_DIR}/DEBIAN/postrm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

systemctl daemon-reload || true
EOF

chmod 0755 \
  "${BUILD_DIR}/DEBIAN/postinst" \
  "${BUILD_DIR}/DEBIAN/prerm" \
  "${BUILD_DIR}/DEBIAN/postrm"

dpkg-deb --build "${BUILD_DIR}" "${DIST_DIR}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "Built ${DIST_DIR}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
