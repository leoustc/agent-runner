#!/usr/bin/env bash
# Agent Runner Worker Script
#
# Inputs:
#   1. inbox path
#   2. waittime in seconds
#   3. optional --role <role>
#   4. optional agent CLI command
#
# Usage:
#   ./agent-runner-worker.sh ./inbox 600
#   ./agent-runner-worker.sh ./inbox 600 --role "Architect"
#   ./agent-runner-worker.sh ./inbox 600 /usr/bin/codex exec --yolo
#   ./agent-runner-worker.sh ./inbox 600 --role "Architect" /usr/bin/codex exec --yolo
#
# Additional Runner:
#   If you want to create another agent runner, create another inbox folder first
#   and then start this script with that inbox path.
#
# Hints:
#   - The workspace defaults to the parent directory of the inbox path,
#     unless WORKSPACE_OVERRIDE is provided by the launcher.
#   - The inbox is the place where new message files arrive.
#
# Workflow:
#   1. Resolve the workspace from the parent directory of the inbox path.
#   2. Prepare the workspace runtime folders:
#      logs, processed, memory, notes, and context.
#   3. Create a built-in runner prompt file in the workspace.
#   4. Start the agent CLI with that prompt.
#   5. Block on inbox file activity with inotifywait.
#   6. When a new inbox file arrives or a write completes, print the inbox file list.
#   7. Loop and run the agent again.
#
# Concurrency:
#   - Only one runner instance should be active per workspace.
#   - A LOCK file with the current PID is used to prevent duplicates.
set -u
set -o pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <inbox-path> <waittime-seconds> [agent-cli ...]" >&2
  exit 1
fi

INBOX_ARG="$1"
WAITTIME="$2"
shift 2 || true
TEAM="${TEAM_NAME:-default}"

if ! [[ "${WAITTIME}" =~ ^[0-9]+$ ]] || [ "${WAITTIME}" -le 0 ]; then
  echo "agent-runner-worker.sh: waittime must be a positive integer" >&2
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
if [ -n "${WORKSPACE_OVERRIDE:-}" ]; then
  WORKSPACE_INPUT="${WORKSPACE_OVERRIDE}"
  if [ ! -d "${WORKSPACE_INPUT}" ]; then
    mkdir -p "${WORKSPACE_INPUT}" || {
      echo "agent-runner-worker.sh: cannot create workspace ${WORKSPACE_INPUT}" >&2
      exit 1
    }
  fi
  WORKSPACE="$(cd "${WORKSPACE_INPUT}" && pwd)"
else
  WORKSPACE="$(cd "${INBOX_PATH}/.." && pwd)"
fi

mkdir -p "${INBOX_PATH}" \
  "${WORKSPACE}/processed" \
  "${WORKSPACE}/memory" \
  "${WORKSPACE}/notes" \
  "${WORKSPACE}/context"

LOCK_FILE="${WORKSPACE}/LOCK"
LOG_FILE="${WORKSPACE}/.agent-runner.log"

if [ -n "${AGENT_NAME:-}" ]; then
  SAFE_AGENT_NAME="${AGENT_NAME//\//_}"
  SAFE_AGENT_NAME="${SAFE_AGENT_NAME// /_}"
else
  SAFE_AGENT_NAME="$(basename "${WORKSPACE}")"
fi

if mkdir -p /var/log/agent-runner 2>/dev/null; then
  LOG_FILE="/var/log/agent-runner/${SAFE_AGENT_NAME}.log"
fi

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
    echo "agent-runner-worker.sh: running already for ${WORKSPACE} with pid ${existing_pid}"
    exit 0
  fi
  rm -f "${LOCK_FILE}"
fi

if ! ( set -o noclobber; echo "$$" > "${LOCK_FILE}" ) 2>/dev/null; then
  echo "agent-runner-worker.sh: failed to create lock file ${LOCK_FILE}" >&2
  exit 1
fi

cleanup() {
  release_lock
}
trap cleanup EXIT INT TERM

PROMPT_FILE="${WORKSPACE}/.runner_prompt.md"

write_prompt_file() {
  local snapshot_file="$1"
  local file_path
  local src_file
  local has_files=false

  cat > "${PROMPT_FILE}" <<EOF
---
runner: agent runner
workspace: ${WORKSPACE}
inbox: ${INBOX_PATH}
team: ${TEAM}
waittime: ${WAITTIME}
role: ${ROLE}
---

# Runner Prompt

You are an agent runner in the workspace \`${WORKSPACE}\` with role \`${ROLE}\` and team \`${TEAM}\`.

## Operational Steps
- Read \`AGENTS.md\`, \`ROLE.md\`, and \`INSTRUCTION.md\` first if present.
- Read new inbox files in batches, then process and reply one-by-one in order.
- Send one reply when context is ready. Keep messages direct and concise.
- If a message does not specify a reply destination, send replies to manager/master.
- Recheck the inbox after each item before waiting.
- If no inbox activity for \`${WAITTIME}\` seconds, you may stop.
- After finishing an item, move it out of inbox to \`${WORKSPACE}/processed/\` if available.

Use \`/etc/agent-runner/SKILL.md\` for delegation and context conventions.

## Current Inbox
Process the inbox messages below now. For each message, print a direct text reply.
Do not only acknowledge the prompt; answer the message content.
EOF

  if [ -f "${snapshot_file}" ]; then
    while IFS= read -r -d '' file_path; do
      [ -z "${file_path}" ] && continue
      [ "${file_path}" = "." ] && continue
      src_file="${INBOX_PATH}/${file_path#./}"
      [ -f "${src_file}" ] || continue
      has_files=true
      {
        printf "\n### %s\n\n" "${file_path#./}"
        printf '```text\n'
        cat -- "${src_file}"
        printf '\n```\n'
      } >> "${PROMPT_FILE}"
    done < "${snapshot_file}"
  fi

  if [ "${has_files}" != true ]; then
    cat >> "${PROMPT_FILE}" <<'EOF'

No current inbox files are present. Say that the inbox is empty and wait for the next task.
EOF
  fi
}

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "agent-runner-worker.sh: inotifywait is required. "
  echo "On Ubuntu or Debian: "
  echo "    sudo apt-get update && sudo apt-get install -y inotify-tools" 
  HAS_INOTIFYWAIT=false
else
  HAS_INOTIFYWAIT=true
fi

run_agent_once() {
  local command_status=0

  echo "----- $(date -u +\"%Y-%m-%dT%H:%M:%SZ\") -----"

  (
    cd "${WORKSPACE}" && {
      "${AGENT_CMD[@]}" < "${PROMPT_FILE}"
    }
  )
  command_status=$?

  if [ "${command_status}" -ne 0 ]; then
    echo "agent-runner-worker.sh: agent command failed for ${WORKSPACE}" >&2
    echo "agent-runner-worker.sh: command: ${AGENT_CMD[*]}" >&2
    echo "agent-runner-worker.sh: status: ${command_status}" >&2
    return 1
  fi
}

snapshot_inbox_files() {
  local snapshot_file="$1"
  (
    cd "${INBOX_PATH}" && \
      find . -maxdepth 1 -type f -not -name ".runner_prompt.md" -print0
  ) > "${snapshot_file}"
}

inbox_has_files() {
  (
    cd "${INBOX_PATH}" && \
      find . -maxdepth 1 -type f -not -name ".runner_prompt.md" -print -quit
  ) | grep -q .
}

cleanup_inbox_snapshot() {
  local snapshot_file="$1"
  local processed_dir="${WORKSPACE}/processed"
  local file_path

  if [ ! -f "${snapshot_file}" ]; then
    return 0
  fi

  while IFS= read -r -d '' file_path; do
    [ -z "${file_path}" ] && continue
    if [ "${file_path}" = "." ]; then
      continue
    fi
    local src_file="${INBOX_PATH}/${file_path#./}"
    if [ -f "${src_file}" ]; then
      if [ -d "${processed_dir}" ]; then
        mv -- "${src_file}" "${processed_dir}/" 2>/dev/null || rm -f -- "${src_file}"
      else
        rm -f -- "${src_file}"
      fi
    fi
  done < "${snapshot_file}"
}

while true; do
  INBOX_SNAPSHOT="$(mktemp)"
  snapshot_inbox_files "${INBOX_SNAPSHOT}"
  write_prompt_file "${INBOX_SNAPSHOT}"

  run_exit=0
  run_agent_once || run_exit=$?
  if [ "${run_exit}" -eq 0 ]; then
    cleanup_inbox_snapshot "${INBOX_SNAPSHOT}"
  else
    echo "agent-runner-worker.sh: agent run failed; keeping inbox files for retry: ${INBOX_SNAPSHOT}" >&2
  fi
  rm -f -- "${INBOX_SNAPSHOT}"

  if inbox_has_files; then
    continue
  fi

  if [ "${HAS_INOTIFYWAIT}" != true ]; then
    sleep "${WAITTIME}"
    continue
  fi

  if inotifywait --quiet --timeout "${WAITTIME}" --event create,close_write "${INBOX_PATH}" >/dev/null 2>&1; then
    echo "file change: ${INBOX_PATH}"
    ls -1 "${INBOX_PATH}" || true
  elif [ $? -ne 1 ]; then
    echo "agent-runner-worker.sh: inotifywait failed on ${INBOX_PATH}, code $?" >&2
    sleep 2
  fi
done
