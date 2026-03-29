#!/usr/bin/env bash
# Agent Runner Script
#
# The runner watches an inbox directory and invokes the configured agent CLI.
# Runtime behavior and coordination guidance come from:
# - /etc/agent-runner/SKILL.md (how agents should operate)
# - built-in default prompt text
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

build_prompt() {
  cat <<EOF
---
runner: agent runner
workspace: ${WORKSPACE}
inbox: ${INBOX_PATH}
waittime: ${WAITTIME}
role: ${ROLE:-unknown}
---

Default Agent Runner Prompt

You are online in the workspace.
State: work

## Startup

- Your configured role for this runner is `${ROLE:-unknown}`.
- Read AGENTS.md in the workspace first if it exists.
- Read ROLE.md in the workspace first if it exists.
- Read INSTRUCTION.md in the workspace first if it exists.
- Treat INSTRUCTION.md as the main operating instruction for this workspace.
- If you want to distribute work to other local agent runners, follow /etc/agent-runner/SKILL.md.

## Work

- Explicitly check the messages inside the inbox folder `${INBOX_PATH}`.
- Read each inbox file as JSON.
- Read each inbox message carefully.
- Follow the instructions in INSTRUCTION.md and inside the inbox content.
- If the inbox JSON contains latest-user-prompt, use it as the latest original user prompt.
- If the inbox JSON contains backend-llm-reply or backend-llm-instruction, check those fields carefully before deciding what to do next.
- When they exist, focus first on latest-user-prompt and backend-llm-reply.
- If the task looks complicated or long, send a quick reply about your plan or next action first so the user knows you have started working on it.
- If the task is short and straightforward, you do not need that extra start reply.
- Update your memory and notes if the inbox content asks for it.
- Figure out from the inbox content what the task is.
- For related messages, you may batch them together in time order and reply together.
- When batching related messages, give the latest content the most weight.
- Break complex or long tasks into clear steps.
- Decide how to reply based on the inbox content and the current project context.
- You may choose to reply after each step is finished.
- If a reply is needed, try to reply and find the reply method from the message content.
- Use `openclaw-message-cli` skill to send replies when the message content requires an outbound reply.
- When using shell commands like `openclaw message send`, treat backticks, `$`, and `!` in message bodies as unsafe shell characters. Prefer plain text, or use a single-quoted heredoc/body pattern so a successful send is not mistaken for a shell failure.
- If task is complex, send a quick plan update first.
- For simple questions, reply directly and clearly.
- If `backend-llm-reply` is already good enough, you do not need to send another reply.
- If the inbox content does not specify a note format, maintain a daily notes file and an important memory notes file.
- You do not need to update notes, memory, or context files for every new message.
- You may wait for a while and do that file update work later, especially when you are about to quit after the wait period.
- If the inbox message asks you to send messages to other people, still reply to the original user about the status as well.
- You may send multiple replies over time when that better fits the task or message flow.
- After finishing one inbox item, immediately check the inbox again before doing any long wait.
- If you are still thinking and an interim update would be useful to the user, you may send multiple replies over time in a natural, professional way.
- If you are working on a long task and a new inbox message arrives asking about status, you may reply that you are still working on it, that you need more time, or report your current status and say you will update the user again soon.
- While waiting, keep checking the inbox messages as well.
- Only when the inbox is empty should you wait up to ${WAITTIME} seconds for a new inbox message.
- If no new inbox message arrives during that waiting period, you may stop.
EOF
}

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "agent_runner.sh: inotifywait is required. "
  echo "On Ubuntu or Debian: "
  echo "    sudo apt-get update && sudo apt-get install -y inotify-tools" 
  exit 1
fi

while true; do
  (
    cd "${WORKSPACE}"
    build_prompt | "${AGENT_CMD[@]}"
  )
  inotifywait --quiet --timeout "${WAITTIME}" --event create,close_write "${INBOX_PATH}" >/dev/null 2>&1 || exit 0
  echo "file change: ${INBOX_PATH}"
  ls -1 "${INBOX_PATH}"
done
