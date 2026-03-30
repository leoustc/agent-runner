#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
PKG_NAME="agent-runner"
RPM_ARCH="noarch"
RPM_ROOT="${ROOT_DIR}/build/rpm"
TOPDIR="${RPM_ROOT}/rpmbuild"
TARBALL="${TOPDIR}/SOURCES/${PKG_NAME}-${VERSION}.tar.gz"
SPEC_FILE="${TOPDIR}/SPECS/${PKG_NAME}.spec"
DIST_DIR="${ROOT_DIR}/dist"
SOURCE_DIR="${RPM_ROOT}/${PKG_NAME}-${VERSION}"

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "build-rpm.sh: rpmbuild is required" >&2
  echo "On Fedora, RHEL, or Rocky: sudo dnf install -y rpm-build" >&2
  exit 1
fi

rm -rf "${RPM_ROOT}"
mkdir -p \
  "${TOPDIR}/BUILD" \
  "${TOPDIR}/BUILDROOT" \
  "${TOPDIR}/RPMS" \
  "${TOPDIR}/SOURCES" \
  "${TOPDIR}/SPECS" \
  "${TOPDIR}/SRPMS" \
  "${DIST_DIR}" \
  "${SOURCE_DIR}/scripts"

install -m 0755 "${ROOT_DIR}/scripts/agent-runner-worker.sh" "${SOURCE_DIR}/scripts/agent-runner-worker.sh"
install -m 0755 \
  "${ROOT_DIR}/scripts/agent-runner-service" \
  "${ROOT_DIR}/scripts/agent-runner-manager" \
  "${ROOT_DIR}/scripts/agent-runner-update" \
  "${ROOT_DIR}/scripts/agent-runner-status" \
  "${SOURCE_DIR}/scripts/"
install -m 0644 "${ROOT_DIR}/config.samples" "${SOURCE_DIR}/config.samples"
install -m 0644 "${ROOT_DIR}/SKILL.md" "${SOURCE_DIR}/SKILL.md"
install -m 0644 "${ROOT_DIR}/LICENSE" "${SOURCE_DIR}/LICENSE"
install -m 0644 "${ROOT_DIR}/README.md" "${SOURCE_DIR}/README.md"

tar -C "${RPM_ROOT}" -czf "${TARBALL}" "${PKG_NAME}-${VERSION}"

cat > "${SPEC_FILE}" <<'EOF'
Name: __PKG_NAME__
Version: __VERSION__
Release: 1%{?dist}
Summary: Standalone inbox-based agent runner shell script
License: MIT
URL: https://github.com/leoustc/agent-runner
Source0: %{name}-%{version}.tar.gz
BuildArch: __RPM_ARCH__
Requires: bash, inotify-tools, curl

%description
A small RPM package that installs the agent-runner CLI and systemd template
service for inbox-driven agent work.

%prep
%setup -q

%build

%install
rm -rf "%{buildroot}"
install -d "%{buildroot}/usr/local/bin"
install -d "%{buildroot}/usr/lib/systemd/system"
install -d "%{buildroot}/etc/agent-runner"
install -d "%{buildroot}/usr/share/doc/%{name}"

install -m 0755 scripts/agent-runner-worker.sh "%{buildroot}/usr/local/bin/agent-runner"
install -m 0755 scripts/agent-runner-service "%{buildroot}/usr/local/bin/agent-runner-service"
install -m 0755 scripts/agent-runner-manager "%{buildroot}/usr/local/bin/agent-runner-manager"
install -m 0755 scripts/agent-runner-update "%{buildroot}/usr/local/bin/agent-runner-update"
install -m 0755 scripts/agent-runner-status "%{buildroot}/usr/local/bin/agent-runner-status"

cat > "%{buildroot}/usr/lib/systemd/system/agent-runner.service" <<'UNIT'
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
UNIT

cat > "%{buildroot}/usr/lib/systemd/system/agent-runner@.service" <<'UNIT'
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
UNIT

install -m 0644 config.samples "%{buildroot}/etc/agent-runner/config.sample"
install -m 0644 SKILL.md "%{buildroot}/etc/agent-runner/SKILL.md"
install -m 0644 config.samples "%{buildroot}/usr/share/doc/%{name}/config.samples"
install -m 0644 README.md "%{buildroot}/usr/share/doc/%{name}/README.md"
install -m 0644 LICENSE "%{buildroot}/usr/share/doc/%{name}/LICENSE"

%post
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
fi

%postun
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
fi

%files
%license /usr/share/doc/%{name}/LICENSE
%doc /usr/share/doc/%{name}/README.md
/usr/local/bin/agent-runner
/usr/local/bin/agent-runner-service
/usr/local/bin/agent-runner-manager
/usr/local/bin/agent-runner-update
/usr/local/bin/agent-runner-status
/usr/lib/systemd/system/agent-runner.service
/usr/lib/systemd/system/agent-runner@.service
/etc/agent-runner/config.sample
/etc/agent-runner/SKILL.md
/usr/share/doc/%{name}/config.samples

%changelog
* Thu Mar 26 2026 li <li@localhost> - __VERSION__-1
- Build initial RPM package
EOF

sed -i \
  -e "s/__PKG_NAME__/${PKG_NAME}/g" \
  -e "s/__VERSION__/${VERSION}/g" \
  -e "s/__RPM_ARCH__/${RPM_ARCH}/g" \
  "${SPEC_FILE}"

rpmbuild \
  --define "_topdir ${TOPDIR}" \
  -bb "${SPEC_FILE}"

RPM_GLOB="${TOPDIR}/RPMS/${RPM_ARCH}/${PKG_NAME}-${VERSION}-1*.${RPM_ARCH}.rpm"
mapfile -t RPM_FILES < <(compgen -G "${RPM_GLOB}" || true)

if [ "${#RPM_FILES[@]}" -ne 1 ]; then
  echo "build-rpm.sh: expected exactly one RPM matching: ${RPM_GLOB}" >&2
  exit 1
fi

RPM_FILE="${RPM_FILES[0]}"
cp "${RPM_FILE}" "${DIST_DIR}/"
echo "Built ${DIST_DIR}/$(basename "${RPM_FILE}")"
