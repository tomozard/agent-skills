# setup.md — install the Herdr agent-team harness

Read this only when `command -v hteam` prints nothing, or when the Human asks to
install, repair or reinstall the team. Everything below is a command to run, not a
description to summarise: run each step and report the output you actually got.

**This file is a procedure, not the payload.** The launcher, the 12 role prompts,
the guard binaries, the extensions and the voice files live in the harness
repository (`project-scaffold`), not in this skill. Do not recreate them by hand.

## Hard rules

- Never copy files into `~/bin`, `~/.agents/agents`, `~/.agents/extensions`,
  `~/.claude/agents` or `~/.pi` by hand. A hand-copied file differs from the
  installed one and every later verification lies about it.
- Never edit anything under `~/.agents/skills/herdr-agent-team/`. `npx skills add`
  overwrites it on the next update; change the skill repository instead.
- Never run the uninstaller from inside a team role pane (`HERDR_AGENT_ROLE` is
  set). It removes the binaries that pane is running from.
- If a step fails, stop and report the exact stderr. Do not try a second path
  silently — the installer refuses for a reason (missing prerequisite, wrong
  branch, dirty tree).

## 1. Prerequisites

```bash
python3 --version                                  # 3.9+
python3 -c 'import yaml; print(yaml.__version__)'  # PyYAML, pip --user is fine
command -v herdr && herdr --version                # the Herdr CLI
ls -l ~/.local/bin/herdr-app ~/.local/bin/herdr-core   # the Herdr desktop app
command -v pi; command -v claude                   # at least one runtime
```

If PyYAML is missing: `python3 -m pip install --user pyyaml`.
If `herdr-app` or `herdr-core` is missing, the Herdr desktop app is not installed:
say so and stop. Neither this skill nor the installer can install the app.

## 2. Get the harness repository

```bash
git clone -b feat/app-team-staffing-gate \
  https://git-lab.apthai.com/ap-martech/web-apthai/project-scaffold.git \
  ~/Workspaces/project-scaffold
```

That branch carries the harness; `main` does not. Use an existing clone if one is
already checked out there — run `git -C ~/Workspaces/project-scaffold log -1` and
confirm it is the branch above, not another feature branch.

No GitLab access means no install. This repository is private and on-premise;
there is no public mirror to fall back to.

## 3. Install the skill layer first

```bash
npx skills add tomozard/agent-skills/skills/herdr-agent-team -g -a '*'
npx skills add tomozard/agent-skills/skills/hteam -g -a '*'
```

The installer refuses to run without this: it needs
`~/.agents/skills/herdr-agent-team/scripts/{workflow-shape,task-board}` and will
print the same command if either is missing. It is expected that two agent slots
fail with "does not support global skill installation" — that is not an error.

## 4. Install the runtime

```bash
cd ~/Workspaces/project-scaffold && ./setup_harness.sh
```

It validates the repository first (`tests/validate.sh`, a few minutes), then
installs 55 artifacts: 15 binaries in `~/bin` (including the `hteam` symlink), the
role prompts in `~/.agents/agents`, `team.json` linked to the canonical file, the
guard binaries, the extensions, the Claude agent definitions, `/hteam` for Pi, and
the voice scripts.

## 5. Verify before telling the Human it worked

```bash
cd ~/Workspaces/project-scaffold && ./uninstall.sh --check   # expect: 55 artifacts
readlink ~/.agents/team.json                                  # expect the agent-skills config
command -v hteam && hteam check                               # expect: check passed
```

`uninstall.sh --check` exits 1 while artifacts exist — that is the pass condition
here. `hteam check` needs Herdr.app running; if it reports the app window is not
reachable, open the app and re-run instead of reporting a broken install.

Also confirm `~/bin` is on `PATH` (`case ":$PATH:" in *":$HOME/bin:"*)`). The
installer does not edit shell profiles; add `export PATH="$HOME/bin:$PATH"` to
`~/.zshrc` if it is missing, then open a new shell.

## 6. Failure modes

| Symptom | Cause | Action |
|---|---|---|
| `the agent-skills tooling is missing` | step 3 skipped | run the `npx skills add` command it prints |
| `PyYAML is missing` | pip dependency absent | `python3 -m pip install --user pyyaml` |
| `clickup-watch tests failed` | older clone without the PyYAML gate | pull the branch, then re-run |
| `coder cannot start on protected branch` | dispatch without `--work-branch` | pass the branch from the scope lock |
| `unknown argument: --task-class` | `~/bin` holds an older dispatch/spawner | re-run `./setup_harness.sh` |
| `herdr app window is not reachable` | Herdr.app closed | open the app, re-run `hteam check` |

## 7. Remove it

```bash
cd ~/Workspaces/project-scaffold && ./uninstall.sh          # 55 artifacts
npx skills remove herdr-agent-team hteam -g -y              # skill layer
rm -f ~/.hermes/skills/{herdr-agent-team,hteam}             # Hermes symlinks
```

`uninstall.sh` never deletes `{workspace}/.agents/task-board` (durable task state)
or `~/.config/herdr-team/clickup-watch.yaml` (machine config).
