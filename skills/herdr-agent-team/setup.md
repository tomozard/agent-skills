# setup.md — install the Herdr agent-team harness

Read this only when `command -v hteam` prints nothing, or when the Human asks to
install, repair or reinstall the team. Everything below is a command to run, not a
description to summarise: run each step and report the output you actually got.

This skill is self-contained. The launcher, the 12 role prompts, the guard
binaries, the extensions and the voice scripts ship inside it under `harness/`,
so `npx skills add` is the only download involved — there is no second repository
to clone.

## Hard rules

- Never copy files into `~/bin`, `~/.agents/agents`, `~/.agents/extensions`,
  `~/.claude/agents` or `~/.pi` by hand. Run the installer; a hand-copied file
  differs from the installed one and every later verification lies about it.
- Never edit anything under `~/.agents/skills/herdr-agent-team/`. `npx skills`
  overwrites that directory on the next update; change the skill repository
  instead.
- Never run the uninstaller from inside a team role pane (`HERDR_AGENT_ROLE` is
  set). It removes the binaries that pane is running from.
- If a step fails, stop and report the exact stderr. The installer refuses for a
  reason (missing prerequisite, missing skill scripts), and a second guess is how
  an install half-lands.

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
say so and stop. Nothing in this skill can install the app.

## 2. Install the skill — this also delivers the harness payload

```bash
npx skills add tomozard/agent-skills/skills/herdr-agent-team -g -a '*'
npx skills add tomozard/agent-skills/skills/hteam -g -a '*'
```

Expect two agent slots to fail with "does not support global skill installation"
— that is not an error. Confirm the payload arrived:

```bash
ls ~/.agents/skills/herdr-agent-team/harness/bin/agent-runtime
ls ~/.agents/skills/herdr-agent-team/scripts/workflow-shape
```

## 3. Install the runtime

```bash
cd ~/.agents/skills/herdr-agent-team/harness && ./setup_harness.sh
```

The installer validates the payload first (`tests/validate.sh`, a few minutes),
then installs 55 artifacts: 15 binaries in `~/bin` (including the `hteam`
symlink), the role prompts in `~/.agents/agents`, `team.json` linked to the
canonical config, the guard binaries, the extensions, the Claude agent
definitions, `/hteam` for Pi, and the voice scripts.

## 4. Verify before telling the Human it worked

```bash
cd ~/.agents/skills/herdr-agent-team/harness && ./uninstall.sh --check   # expect 55
readlink ~/.agents/team.json                                  # expect the agent-skills config
command -v hteam && hteam check                               # expect: check passed
```

`uninstall.sh --check` exits 1 while artifacts exist — that is the pass condition
here. `hteam check` needs Herdr.app running; if it reports the app window is not
reachable, open the app and re-run instead of reporting a broken install.

Also confirm `~/bin` is on `PATH` (`case ":$PATH:" in *":$HOME/bin:"*)`). The
installer does not edit shell profiles; add `export PATH="$HOME/bin:$PATH"` to
`~/.zshrc` if it is missing, then open a new shell.

## 5. Failure modes

| Symptom | Cause | Action |
|---|---|---|
| `the agent-skills tooling is missing` | step 2 skipped or half-installed | re-run the `npx skills add` command |
| `PyYAML is missing` | pip dependency absent | `python3 -m pip install --user pyyaml` |
| `clickup-watch tests failed` | PyYAML absent but the gate was bypassed | install PyYAML, re-run |
| `missing role file` | step 3 not run, or run from the wrong directory | `cd ~/.agents/skills/herdr-agent-team/harness && ./setup_harness.sh` |
| `coder cannot start on protected branch` | dispatch without `--work-branch` | pass the branch from the scope lock |
| `unknown argument: --task-class` | `~/bin` holds older binaries | re-run step 3 |
| `herdr app window is not reachable` | Herdr.app closed | open the app, re-run `hteam check` |

## 6. Update or remove

```bash
# update
npx skills update herdr-agent-team hteam -g -y
cd ~/.agents/skills/herdr-agent-team/harness && ./setup_harness.sh

# remove
cd ~/.agents/skills/herdr-agent-team/harness && ./uninstall.sh   # 55 artifacts
npx skills remove herdr-agent-team hteam -g -y
rm -f ~/.hermes/skills/{herdr-agent-team,hteam}                  # Hermes symlinks
```

`uninstall.sh` never deletes `{workspace}/.agents/task-board` (durable task
state) or `~/.config/herdr-team/clickup-watch.yaml` (machine config). The ClickUp
intake watcher also needs `workspace_id` set in that config; the shipped default
is empty on purpose.
