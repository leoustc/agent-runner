# Agent Runner

`agent-runner` is a local multi-agent orchestration and inbox-based
communication system built around systemd.

## Features

- multiple agent management with systemd
- local file listening with low CPU usage
- mailbox-style agent-to-agent communication
- built-in skill file for local agent discovery and delegation
- supports local agent CLIs such as Codex, Claude, Cline, and Pi
- supports persistent local agents for faster follow-up and quick response
- supports dynamic agent add or delete with `systemctl reload agent-runner`
- simple config and go

This project packages a simple model:

- one agent runner per inbox
- one workspace per agent
- one shared config file that defines local agents
- local agent-to-agent communication by writing JSON files into inbox folders

The Debian package name and CLI name are both `agent-runner`.

## Description

This project is useful when you want several local agents to:

- run independently under systemd
- stay mapped to their own workspace and inbox
- communicate with each other through filesystem inbox messages
- be started one-by-one or as a configured group

Each agent:

- watches its own inbox
- runs in its own workspace
- can communicate with other local agents by writing JSON messages into their
  inboxes
- can be started individually or as part of the whole configured group

## Build Debian Package

```bash
make build-deb
```

The `.deb` package is written to `dist/`.

## Build RPM Package

```bash
make build-rpm
```

The `.rpm` package is written to `dist/`.

## Install

Install the latest release with:

```bash
curl -fsSL https://raw.githubusercontent.com/leoustc/agent-runner/main/install.sh | sudo bash
```

Or, if you keep this repo locally, run:

```bash
make update
```

## Install Debian Package

```bash
make install-deb
```

The package installs:

- `/usr/local/bin/agent-runner`
- `/usr/local/bin/agent-runner-service`
- `/usr/local/bin/agent-runner-manager`
- `/usr/local/bin/agent-runner-update`
- `/lib/systemd/system/agent-runner.service`
- `/lib/systemd/system/agent-runner@.service`
- `/etc/agent-runner/config.sample`
- `/etc/agent-runner/SKILL.md`
- `/usr/share/doc/agent-runner/config.samples`

## Install RPM Package

```bash
make install-rpm
```

The RPM package installs the same CLI files, config sample, skill file, and
systemd services. On RPM-based systems the service units are installed under
`/usr/lib/systemd/system`.

## Installed CLI Commands

Installed commands:

- `agent-runner <inbox-path> <waittime-seconds> [agent-cli ...]`  
  Start one watcher loop for an inbox and run the configured agent CLI with the installed prompt.
- `agent-runner-service <agent-name>`  
  Start a single named agent from its section in `/etc/agent-runner/config`.
- `agent-runner-manager <start|stop|restart>`  
  Manage all configured agent instances in batch.
- `agent-runner-update`  
  Reinstall/update to the latest release using the remote install script.

```bash
agent-runner --help
agent-runner-service manager
agent-runner-manager start
sudo agent-runner-update
```

## Summary

`agent-runner` provides filesystem-inbox orchestrated local agents with a simple
systemd service model, shared `/etc/agent-runner` configuration and skill bundle,
and a built-in update path through `agent-runner-update`.

## Config

The config file can define multiple local agents in one file.

Before starting the service, copy the sample file first:

```bash
sudo cp /etc/agent-runner/config.sample /etc/agent-runner/config
sudo editor /etc/agent-runner/config
```

## Update Command

Install the latest release again using the package updater:

```bash
sudo agent-runner-update
```

This runs the same installer URL:

```bash
curl -fsSL https://raw.githubusercontent.com/leoustc/agent-runner/main/install.sh | sudo bash
```

Example config:

```bash
[agent-a]
INBOX=/srv/agent-a/inbox
WAITTIME=600
ROLE="Architect"
CLI="/usr/bin/codex exec --yolo"

[agent-b]
INBOX=/srv/agent-b/inbox
WAITTIME=600
ROLE="Backend Engineer"
CLI="/usr/bin/codex exec --yolo"
```

Each section defines one local agent:

- `INBOX`
  The inbox folder for that agent
- `WAITTIME`
  The standby wait time in seconds
- `ROLE`
  The agent role used for routing and delegation decisions, and passed into the
  runner prompt
- `CLI`
  The command used to run the agent

## Service Modes

Start one service instance per section name:

```bash
sudo systemctl enable --now agent-runner@agent-a
sudo systemctl enable --now agent-runner@agent-b
```

If a section name contains `/`, replace it with `_` when addressing the instance
unit. For example: `[social/martin]` maps to `agent-runner@social_martin`.

Or start all configured agents at once:

```bash
sudo systemctl start agent-runner
```

To start newly added or currently stopped agents without restarting agents that
are already running, use:

```bash
sudo systemctl reload agent-runner
```

## Workflow

- `sudo systemctl start agent-runner`
  Starts the configured agent group.
- `sudo systemctl reload agent-runner`
  Starts newly added or currently stopped agents without restarting agents that
  are already running.
- `sudo systemctl stop agent-runner`
  Stops all configured agents.
- `sudo systemctl stop agent-runner@agent-a`
  Stops only one agent instance.
- `sudo systemctl start agent-runner@agent-a`
  Starts only one agent instance.

## Communication

Agents communicate through inbox files.

- each agent has one inbox
- the workspace of an agent is the parent directory of its inbox
- to delegate work, write a new JSON file into another agent's inbox
- to discover another agent's inbox and role, use `/etc/agent-runner/config`
- `/etc/agent-runner/SKILL.md` explains the local agent-to-agent communication
  contract

## How to Add Agent Runner

1. Edit `/etc/agent-runner/config`
2. Add a new section such as:

```bash
[agent-c]
INBOX=/srv/agent-c/inbox
WAITTIME=600
ROLE="Frontend Engineer"
CLI="/usr/bin/codex exec --yolo"
```

3. Create the inbox parent workspace if needed
4. Run:

```bash
sudo systemctl reload agent-runner
```

That will start the new agent if it is not already running, and it will not
restart agents that are already running.

## How to Stop Agent Runner

Stop one agent:

```bash
sudo systemctl stop agent-runner@agent-a
```

Stop all configured agents:

```bash
sudo systemctl stop agent-runner
```

## Hints

- Do not run `systemctl restart agent-runner` unless you want all configured
  agents to restart.
- Use `systemctl reload agent-runner` when you add a new config section and want
  to start only the missing or stopped agents.
- If you want to restart only one agent, use:

```bash
sudo systemctl restart agent-runner@agent-a
```

After install:

```bash
sudo systemctl status agent-runner
sudo systemctl status agent-runner@agent-a
```

Runtime dependency:

- `inotify-tools`
