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

install -m 0755 "${ROOT_DIR}/scripts/agent-runner-worker.sh" "${BUILD_DIR}/usr/local/bin/agent-runner"
install -m 0755 \
  "${ROOT_DIR}/scripts/agent-runner-service" \
  "${ROOT_DIR}/scripts/agent-runner-manager" \
  "${ROOT_DIR}/scripts/agent-runner-update" \
  "${ROOT_DIR}/scripts/agent-runner-status" \
  "${BUILD_DIR}/usr/local/bin/"

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
Restart=on-failure
RestartSec=5
KillMode=control-group
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

install -m 0644 "${ROOT_DIR}/config.samples" "${BUILD_DIR}/etc/agent-runner/config.sample"
install -m 0644 "${ROOT_DIR}/SKILL.md" "${BUILD_DIR}/etc/agent-runner/SKILL.md"
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
