---
title: Guide
---

# Herdr Agent Team

A delivery team of AI agents for real repositories. The point is not more agents —
it is that **staffing, scope, and the commit gate are decided by rules instead of
by whoever is holding the conversation**.

- **Staffing is resolved, not negotiated.** One intake file maps to one of eleven
  shapes (`W0`–`W10`), and a role the shape does not staff is a refused launch.
- **A commit needs a verified diff.** The Worker freezes the staged diff to a
  SHA-256, an independent Verifier passes that exact hash, and only then may a
  commit helper create the commit.
- **The Human keeps four tokens.** Scope, commit, push, and PR. Everything else
  is routine, reversible execution.

This page is the whole operating guide. If you are an agent asked to install the
team, read **[Agent install](agent-install.html)** instead — it is the runbook.

## Contents

1. [Requirements](#requirements)
2. [Install](#install)
3. [Configure](#configure)
4. [Open a team](#open-a-team)
5. [Hand it to your agent](#hand-it-to-your-agent)
6. [What the harness is made of](#what-the-harness-is-made-of)
7. [The team: 12 roles, 11 shapes](#the-team-12-roles-11-shapes)
8. [Routing and models](#routing-and-models)
9. [Daily use](#daily-use)
10. [Troubleshooting](#troubleshooting)
11. [Full docs and known gaps](#full-docs-and-known-gaps)

---

## Requirements

| Requirement | Why | Check |
|---|---|---|
| Herdr installed and opened once | the app plus `herdr-app` and `herdr-core`; Herdr itself ships for macOS, Linux, and Windows — [herdr.dev/download](https://herdr.dev/download/) | `ls -l ~/.local/bin/herdr-app ~/.local/bin/herdr-core` |
| macOS | this harness is macOS-only today: bash launchers, `~/bin` PATH, and the voice helper (`afplay`) | `uname -s` |
| Pi, authenticated | **required** — the Orchestrator and PM run on Pi, and the launcher refuses to start without it | `pi --version` |
| Claude Code, authenticated | recommended — several `critical` routes have no Pi alternate | `claude --version` |
| Node.js 18+ | `npx` installs the skill layer | `node --version` |
| Python 3 with PyYAML | the tools (`roster`, `workflow-shape`, `task-board`) and ClickUp helpers | `python3 -c 'import yaml'` |
| git | scope lock, diff freeze, guards | `git --version` |
| `~/bin` on `PATH` | installed commands land there | `case ":$PATH:" in *":$HOME/bin:"*) echo ok;; esac` |

Install both runtimes where you can: a writer and its verifier must not share a
model, and two runtimes make that easy.

If PyYAML is missing:

```bash
python3 -m pip install --user pyyaml
```

## Install

### Step 0 — Herdr

The team runs inside the Herdr desktop app, so install it first. It is free,
open source, and self-updating; one line installs the app and `herdr-core`:

```bash
# macOS / Linux
curl -fsSL https://releases.herdr.dev/app/install.sh | sh

# Windows (PowerShell) — Herdr runs there, this harness does not (yet)
irm https://releases.herdr.dev/app/install.ps1 | iex
```

Or download the app: <https://herdr.dev/download/>. Nothing in this skill installs
Herdr for you: the installer's preflight and `hteam check` name the download page
and stop.

Check the whole host with one read-only command (it installs nothing):

```bash
npx herdr-agent-team health
```

Then open Herdr once. `~/.local/bin/herdr-app` and `~/.local/bin/herdr-core` must
both exist. `npx … --yes` verifies this before it writes anything:

```text
herdr-install: preflight
  ok:   herdr-app 0.1.16 (/Users/you/.local/bin/herdr-app)
  ok:   herdr-core 0.1.21 (/Users/you/.local/bin/herdr-core)
```

If either line is `MISS`, the installer prints the two commands above and exits
`3` without touching `$HOME`. `--allow-no-herdr` installs the harness anyway, for a
machine that is being prepared.

### Step 1 — the team

**One command.** It runs the policy layer, then the runtime layer, then a deep
check:

```bash
npx -y herdr-agent-team@latest --yes
```

Pinned: `npx -y herdr-agent-team@0.2.0 --yes`. Straight from the repository:
`npx -y github:tomozard/agent-skills --yes`.

What that does, in order:

1. `npx skills add tomozard/agent-skills/skills/herdr-agent-team -g -y -a pi claude-code`
   — the skill: policy, references, the resolver and the task board.
2. `~/.agents/skills/herdr-agent-team/harness/setup_harness.sh`
   — the runtime: 18 commands into `~/bin`, 12 role files, 5 Pi extensions, Claude
   agent files, guards, `team.json`, and a `/hteam` command for Pi.
3. `hteam check --deep` — verifies every installed artifact against the payload.

The skills CLI copies files and cannot run install scripts, which is why the
wrapper exists. If you prefer to see each phase, run the two commands yourself:

```bash
npx skills add tomozard/agent-skills/skills/herdr-agent-team -g -y -a pi claude-code
~/.agents/skills/herdr-agent-team/harness/setup_harness.sh
```

Useful flags on the wrapper: `--dry-run` (print the plan only), `--skip-validate`
(skip the test suite — only after machine-local routing edits), `--yes` (required;
without it, the wrapper prints the plan and stops).

### Verify

```bash
command -v hteam
hteam check --deep
```

A healthy install ends with `deep check passed`. `MISS` means an artifact is
missing — re-run the installer. `STALE` means the installed copy is older than
the payload — also re-run the installer.

### Uninstall

```bash
~/.agents/skills/herdr-agent-team/harness/uninstall.sh --dry-run
~/.agents/skills/herdr-agent-team/harness/uninstall.sh
npx skills remove herdr-agent-team -g -y
```

It never deletes your projects, `{folder}/.agents/task-board`, the workspace
registry, the vault, or `~/.config/herdr-team/setup-answers.md`.

---

## Configure

`hteam setup` is the guided path. It checks the host first (`health --json`), asks
only what it cannot detect, and writes through `hteam-config`, so nothing is
hand-edited:

```bash
hteam setup                 # interactive
hteam setup --dry-run       # print the writes
hteam setup --defaults      # recommended answers, no prompts
hteam setup --only vault    # one step
hteam setup --projects all  # register every git repository under the folder
```

It refuses to run on a host that cannot start the team (exit `3`), never
overwrites a registered project, and keeps a backup of the registry before
writing it.

The same values by hand:

```bash
hteam-config show          # effective values and where each came from
hteam-config set voice on
hteam-config validate
hteam-config path
```

| Key | Env var | Default | Meaning |
|---|---|---|---|
| `space` | `HERDR_TEAM_SPACE` | `Herdr Team` | the control space that holds the Orchestrator |
| `folder` | `HERDR_TEAM_CWD` | `~/Workspaces` | where team terminals start |
| `voice` | `HERDR_VOICE_MODE` | `off` | short Thai status speech from Orchestrator and PM |
| `repo` | `HERDR_TEAM_REPO` | detected | the installed harness the launcher runs |
| `registry` | `HERDR_TEAM_REGISTRY` | `{folder}/.agents/workspace-registry.yaml` | the project index |
| `vault` | `HERDR_TEAM_VAULT` | `{folder}/vault` | long-term notes and the activity journal |
| `activity_log` | `HERDR_TEAM_ACTIVITY_LOG` | `{vault}/log.md` | where Documenter appends completion entries |

Precedence is **flag > env > file > default**. An invalid value is refused before
anything is written.

### The project registry

`{workspaces_root}/.agents/workspace-registry.yaml` is the canonical index. The
Orchestrator and every PM resolve projects through it — **an unregistered project
cannot be started**.

```yaml
projects:
  smart_ai:
    name: smart-ai
    path: /Users/you/Workspaces/smart-ai
    description: Customer-facing assistant
    status: active
    repos:
      api:
        path: /Users/you/Workspaces/smart-ai/api
        tech_stack: [go, postgres]
        description: Public API
```

A display name may contain hyphens; the runtime **slug** is lowercase snake_case
(`ap-bootcamp` becomes `ap_bootcamp`). If two names normalize to the same slug,
stop and ask the Human — do not pick one.

---

## Open a team

```bash
hteam                 # start (or report) the Orchestrator in the Herdr app
hteam check           # validate prerequisites only, change nothing
hteam --voice on      # speak short Thai status from Orchestrator and PM
hteam --space "Herdr Team"
hteam --folder ~/Workspaces
```

What happens next: the Orchestrator lists your registered projects in Thai, you
pick one (or ask for a new one), and it opens that project's space, labels the tab
`manager-{project}`, and starts a PM at `pm-{project}`. **After that you talk to
the PM**, not the Orchestrator — the PM owns scope, staffing, gates, and reporting
for its project.

One project gets exactly one PM. A second PM in the same project is refused, and
`--force` is a Human repair for a genuinely stuck PM, not a routine path.

## Hand it to your agent

Give your agent a URL, not a transcript:

- **[Agent install](agent-install.html)** — a self-contained runbook: preflight,
  exact commands, acceptance evidence, failure handling. Source:
  [`docs/agent-install.md`](https://github.com/tomozard/agent-skills/blob/main/docs/agent-install.md).
- **[llms.txt](llms.txt)** — the same entry points in the machine-readable
  [llms.txt](https://llmstxt.org/) format.
- **`SKILL.md`** — the full policy, linked below.

Five rules an installing agent must not break:

1. Install through the installer only. Never copy files into `~/.agents`,
   `~/.claude`, `~/.pi`, or `~/bin` by hand.
2. Never edit anything under `~/.agents/skills/herdr-agent-team/` — the skills CLI
   overwrites it. Change the repository or the config files.
3. Never invent a model identifier. Models come from the allowlist in
   `team.json`, and the resolver refuses anything else.
4. `HERDR_ENV=1` is required before any Herdr control command, and only panes
   inside Herdr may run them.
5. Ask the Human before anything that changes routing, expands scope, or writes
   outside the expected locations.

---

## What the harness is made of

The harness shares nine contracts, not one binary. Knowing which contract you are
editing is what keeps the two runtimes honest.

```text
                    ┌──────────────────────────┐
                    │  team.json (canonical)   │  routing + authority of 12 roles
                    └────────────┬─────────────┘
        ┌───────────────┬────────┴────────┬────────────────┐
   agent-runtime   spawn-agent    herdr-app-spawn-role   roster / workflow-shape
        │                                                  │
        └────────────► env HERDR_* (about 27 vars) ◄───────┘
                            │
        ┌───────────────────┼─────────────────────┐
   guard-bin (git/gh/glab)  extensions (Pi)   agent-helpers.sh (roles)
```

| Contract | Lives at | Consumed by | Change it by |
|---|---|---|---|
| `team.json` | `~/.agents/team.json`, generated from `config/team.json` plus `~/.config/herdr-team/team.local.json` | every launcher, spawner, `roster`, `workflow-shape`, guards, PM/Supervisor prompts | editing the file, then `roster ROLE TIER` to prove it resolves |
| Role text | `~/.agents/agents/<role>.md`, `~/.claude/agents/herdr-<role>.md` | Pi (system prompt) and Claude (custom agent) | changing the repository and re-running the installer |
| `agent-helpers.sh` | `~/.agents/skills/agent-shared/lib/` | every role: `[ACK]`/`[STATUS]`/`[DONE]`/`[STUCK]`, `agent_pass`, the hash-bound commit gates | it ships with the skill |
| Guards | `~/.agents/guard-bin/{git,gh,glab}` | every role that runs Git or a forge command | driven by `HERDR_*` policy env, not edited locally |
| Env contract | exported by the launchers | guards, extensions, helpers | it is derived from `team.json` |
| State + manifests | `~/.local/state/herdr-app-team/`, `{folder}/.agents/task-board`, `~/.agents/project-scaffold-*.txt` | launcher, spawner, installer, `check --deep` | the installer and the tools own these |
| Voice | `~/.config/herdr/voice-owner`, `voice-notify.log`, `tts-thai.sh` | Orchestrator and PM only | `hteam --voice on`, `hteam-config set voice on` |
| Vault | configured `vault` + `activity_log` | Investigator (scoped read), Documenter (journal write) | `hteam-config set vault … activity_log …` |
| Project setup | the registry, one space per project, one PM per project | Orchestrator, spawner, PM | `hteam-config` and the registry file |

Known gap, being closed: `hteam check` validates installation, not this table.
Seven of the nine contracts have no automated health check today — see
[known gaps](#full-docs-and-known-gaps).

---

## The team: 12 roles, 11 shapes

Three authority layers plus an optional controller:

| Layer | Roles | May | May not |
|---|---|---|---|
| bootstrap | `orchestrator` | registry, harness, project/PM lifecycle, cross-project, shutdown | take over discovery, planning, or implementation after handoff |
| project owner | `pm` | own one project's scope, staffing, gates, reporting | write repository files; verify its own work |
| optional controller | `supervisor` | workers and verifiers for full / multi-worker / revision loops | cross Human gates; invent scope |
| planner | `sa`, `investigator`, `researcher`, `designer` | read; produce specs, evidence, designs | write the spec or repository; assign work; mutate a vault |
| worker | `coder`, `refactor` | edit only `Allowed files`; freeze a candidate; commit after the token | edit outside scope; commit without a verified hash |
| verifier | `reviewer`, `tester` | one hash-bound verdict on the frozen diff | implement what they verify; instruct other agents |
| document | `documenter` | write only the approved Markdown/text/note files | mutate Git |

The shape decides who works, from one intake file:

| Shape | Selected when | Staff | Verifiers |
|---|---|---|---|
| `W0-answer` | advisory only, no repository write | — | — |
| `W1-doc` | documentation-only change | documenter | reviewer when policy or security |
| `W2-micro` | deterministic micro diff, no behavior change | coder | — (task-board proof) |
| `W3-fix` | known-cause fix, acceptance not runnable | coder | reviewer |
| `W4-fix-test` | known-cause fix with runnable acceptance | coder | tester |
| `W5-refactor` | structural cleanup, no behavior change | refactor | reviewer |
| `W6-fix-refactor` | fix whose root cause is structural | coder, refactor (serial) | reviewer, tester |
| `W7-feature` | new behavior; specification first | sa (+ designer/researcher), coder | reviewer, tester |
| `W8-investigate` | cause or scope unknown | investigator | — |
| `W9-ops` | operational change, no source behavior change | coder | reviewer |
| `W10-deliver` | commit/push/PR of a verified increment | — | — |

`minimal`, `focused`, and `full` are staffing modes; `direct` and `supervised` are
execution paths. PM chooses both and records why. Raising the shape once needs a
written reason; a second raise is the Human's decision.

### Local roles

A brand-new role belongs in this repository, with tests and a reviewed shape
membership. When a machine only needs a variant of a contract it already has,
`hteam agent` clones one into a local role:

```bash
hteam agent --add security_reviewer --from reviewer --shapes W3-fix,W7-feature
hteam agent --list
hteam agent --remove security_reviewer
```

A clone cannot invent authority: it copies the base contract, is pinned to one
model, and may only be staffed by shapes you name. A cloned planner never gains
write access, a controller is not cloneable, and removing it deletes the role
text, the Claude agent file, and every overlay entry.

The role text lives in `~/.config/herdr-team/roles/<name>.md`; the resolver reads
its shape membership from `local_roles` in `team.local.json`, so an undeclared
shape cannot staff it.

## Routing and models

`team.json` (schema v4) is the only source of model identifiers. A role is either
`fixed` or `controller`-selected, and controller-selected roles route by tier:

```json
"coder": {
  "repo_mode": "write",
  "may_local_commit": true,
  "may_authorized_push": true,
  "may_authorized_pr_create": true,
  "model_selection": "controller",
  "models": {
    "pi": ["opencode-go/deepseek-v4.1-flash", "antigravity/gemini-3.8-flash"],
    "claude": ["opus", "fable"]
  },
  "routing": {
    "standard": {
      "primary": { "runtime": "pi", "model": "opencode-go/deepseek-v4.1-flash" },
      "alternates": [
        { "runtime": "claude", "model": "fable" },
        { "runtime": "pi", "model": "antigravity/gemini-3.8-flash" }
      ]
    },
    "critical": {
      "primary": { "runtime": "claude", "model": "opus" },
      "alternates": [
        { "runtime": "claude", "model": "fable" },
        { "runtime": "pi", "model": "opencode-go/deepseek-v4.1-flash" }
      ]
    }
  }
}
```

Rules the resolver enforces and a plan may not override:

1. **Allowlist only.** A model that is not in `roles.<role>.models.<runtime>` is
   refused, not normalized.
2. **Alternates stay in the tier.** An unavailable primary may fall to that tier's
   alternates, and the fallback reason is recorded.
3. **Never self-verify.** A writer and its verifier must not share a model; on
   collision the resolver tries an alternate, then a tier raise, then another
   verifier role, and otherwise returns `blocked`.
4. **Nothing usable is `[STUCK]`.** Do not substitute a model from another tier or
   runtime to make it run.
5. **Tiers are two.** `standard` (score 0–7) and `critical` (8–10). Security,
   authentication, payments, destructive data changes, migrations, production
   infrastructure, and cross-repository work always land in `critical`.

### Pin a model without editing the shipped file

`config/team.json` is replaced by every `npx skills update`, so it is not where a
machine-specific choice belongs. The effective roster is **canonical + overlay**:

| File | Owner | Survives an update |
|---|---|---|
| `~/.agents/skills/herdr-agent-team/config/team.json` | the repository | replaced |
| `~/.config/herdr-team/team.local.json` | this machine | yes |
| `~/.agents/team.json` | generated (canonical + overlay) | re-rendered |

```bash
hteam model                                   # table, then an interactive edit
hteam model --json                            # where each role/tier resolves
hteam model --set coder critical pi antigravity/gemini-3.8-flash
hteam model --unset coder critical
hteam model --reset                           # back to the shipped roster
hteam model --allow-model claude fable        # extend an allowlist deliberately
```

Every write goes to the overlay, re-renders the effective roster, and is kept only
if `team-config validate` still resolves all 24 role/tier routes. A refused write
restores the previous overlay. Tools the wizard uses directly:

```bash
team-config paths          # base, overlay, effective, stale?
team-config show --json    # the merged roster
team-config validate       # every role x tier
team-config reset          # drop the overlay and re-render
```

> Sharing a model between a writer and its verifier is allowed in the shipped
> roster — the resolver substitutes an alternate or raises the tier — so
> `hteam model` prints a note rather than refusing. `disabled_model_providers`
> still needs an enabled alternate on every route that used it.

---

## Daily use

| Command | What it does |
|---|---|
| `hteam` | start or report the Orchestrator in the app |
| `hteam check`, `hteam check --deep` | prerequisites, then installed-artifact integrity |
| `hteam health`, `hteam health --json` | readiness: host, Herdr, runtimes, install, routing, vault, voice — exit `3` when the host cannot run the team |
| `hteam setup` | guided: Herdr check → folder → vault → projects → voice; `--defaults`, `--dry-run`, `--only`, `--projects all\|none` |
| `hteam model` | show/pin routing in `team.local.json`, re-render, validate |
| `hteam agent` | list/add/remove a machine-local role cloned from a built-in contract |
| `hteam-config show`, `set`, `validate` | read and write per-machine config |
| `hteam-dispatch <role> --brief F --request "…" --risk low` | one call: intake → shape → spawn, and it refuses a role the shape does not staff |
| `hteam-dispatch --explain --request "…" --risk low` | print the resolved shape without spawning |
| `hteam-config path` | print the config file in use |
| `workflow-shape --list` | print the shape catalogue |
| `workflow-shape --intake task.json --format text` | resolve one intake |
| `task-board create`, `show`, `list`, `event`, `transition` | the durable task board |
| `roster ROLE TIER` | resolve runtime and model for a role and tier |
| `runtime-probe` | which agent CLIs this machine has, and which verbs they support |
| `clickup-status check`, `ask`, `mark`, `status` | keep a ClickUp task in step (Human-run helper) |
| `validate-okf [ROOT]` | validate the OKF contract of Markdown files |
| `hteam-shutdown` | close the team's panes (Orchestrator pane last) |

Workers, verifiers, and planners are spawned by their controller — you do not run
them by hand.

### The commit gate

```text
Worker edits Allowed files
  → agent_prepare_verification_candidate   freezes the staged diff to a SHA-256
  → independent Verifier PASS on that hash
  → agent_prepare_commit_review            re-hashes the frozen index
  → APPROVE_COMMIT (manual) or AUTO_COMMIT (pre-approved at scope)
  → agent_authorized_commit / agent_auto_commit
  → helper compares the created commit to the verified hash   (integrity check)
```

Any branch, index, diff, or message change invalidates every earlier verdict and
requires fresh verification. Raw `git commit` is blocked by the guard.

### Human tokens

| Gate | Token | Expires when |
|---|---|---|
| Scope and work branch | approval of the plan; may include `AUTO_COMMIT` for the later commit only | scope changes |
| Local commit | `APPROVE_COMMIT` | branch, index, diff, or message changes |
| Branch push | `APPROVE_PUSH` | the current non-protected `HEAD` only |
| PR into `dev` | `APPROVE_PR_DEV` | exactly one PR from that branch |

Agents never update, close, merge, or review a PR, deploy, release, promote,
force-push, delete a branch, or tag.

---

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| installer stops: `PyYAML is missing` | no PyYAML for this account | `python3 -m pip install --user pyyaml`, re-run |
| `herdr-app not found` | Herdr not installed or never opened | install from <https://herdr.dev/download/> (or the one-liner in Step 0), open once, check `~/.local/bin/herdr-app` |
| `the Herdr app window is not reachable` | app closed | open Herdr.app and retry |
| `pi CLI not found` | no Pi runtime | install Pi, or make sure it is on `PATH` |
| `Already inside a team terminal` | the pane already runs a role | talk to that role's controller; do not open a second team |
| `[STUCK] no launchable pair` | the roster route has no installed, enabled, allowlisted model | fix `team.json` or install the runtime — never substitute a model |
| `check --deep` prints `MISS` / `STALE` | artifacts missing or older than the payload | re-run the installer |
| installer tests fail after local routing edits | the suite asserts the shipped model tables | re-run with `--skip-validate` |
| voice on but silent | no engine, or a dead owner lease | `voice-notify test`, check gTTS/VoiceStudio, restart the Orchestrator |
| Investigator is `[STUCK]` | vault path missing, or scope not a descendant of the vault root | check `hteam-config show`, pass a scope below the vault root |

---

## Full docs and known gaps

Authoritative, in the repository:

| Read | For |
|---|---|
| [SKILL.md](https://github.com/tomozard/agent-skills/blob/main/skills/herdr-agent-team/SKILL.md) | the policy entry point and the four rules |
| [setup.md](https://github.com/tomozard/agent-skills/blob/main/skills/herdr-agent-team/setup.md) | the interactive install phases, question by question |
| [references/launcher.md](https://github.com/tomozard/agent-skills/blob/main/skills/herdr-agent-team/references/launcher.md) | `hteam`, config keys, voice engine, failure modes |
| [references/team-at-a-glance.md](https://github.com/tomozard/agent-skills/blob/main/skills/herdr-agent-team/references/team-at-a-glance.md) | authority layers, delivery stages, shapes, Human gates |
| [references/workflow-shapes.md](https://github.com/tomozard/agent-skills/blob/main/skills/herdr-agent-team/references/workflow-shapes.md) | intake fields, tiers, escalation |
| [references/runtime-adapters.md](https://github.com/tomozard/agent-skills/blob/main/skills/herdr-agent-team/references/runtime-adapters.md) | the six runtime verbs and how each CLI is driven |
| [references/communication-protocol.md](https://github.com/tomozard/agent-skills/blob/main/skills/herdr-agent-team/references/communication-protocol.md) | messages, verdicts, dispatch accounting |
| [harness/README.md](https://github.com/tomozard/agent-skills/blob/main/skills/herdr-agent-team/harness/README.md) | the runtime payload and its architecture |
| [docs/releasing.md](https://github.com/tomozard/agent-skills/blob/main/docs/releasing.md) | how a release is cut, published, and picked up |

Known gaps, in priority order:

1. **`hteam health` follow-ups** — it covers the host, Herdr, runtimes, install,
   routing, workspace, and voice; a per-project scope and a `--fix` for missing
   artifacts are still open.
2. **`hteam model` follow-ups** — the overlay and the wizard exist; per-role
   prompt editing (not just routing) and an `--explain` diff are still open.
3. **`hteam agent` follow-ups** — cloning exists; editing the role text in place
   from the wizard, and generating the operator reference page, are still open.
4. **Project scope checks** — per-project health (registry entry, branch, task
   board, vault log) and a `hteam project` helper for the registry.

Contributions to any of these are welcome — the repository's test suite
(`skills/herdr-agent-team/harness/tests/validate.sh`) is the bar.
