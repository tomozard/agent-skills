---
title: Agent install
---

# Agent install runbook

You are an agent installing the Herdr Agent Team on a Human's Mac. This page is
self-contained: follow it in order, stop at the first hard failure, and report
what you saw. Do not improvise around a failed step — the installer and the
checks are the contract.

Back to the [human guide](index.html).

## Ground rules

1. **Install through the installer.** Never copy files into `~/.agents`,
   `~/.claude`, `~/.pi`, or `~/bin` by hand. The installer maintains manifests and
   removes stale copies; a hand copy breaks `hteam check --deep`.
2. **Never edit the installed skill tree** (`~/.agents/skills/herdr-agent-team/`).
   `npx skills` overwrites it. Change the repository or the config files named
   here.
3. **Never invent a model identifier.** Models come from the allowlist in
   `team.json`; the resolver refuses anything else.
4. **Do not change routing, scope, or commit settings** as part of an install.
   Those are the Human's decisions.
5. **Ask before writing outside the expected locations**, and ask before removing
   anything.
6. **`HERDR_ENV=1` is required** before any Herdr control command, and only panes
   inside Herdr may run them. The launcher is the only startup exception.

## Step 0 — Herdr, then preflight

Herdr is a separate product and this skill never installs it. If it is missing,
give the Human the download page (<https://herdr.dev/download/>) and the official
one-liner — macOS/Linux `curl -fsSL https://releases.herdr.dev/app/install.sh | sh`,
Windows `irm https://releases.herdr.dev/app/install.ps1 | iex` — then stop until
they confirm it is installed and opened once.

`npx … --yes` enforces this itself: it prints `herdr-install: preflight`, and a
`MISS` line stops it with exit `3` before anything is written. `--allow-no-herdr`
is the only way past it, and it is for a machine that is being prepared.

Run the preflight below only after that.

Run all of it, then report every failure together. Do not start installing until
the block is clean.

```bash
uname -s                                  # must print Darwin
ls -l ~/.local/bin/herdr-app ~/.local/bin/herdr-core
pi --version
claude --version                          # recommended, not strictly required
node --version                            # >= 18, for npx
python3 -c 'import yaml; print("pyyaml ok")'
git --version
case ":$PATH:" in *":$HOME/bin:"*) echo "PATH ok";; *) echo "PATH missing ~/bin";; esac
```

| Result | Meaning | Action |
|---|---|---|
| `uname -s` is not `Darwin` | this harness is macOS-only today (Herdr itself also runs on Linux and Windows) | stop; report that the harness needs macOS |
| `herdr-app` or `herdr-core` missing | Herdr is not installed, or was never opened | give the Human <https://herdr.dev/download/>; macOS/Linux `curl -fsSL https://releases.herdr.dev/app/install.sh \| sh`, Windows `irm https://releases.herdr.dev/app/install.ps1 \| iex`; open Herdr once; stop until both binaries exist |
| `pi` missing | the Orchestrator and PM run on Pi | stop; ask the Human to install and authenticate Pi |
| `claude` missing | critical routes lose their primary | continue, but tell the Human: some `critical` work will be `[STUCK]` |
| node < 18 | `npx` cannot install the skill layer | stop; ask for a Node upgrade |
| PyYAML import fails | the tools cannot parse config | run `python3 -m pip install --user pyyaml`, retry |
| `PATH missing ~/bin` | installed commands will not be found | add `export PATH="$HOME/bin:$PATH"` to the Human's shell rc, open a new shell |

## Step 1 — Install

```bash
npx -y github:tomozard/agent-skills --yes
```

`--yes` is required; without it the wrapper prints the plan and exits 1. The
command runs the skill layer, then the runtime installer, then `hteam check --deep`.
Expect the tail to look like:

```text
Installation complete
  ok:   deep check passed
herdr-install: done — run 'hteam' to open a team, or '/hteam setup' in Pi
```

If the installer stops on its own validation suite, read the `FAIL` line before
doing anything else. Do not add `--skip-validate` to get past a real failure; that
flag exists only for a machine whose `team.json` was deliberately customised.

## Step 2 — Verify

```bash
command -v hteam
hteam check --deep
```

Acceptance: the command exists and the check ends with `deep check passed`. A
`MISS` line names a missing artifact (re-run the installer). A `STALE` line means
the installed copy is older than the payload (also re-run the installer).

## Step 3 — Configure (ask the Human)

Ask these four questions, one at a time. Use the answers verbatim.

1. Which folder holds the projects the team may work on? (suggest `~/Workspaces`)
2. Where should the long-term notes and activity journal live? (suggest
   `~/Workspaces/vault`)
3. Voice status speech on or off? (suggest `off` until the Human has heard it)
4. Which runtime is primary, `pi` or `claude`? (suggest `pi` — the fixed roles use
   Pi)

Apply them:

```bash
hteam-config set folder "<folder>" vault "<vault>" activity_log "<vault>/log.md" voice "<on|off>" repo "$HOME/.agents/skills/herdr-agent-team/harness"
hteam-config set space "Herdr Team"
hteam-config validate
hteam-config show
```

Only run `mkdir -p "<vault>"` and create `"<vault>/log.md"` if the Human agrees.
`hteam-config` refuses an invalid value before writing; if it refuses, report the
message rather than retrying with a guessed value.

## Step 4 — Register projects (ask the Human)

Never write the registry from guesswork. Show candidates, then ask which ones to
register with a one-line description each.

```bash
REG="$(hteam-config show --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["registry"])')"
find "<folder>" -maxdepth 3 -name .git -type d -not -path '*/.git/*' | sed 's|/.git$||' | sort
```

Then, with the Human's confirmed list, back up and append — never overwrite:

```bash
mkdir -p "$(dirname "$REG")"
[ -f "$REG" ] && cp "$REG" "$REG.bak-$(date +%Y%m%d-%H%M%S)"
```

Registry shape (one block per project, merge into the existing `projects:` map):

```yaml
projects:
  smart_ai:
    name: smart-ai
    path: /Users/you/Workspaces/smart-ai
    description: Customer-facing assistant
    status: active
    repos: {}
```

Validate what you wrote:

```bash
python3 -c 'import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));print("projects:",len(d["projects"]))' "$REG"
```

Two names that normalise to the same lowercase snake_case slug is a hard stop:
ask the Human which one to keep.

## Step 5 — Start the team

```bash
hteam check          # prerequisites only; must pass before starting
hteam                # start the Orchestrator in the Herdr app
```

Expected: the Orchestrator opens in the control space, lists the registered
projects in Thai, and asks which project to open. Tell the Human to continue in
the **`pm-{project}`** pane after the handoff — the Orchestrator is bootstrap only.

Do not start a second team from a pane that already runs a role; that launch is
refused on purpose.

## Step 6 — Hand off

Report back, in the Human's language, with: what was installed, the resolved
config (`hteam-config show`), the registered projects, and the exact command that
failed if anything did.

Handoff message template (Thai):

```text
ติดตั้ง harness เรียบร้อยแล้วค่ะ
- คำสั่ง: hteam, hteam-config, workflow-shape, task-board, roster
- ตรวจสอบ: hteam check --deep ผ่าน
- config: space=Herdr Team, folder=…, vault=…
- โปรเจกต์ที่ลงทะเบียน: …
ขั้นต่อไป: พิมพ์ hteam เพื่อเปิด Orchestrator แล้วเลือกโปรเจกต์
```

## Failure handling

| Symptom | Cause | Action |
|---|---|---|
| `PyYAML is missing` | interpreter without PyYAML | `python3 -m pip install --user pyyaml`, re-run |
| `herdr-app not found`, or the installer's preflight exits 3 | Herdr absent or not opened | stop, give the Human <https://herdr.dev/download/> and the installer line from Step 0; never pass `--allow-no-herdr` to get past this |
| `Herdr app window is not reachable` | app closed | open Herdr.app, re-run `hteam check` |
| `pi CLI not found` | no Pi runtime | stop, ask the Human |
| `the agent-skills tooling is missing` | skill layer not installed | run `npx skills add tomozard/agent-skills/skills/herdr-agent-team -g -y -a pi claude-code`, then the installer |
| `[STUCK] no launchable pair` | no installed, enabled, allowlisted model on that route | report the role and tier; do not substitute a model |
| `deep check failed` with `MISS` | artifact missing | re-run the installer |
| `Already inside a team terminal` | the pane runs a role | talk to that role's controller |

Stop and ask the Human when: Herdr or Pi is missing, the registry is ambiguous,
a routing check returns `[STUCK]`, or a step would write outside `$HOME`.

## Rollback

```bash
~/.agents/skills/herdr-agent-team/harness/uninstall.sh --dry-run
~/.agents/skills/herdr-agent-team/harness/uninstall.sh
npx skills remove herdr-agent-team -g -y
```

It never deletes projects, the task board, the registry, the vault, or
`~/.config/herdr-team/setup-answers.md`.
