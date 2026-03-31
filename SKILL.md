# Agent Runner Skill

This skill is for agents running under `agent-runner`.

Use it when you need to discover another local agent and write a message to that
agent's inbox.

## Discover

Each local agent is defined by one section in `/etc/agent-runner/config`.

To find another agent:

- read `/etc/agent-runner/config`
- find the target agent section
- check the `ROLE`, `TEAM`, and `INBOX` fields to identify which agent is the right one for the task
- read the `INBOX` value in that section
- if more than one agent has the same suitable `ROLE`, choose the most specific
  match for the task
- if `ROLE` is missing or the match is ambiguous, do not guess. Keep the work
  local instead of routing it to the wrong agent

Examples:

- `master` -> `/root/.openclaw/workspace/inbox`
- `architect` -> `/root/.openclaw/agents/architect/inbox`

## Usage

- One agent runner watches one inbox path.
- The workspace defaults to the parent directory of `INBOX`.
- Optional `WORKSPACE` can override that default and force a custom workspace path.
- Optional `TEAM` selects the team label shown by status output (`default` when omitted).
- Use `ROLE` to decide which agent should receive the delegated task.
- If you want to delegate work to another agent, write a new JSON message file
  into that agent's inbox path.
- Write one new JSON file per message or task.

## Communication

- Use the target agent's inbox path from `/etc/agent-runner/config`.
- Write a JSON file that clearly states the task, context, and expected output.
- Include at least:
  - task fields and expected output
  - any task-specific instructions
- For manager/master messages, additionally include:
  - `context_id`
  - `context_file` (absolute or workspace-relative path to the JSONL context file, format:
    `${WORKSPACE}/context/<context_id>/<YYYY-MM-DD>.jsonl`)
- For outbound responses, include `reply_to_inbox` if you want a specific recipient inbox.
- If `reply_to_inbox` is missing, send the reply to the manager/master inbox by default.
- Workers can read the provided `context_file` when available to understand task context.
- Do not overwrite an existing inbox file. Create a new file for each message.
- Write the message atomically: write to a temporary file in the same inbox
  directory first, then rename it to the final `.json` filename
- After processing each inbox file, remove it from the inbox or move it to
  `<WORKSPACE>/processed/` to keep the queue clean.
- If the other agent is already running, it will pick up the new inbox file by
  itself.
- When reading agent status, use `agent-runner-status` and interpret `TEAM` columns
  with `default` as the fallback when no `TEAM` is set.

## Context Management

- For tasks handled by the master/manager role only, maintain daily context logs in a
  per-task folder keyed by `context_id`.
- Use the workspace context folder: `${WORKSPACE}/context/`.
- Store and append task history as JSONL in daily files:
  - `${WORKSPACE}/context/<context_id>/<YYYY-MM-DD>.jsonl`
- Read `context_id` from the incoming inbox message JSON.
- If `context_id` is missing, `null`, blank, or not usable, use `default` as a fallback.
- Use UTC date (`YYYY-MM-DD`) for daily file names and append to today’s file:
  - `${WORKSPACE}/context/<context_id>/<YYYY-MM-DD>.jsonl`.
- For each received task, manager/master should:
  - create the context file if missing
  - append task summary, requirements, and current state as JSON lines
  - note the selected agent, handoff notes, and expected outputs
  - append status updates as status moves (`received`, `dispatched`, `in_progress`,
    `completed`, `blocked`)
- Remove duplicate context lines before writing new updates so each entry stays
  concise:
  - do not duplicate identical task summaries
  - do not duplicate unchanged status transitions
  - when appending periodic updates, prefer an incremental event format (`append` + unique `event_id` or `timestamp+status`) to avoid repeated full snapshots
- Include `context_id` and `context_file` in all delegated inbox messages and keep
  a single source of truth in the JSONL context file.
- When dispatching, fill `context_file` with the exact path of the JSONL file the
  manager/master maintains for that task.
- Only manager/master may write, update, or modify context files; workers should only read.
- Do not create ad-hoc context snapshots outside the
  `${WORKSPACE}/context/<context_id>/<YYYY-MM-DD>.jsonl` files unless asked.

## ADD agent session

- Add a new `[agent-name]` section to `/etc/agent-runner/config`.
- Set `INBOX` to a writable folder for that agent (must be unique).
- Set `WAITTIME` in seconds (for example `600`).
- Set `ROLE` to a clear routing label.
- Set `TEAM` to the coordination team label (for example `engineer`, `social`, `gpulab`).
- If `TEAM` is not set, use `default`.
- If your layout is team-based, place the workspace under:
  - `/.../<TEAM>/<agent-name>/`
  - and use `/.../<TEAM>/<agent-name>/inbox` as `INBOX`.
- Optionally set `WORKSPACE`; if omitted, it defaults to the parent folder of `INBOX`.
- Set `CLI` to the command used to run that agent (for example `/usr/bin/codex exec --yolo`).
- Create the workspace parent directory for the inbox if it does not exist.
- Reload the runner set with `sudo systemctl reload agent-runner`.
- Start the specific agent if needed with `sudo systemctl start agent-runner@agent-name`.
- Confirm startup with `sudo systemctl status agent-runner@agent-name`.

## DELETE agent session

- Stop the agent first:
  - `sudo systemctl stop agent-runner@agent-name`
- Remove the agent section from `/etc/agent-runner/config`.
- Move the workspace to an archive folder instead of deleting it:
  - `sudo mv /path/to/<TEAM>/<agent-name> /path/to/archive/<TEAM>/<agent-name>_archived`
- Optionally clear inbox files from the archived workspace after archiving.
- Reload the runner set so removed agents do not restart:
  - `sudo systemctl reload agent-runner`
- Keep the archived workspace unless explicitly told to delete it.
- Do not delete agent workspaces by default.

## DO NOT

- Never write to your own inbox.
- Identify your own inbox first. Your own inbox is the `INBOX` path of the
  agent section that matches your current workspace and role.
- If there is only one agent configured and it is you, do not think about asking
  another local agent for help.
