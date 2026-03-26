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

install -m 0755 "${ROOT_DIR}/scripts/agent_runner.sh" "${SOURCE_DIR}/scripts/agent_runner.sh"
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
Requires: bash, inotify-tools

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

install -m 0755 scripts/agent_runner.sh "%{buildroot}/usr/local/bin/agent-runner"

cat > "%{buildroot}/usr/local/bin/agent-runner-service" <<'SCRIPT'
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
SCRIPT
chmod 0755 "%{buildroot}/usr/local/bin/agent-runner-service"

cat > "%{buildroot}/usr/local/bin/agent-runner-manager" <<'SCRIPT'
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
SCRIPT
chmod 0755 "%{buildroot}/usr/local/bin/agent-runner-manager"

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
Restart=always
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
