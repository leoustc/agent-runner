# Agent Runner Skill

This skill is for agents running under `agent-runner`.

Use it when you need to discover another local agent and write a message to that
agent's inbox.

## Discover

Each local agent is defined by one section in `/etc/agent-runner/config`.

To find another agent:

- read `/etc/agent-runner/config`
- find the target agent section
- check the `ROLE` field to identify which agent is the right one for the task
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
- The workspace of the agent is the parent directory of that inbox path.
- Use `ROLE` to decide which agent should receive the delegated task.
- If you want to delegate work to another agent, write a new JSON message file
  into that agent's inbox path.
- Write one new JSON file per message or task.

## Communication

- Use the target agent's inbox path from `/etc/agent-runner/config`.
- Write a JSON file that clearly states the task, context, and expected output.
- If useful, include:
  - `latest-user-prompt`
  - `context_id`
  - any task-specific instructions
- Do not overwrite an existing inbox file. Create a new file for each message.
- Write the message atomically: write to a temporary file in the same inbox
  directory first, then rename it to the final `.json` filename
- If the other agent is already running, it will pick up the new inbox file by
  itself.

## ADD agent session

- Add a new `[agent-name]` section to `/etc/agent-runner/config`.
- Set `INBOX` to a writable folder for that agent (must be unique).
- Set `WAITTIME` in seconds (for example `600`).
- Set `ROLE` to a clear routing label.
- Set `GROUP` to the project-style coordination group for this agent (for example `engineer`, `social`, `gpulab`).
- If `GROUP` is not set, use `core` as the default.
- When `GROUP` is set, place the agent workspace under:
  - `/.../<GROUP>/<agent-name>/`
  - and use `/.../<GROUP>/<agent-name>/inbox` as `INBOX`.
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
  - `sudo mv /path/to/<GROUP>/<agent-name> /path/to/archive/<GROUP>/<agent-name>_archived`
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
