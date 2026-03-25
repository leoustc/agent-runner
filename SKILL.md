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

## DO NOT

- Never write to your own inbox.
- Identify your own inbox first. Your own inbox is the `INBOX` path of the
  agent section that matches your current workspace and role.
- If there is only one agent configured and it is you, do not think about asking
  another local agent for help.
