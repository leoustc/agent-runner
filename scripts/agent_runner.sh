#!/usr/bin/env bash
# Agent Runner Script
#
# The runner watches an inbox directory and invokes the configured agent CLI.
# Runtime behavior and coordination guidance come from:
# - /etc/agent-runner/SKILL.md (how agents should operate)
# - /etc/agent-runner/PROMPT.md (prompt fed to every run)
# Command-line args:
#   <inbox-path> <waittime-seconds> [agent-cli ...]
#   Optional --role can be passed by the service wrapper for downstream prompts.
# Single-instance execution is protected by a workspace LOCK file.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <inbox-path> <waittime-seconds> [agent-cli ...]" >&2
  exit 1
fi

INBOX_ARG="$1"
WAITTIME="$2"
shift 2 || true

if ! [[ "${WAITTIME}" =~ ^[0-9]+$ ]] || [ "${WAITTIME}" -le 0 ]; then
  echo "agent_runner.sh: waittime must be a positive integer" >&2
  exit 1
fi

ROLE=""
if [ $# -ge 2 ] && [ "$1" = "--role" ]; then
  ROLE="$2"
  shift 2 || true
fi

if [ $# -gt 0 ]; then
  AGENT_CMD=("$@")
else
  AGENT_CMD=(/usr/bin/codex exec --yolo)
fi

mkdir -p "${INBOX_ARG}"
INBOX_PATH="$(cd "${INBOX_ARG}" && pwd)"
WORKSPACE="$(cd "${INBOX_PATH}/.." && pwd)"

mkdir -p "${INBOX_PATH}" \
  "${WORKSPACE}/logs" \
  "${WORKSPACE}/processed" \
  "${WORKSPACE}/memory" \
  "${WORKSPACE}/notes" \
  "${WORKSPACE}/context"

LOCK_FILE="${WORKSPACE}/LOCK"

read_lock_pid() {
  if [ ! -f "${LOCK_FILE}" ]; then
    return 1
  fi
  tr -d '[:space:]' < "${LOCK_FILE}"
}

is_pid_running() {
  local pid="$1"
  if [ -z "${pid}" ]; then
    return 1
  fi
  kill -0 "${pid}" 2>/dev/null
}

release_lock() {
  rm -f "${LOCK_FILE}"
}

existing_pid="$(read_lock_pid || true)"
if [ -n "${existing_pid}" ]; then
  if is_pid_running "${existing_pid}"; then
    echo "agent_runner.sh: running already for ${WORKSPACE} with pid ${existing_pid}"
    exit 0
  fi
  rm -f "${LOCK_FILE}"
fi

if ! ( set -o noclobber; echo "$$" > "${LOCK_FILE}" ) 2>/dev/null; then
  echo "agent_runner.sh: failed to create lock file ${LOCK_FILE}" >&2
  exit 1
fi

cleanup() {
  release_lock
}
trap cleanup EXIT INT TERM

PROMPT_FILE="/etc/agent-runner/PROMPT.md"
if [ ! -f "${PROMPT_FILE}" ]; then
  mkdir -p "/etc/agent-runner"
  cat <<'EOF' > "${PROMPT_FILE}"
check inbox and reply
EOF
  echo "agent_runner.sh: prompt file not found, created default prompt at ${PROMPT_FILE}" >&2
fi
AGENT_INPUT="${PROMPT_FILE}"

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "agent_runner.sh: inotifywait is required. "
  echo "On Ubuntu or Debian: "
  echo "    sudo apt-get update && sudo apt-get install -y inotify-tools" 
  exit 1
fi

while true; do
  (
    cd "${WORKSPACE}"
    "${AGENT_CMD[@]}" < "${AGENT_INPUT}"
  )
  inotifywait --quiet --timeout "${WAITTIME}" --event create,close_write "${INBOX_PATH}" >/dev/null 2>&1 || exit 0
  echo "file change: ${INBOX_PATH}"
  ls -1 "${INBOX_PATH}"
done
