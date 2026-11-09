# setup.md — install and configure the team (interactive)

Read this when `command -v hteam` prints nothing, or when the Human asks to
install, configure or repair the team. This is a conversation: ask the questions
in order, apply each answer with the command given, then move on. Do not batch the
questions and do not invent answers — every value here is the Human's choice.

The payload ships inside this skill under `harness/`; there is no second
repository to clone.

## Hard rules

- Never copy files into `~/bin`, `~/.agents/*`, `~/.claude/agents` or `~/.pi` by
  hand. Run the installer.
- Never edit anything under `~/.agents/skills/herdr-agent-team/` — `npx skills`
  overwrites it. Change the skill repository, or the config files named below.
- Ask one phase at a time. If the Human declines a phase, record the default you
  used and say so.
- ClickUp **auto-intake is out of scope in this phase.** Do not write
  `clickup-watch.yaml`, do not enable `--watch`, do not register ClickUp lists.
  Record only which tracker the Human uses (phase 6).

## Phase 1 — Herdr desktop app

```bash
command -v herdr && herdr --version
ls -l ~/.local/bin/herdr-app ~/.local/bin/herdr-core
```

If any of the three is missing, stop and tell the Human: the team runs inside the
Herdr desktop app and nothing in this skill installs it. Resume once the app is
installed and `~/.local/bin/herdr-app` exists.

## Phase 2 — which runtimes, and which one is primary

```bash
~/.agents/skills/herdr-agent-team/scripts/runtime-probe
```

That table is the ground truth for this machine. **Only `pi` and `claude` are
routable** — `agent-runtime --runtime pi|claude`; the other CLIs the probe lists
(`codex`, `opencode`, `kiro-cli`, `hermes`) are detected but cannot host a role
until an adapter exists. Say that plainly instead of offering them.

**Ask two things:**

1. Which runtimes should the team use — `pi`, `claude`, or both? (both is the
   practical default: a writer and its verifier must not share a model)
2. Which of those is the **primary/default** runtime — the one used when the tier
   does not override it, and the one fixed roles (`orchestrator`, `pm`) run on?

Then list the models for every enabled runtime:

```bash
# pi — the models enabled in this Pi installation
python3 -c 'import json,os;print("\n".join(json.load(open(os.path.expanduser("~/.pi/agent/settings.json")))["enabledModels"]))'

# claude — aliases accepted by `claude --model`
printf '%s\n' opus sonnet haiku
```

Write the answer — the **first** entry is the primary runtime:

```bash
CFG=~/.agents/skills/herdr-agent-team/config/team.json
[ -f ~/Workspaces/agent-skills/skills/herdr-agent-team/config/team.json ] && \
  CFG=~/Workspaces/agent-skills/skills/herdr-agent-team/config/team.json
python3 - "$CFG" <<'PY'
import json, sys
path = sys.argv[1]
team = json.load(open(path))
team["runtime_order"] = ["<primary>", "<other>"]   # e.g. ["claude", "pi"] or ["pi"]
# A fixed role needs a model in every enabled runtime, or the launcher cannot
# start it when the primary changes. Add the missing runtimes per role:
#   team["roles"]["orchestrator"]["models"]["claude"] = ["opus"]
#   team["roles"]["pm"]["models"]["claude"] = ["opus"]
json.dump(team, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["runtime_order"])' "$CFG"
```

If the Human picks `claude` as primary, every fixed role (`orchestrator`, `pm`,
`designer`) must gain a `models.claude` entry, otherwise the launcher reports
`cannot resolve a runtime` for that role.

## Phase 3 — model per tier

Two tiers exist and the resolver picks one per task:

| Tier | Used for | Expectation |
|---|---|---|
| `standard` | normal work | cheaper / faster model |
| `critical` | high risk, or when a writer and its verifier would collide | strongest model |

**Ask, per role group:** which `runtime/model` for `standard`, and which for
`critical`?

- writers: `coder`, `refactor`
- verifiers: `reviewer`, `tester` — must resolve to a different model than the
  writer that produced the diff, on both tiers
- controllers: `orchestrator`, `pm` — `model_selection: fixed`, set `default_model`

Apply the answers to the canonical config (a working clone if one exists, else the
installed skill):

```bash
CFG=~/.agents/skills/herdr-agent-team/config/team.json
[ -f ~/Workspaces/agent-skills/skills/herdr-agent-team/config/team.json ] && \
  CFG=~/Workspaces/agent-skills/skills/herdr-agent-team/config/team.json
python3 - "$CFG" <<'PY'
import json, sys
path = sys.argv[1]
team = json.load(open(path))
# Apply the Human's answers, then save. Shape per routed role:
#   "models": {"pi": ["<model>", ...], "claude": ["<model>"]},
#   "routing": {
#     "standard": {"primary": {"runtime": "pi", "model": "<m>"}, "alternates": []},
#     "critical": {"primary": {"runtime": "claude", "model": "<m>"}, "alternates": []}
#   }
# Fixed roles keep "model_selection": "fixed" and "default_model".
json.dump(team, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
```

Verify before installing — this check matters more than the test suite:

```bash
S=~/.agents/skills/herdr-agent-team/scripts
$S/roster coder    standard; $S/roster reviewer standard
$S/roster coder    critical; $S/roster reviewer critical
$S/workflow-shape --intake ~/.agents/skills/herdr-agent-team/examples/intake.json \
  --team "$CFG" --format json \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["model_independence"])'
```

`model_independence.status` must be `ok`. If it reports a collision, change the
verifier's model or raise the tier — never verify a writer with its own model.

> `tests/validate.sh` asserts the **shipped** model tables (94 references), so a
> customised routing fails it by design. Install with `--skip-validate` in phase 7
> and rely on the roster and independence checks above.

## Phase 4 — memory vault

**Ask:** where should the team keep long-term notes and its activity journal?
Suggest `~/Workspaces/vault`.

```bash
hteam-config set vault "<path>" activity_log "<path>/log.md"
mkdir -p "<path>"                       # only with the Human's agreement
[ -f "<path>/log.md" ] || printf '# Activity log\n' > "<path>/log.md"
```

The Documenter writes completion entries to `activity_log`. The Investigator reads
only a scope named in the task — never the whole vault.

## Phase 5 — projects folder and the registry

**Ask:** which folder holds the projects the team may work on? Suggest
`~/Workspaces`.

```bash
# candidate projects: git repositories at depth 1–2
find "<folder>" -maxdepth 3 -name .git -type d -not -path '*/.git/*' \
  | sed 's|/.git$||' | sort
```

Show that list, then **ask which ones to register**, with a one-line description
each. Write them into the registry, merging — never overwriting:

```bash
REG="$(hteam-config show --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["registry"])')"
mkdir -p "$(dirname "$REG")"
[ -f "$REG" ] && cp "$REG" "$REG.bak-$(date +%Y%m%d-%H%M%S)"
hteam-config set folder "<folder>" registry "$REG"
# Append under `projects:` — one block per project:
#   <slug>:
#     name: <slug>
#     path: <absolute path>
#     description: <one line>
#     status: active
#     repos:
#       <repo>:
#         path: <absolute path>
#         tech_stack: [<languages>]
#         description: <one line>
python3 -c 'import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));print("projects:",len(d["projects"]))' "$REG"
```

The Orchestrator and PM resolve projects through this file; an unregistered project
cannot be started.

## Phase 6 — task status management

**Ask:** is there an existing task-status tool the team should follow — ClickUp,
Linear, Jira, Notion, or none?

Record it; configure no integration in this phase:

```bash
mkdir -p ~/.config/herdr-team
cat > ~/.config/herdr-team/task-status.md <<EOF
tracker: <none|clickup|linear|jira|notion>
workspace: <id or url, if any>
auto_intake: deferred
notes: <how the Human expects status to be reported>
EOF
```

Work is dispatched by the Human in the PM pane; the team's own state lives on the
task board and in the activity log. ClickUp auto-intake is a later phase and stays
disabled (`hteam --watch off`).

## Phase 7 — install

```bash
cd ~/.agents/skills/herdr-agent-team/harness && ./setup_harness.sh
# after custom routing in phase 3:
cd ~/.agents/skills/herdr-agent-team/harness && ./setup_harness.sh --skip-validate
```

Point `repo` at the installed harness so the launcher does not need the old
project-scaffold clone:

```bash
hteam-config set repo "$(cd ~/.agents/skills/herdr-agent-team/harness && pwd)"
```

The installer places 55 artifacts: 15 binaries in `~/bin` (including the `hteam`
symlink), the role prompts in `~/.agents/agents`, `team.json` linked to the
canonical config, the guard binaries, the extensions, the Claude agent definitions,
`/hteam` for Pi, and the voice scripts.

## Phase 8 — verify before reporting success

```bash
cd ~/.agents/skills/herdr-agent-team/harness && ./uninstall.sh --check   # expect 55
readlink ~/.agents/team.json
hteam-config show                       # vault, folder, registry = the answers
command -v hteam && hteam check
```

`uninstall.sh --check` exits 1 while artifacts exist — that is the pass condition.
Confirm `~/bin` is on `PATH` (`case ":$PATH:" in *":$HOME/bin:"*)`); add
`export PATH="$HOME/bin:$PATH"` to `~/.zshrc` if not, then open a new shell.

Write the decisions down so the next session does not re-ask:

```bash
cat > ~/.config/herdr-team/setup-answers.md <<EOF
# Team setup — $(date +%Y-%m-%d)
runtimes: <chosen, in order>
standard tier: <runtime/model per role group>
critical tier: <runtime/model per role group>
vault: <path>
projects folder: <path>
registry: <path> (<n> projects)
tracker: <none|clickup|linear|jira|notion> (auto-intake deferred)
EOF
```

## Phase 9 — update or remove

```bash
# update the payload, then reinstall
npx skills update herdr-agent-team hteam -g -y
cd ~/.agents/skills/herdr-agent-team/harness && ./setup_harness.sh

# remove
cd ~/.agents/skills/herdr-agent-team/harness && ./uninstall.sh
npx skills remove herdr-agent-team hteam -g -y
rm -f ~/.hermes/skills/{herdr-agent-team,hteam}
```

`uninstall.sh` never deletes `{folder}/.agents/task-board`, the registry, the vault
or `~/.config/herdr-team/setup-answers.md`.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| `the agent-skills tooling is missing` | `npx skills add` not run | run the command it prints |
| `PyYAML is missing` | pip dependency absent | `python3 -m pip install --user pyyaml` |
| `clickup-watch tests failed` | PyYAML absent, gate bypassed | install PyYAML, re-run |
| `validate: …` after phase 3 | suite asserts shipped model tables | use `--skip-validate`, keep the roster check |
| `model_independence.status` not `ok` | writer and verifier share a model | change one model or the tier |
| `missing role file` | phase 7 not run, or wrong directory | `cd …/harness && ./setup_harness.sh` |
| `coder cannot start on protected branch` | dispatch without `--work-branch` | pass the branch from the scope lock |
| `herdr app window is not reachable` | Herdr.app closed | open the app, re-run `hteam check` |
