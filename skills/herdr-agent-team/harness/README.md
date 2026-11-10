# Minimal Herdr Agent Team

Source of truth for a Herdr-based, multi-project agent team. The repository is
intentionally limited to team topology, pane control, communication, Pi/Claude
runtime adapters, role definitions, and installation.

## Architecture

The global Orchestrator is the registry, harness, project-workspace, and PM
lifecycle control plane. After it opens a project and confirms PM readiness,
the Human continues directly in that project's PM pane.

```text
[Orchestrator: registry / harness / project lifecycle]
├── opens Project A / manager-a: [pm-a] [supervisor-a]
└── opens Project B / manager-b: [pm-b] [supervisor-b]

Human -> pm-a (Project A work)
Human -> pm-b (Project B work)
```

Each project workspace uses on-demand tabs:

```text
manager-smart_ai
  [pm-smart_ai] [supervisor-smart_ai]

planner-smart_ai
  [sa-smart_ai] [investigator-smart_ai] [researcher-smart_ai/designer-smart_ai]

worker-smart_ai-api
  [coder-smart_ai-api] [refactor-smart_ai-api]

worker-smart_ai-frontend
  [coder-smart_ai-frontend] [refactor-smart_ai-frontend]

verifier-smart_ai
  [reviewer-smart_ai] [tester-smart_ai]
```

Planner roles are a catalog, not a requirement to keep four agents active.
Each tab has at most three panes. PM selects the specialists needed for the
task and reuses a completed slot; a second Planner tab requires an explicit
capacity decision.

Supervisor reuses the verifier tab and its available panes for revisions
instead of creating suffixed verifier tabs. Retired verifier tabs are cleaned
up only when all their panes are `idle` or `done`.
For one task's revision loop, the same selected Reviewer or Tester agent stays
in its pane and reruns verification after each Worker revision. A replacement
agent is used only when the current instance is unavailable, and it reuses the
same role slot rather than adding another pane.

## Command Chain

```text
Human -> Orchestrator -> PM bootstrap
Human -> PM -> Supervisor -> Worker -> [optional Verifier]
         PM -> Planner Team
```

- Orchestrator owns registry/harness lifecycle, PM startup, global status,
  cross-project coordination, and shutdown.
- PM is the primary Human-facing controller after handoff.
- PM owns project planning and Supervisor.
- Supervisor owns all Worker and Verifier tabs in its project.
- Worker creates changes.
- A selected Verifier independently returns `PASS` or `CHANGES_REQUIRED` with
  evidence.
- Failed verification returns to Worker through Supervisor.

Every operation is scope-locked before execution: operation type, intended base branch,
exact allowed files, one required observable behavior, forbidden adjacent
scope, and a smallest-direct-change constraint. Reviewer checks the complete
`base...HEAD` diff and rejects unapproved files or avoidable complexity.

Task classes are adaptive. A `document` task, such as writing a Markdown note,
is delegated by PM to the scoped Documenter role and normally has no Coder,
Supervisor, Reviewer, or Tester. A
Reviewer is added when the document changes policy, security, or executable
behavior; a Tester is added only when there is runnable acceptance or the Human
requests it. `operational` tasks follow the same evidence-based staffing rule.
PM chooses a `Staffing` mode: `minimal` for the smallest executable team,
`focused` for one specialist or evidence role, and `full` for broad or
high-risk work. PM consults the Human directly only for material behavior or
naming decisions, scope expansion, destructive recovery, or authorization
gates.

Every plan defines an Acceptance Gate with `BLOCKER` and `ADVISORY` findings,
`Revision budget: 2`, and a `Model budget`. Only blocker findings may trigger a
revision. Revision 0 is the initial result; after Revision 2 the team accepts
with advisory notes when blockers are gone or stops with `[STUCK]` when a
blocker remains. Document tasks use Documenter and an economical model by
default; Tester requires explicit runnable acceptance.

## Scoped Vault Retrieval

The team can retrieve internal knowledge from the configured vault without a
new always-on Librarian role. PM reuses Investigator for an on-demand,
read-only `investigation` task and keeps Documenter as the only note-writing
role.

```text
Human -> PM -> Investigator (search/read evidence)
         PM -> Documenter (separate approved write, if requested)
```

The retrieval brief names one file or directory below the configured vault
root, a bounded query, excluded paths, a maximum result count, and the required
path-and-excerpt evidence. PM launches Investigator with:

```bash
spawn-agent ... --role investigator --task-class investigation \
  --knowledge-source vault --vault-read-scope projects/smart_ai ...
```

`spawn-agent` and `agent-runtime` validate that the role is Investigator, the
task class is `investigation`, the configured vault exists, and the resolved
scope is a readable descendant of the vault root. The vault root itself and a
path or symlink that resolves outside it are rejected before retrieval starts.
Investigator searches Markdown directly with bounded read-only tools, so the
feature does not require Obsidian to be open and does not expose Obsidian CLI
mutation commands. Results return to PM as vault-relative paths with short
matching excerpts; they do not authorize a write. Creating or updating a note
remains a separate Documenter task with exact `Allowed files`.

This design avoids the main workflow risks: broad scans that waste context,
accidental reads outside the approved knowledge area, overlapping search/write
ownership, and a runtime dependency on the Obsidian application. It is exact
text and file retrieval rather than a semantic/vector index; a missing or
overly broad scope stops as `[STUCK]` so the Human can narrow it deliberately.

## Install

For a clean installation, uninstall the managed runtime and retired full-sync
artifacts before installing the minimal runtime:

```bash
./uninstall.sh --dry-run
./uninstall.sh
./setup_harness.sh
./tests/validate.sh
```

`uninstall.sh --check` exits with status 1 when an installed artifact remains.
The uninstaller removes manifest-owned runtime files and the explicit legacy
catalog from IDE locations previously supported by this repository. Files with
unrelated names are preserved.

For an in-place upgrade, `./setup_harness.sh` remains sufficient because it
replaces all manifest-owned files before copying the current runtime.

The installer manages only:

- `~/.agents/agents.md`, `team.json`, roles, protocols, and three skills
- the role definitions it installs into `~/.claude/agents/`
- `herdr-team`, `agent-runtime`, `spawn-agent`, `verify-pane-agent`, and
  `agent-team-shutdown`, `validate-okf`, `voice-notify`, and `task-board` in `~/bin`

It does not install Herdr, Pi, Claude, models, credentials, MCP servers, or
product workflows.

### Voice summaries on macOS

Voice summary is off by default. The full explanation remains in the UI chat;
when enabled, one Human-facing controller speaks a short Thai outcome after its
session settles. Orchestrator owns voice for startup, registry, global or
cross-project work, handoff, and shutdown. Direct Human input in a PM pane moves
voice ownership to that PM; direct Human input in Orchestrator moves it back.
Background PMs and all child roles stay silent, and agent-to-agent protocol
messages never move ownership. The owning PM also speaks its reply after a
`[DONE]`, `[STUCK]`, or `[AWAITING_HUMAN_COMMIT]` result arrives; `[ACK]`,
`[STATUS]`, and other protocol traffic stay silent. The spoken line states what
was completed or the current state and includes the specific next action
whenever the Human must do something. It does not read the full chat, cut a
long paragraph mid-sentence, replace the full response, or auto-approve
permissions.

```bash
herdr-team                  # voice off
herdr-team --voice on       # speak the active Orchestrator or PM summary
herdr-team --voice off      # explicitly disable voice summaries
```

The voice choice applies to the whole team session when starting a new
Orchestrator. If one is already running, stop and start it again before changing
the choice. Voice ownership is stored per Herdr session, so only the controller
for the latest direct Human conversation can speak. The project source
is [`bin/tts-thai.sh`](/Users/arsan_t/Workspaces/project-scaffold/bin/tts-thai.sh),
and `./setup_harness.sh` installs it as `~/.config/herdr/tts-thai.sh`.

The engine is VoiceStudio `omnivoice` through `bin/tts-speak-omni`: the
Thai-native profile `c3141426` at speed 0.9, passed through a light band-pass
chain (highpass 120 Hz, lowpass 7.5 kHz, gentle compression, -16 LUFS). There is
no cabin reverb: the PA chain widened nothing and made the voice harsh.
Before synthesis the adapter strips markdown, paths, URLs, hashes and emoji,
turns Arabic digits into Thai words and rewrites short English loanwords with
`thai-accent`, because those three are what made earlier output unintelligible.
gTTS (`gtts-cli --lang th`) remains the fallback when VoiceStudio is not
running, so a machine without the backend still speaks. There is deliberately no
macOS `say` fallback: the team never speaks in a voice nobody chose.
A short line synthesizes in about half a second; `HERDR_VOICE_SPEED` is applied
with ffmpeg `atempo` when it is not 1.0, and `HERDR_VOICE_CACHE_DIR` moves the
cache.
The Orchestrator's Thai responses use feminine pronouns and endings to match
this voice. Set
`HERDR_VOICE_TTS_SCRIPT` to override the native voice, or set
`HERDR_VOICE_SOUND=0` / `HERDR_VOICE_SPEECH=0` to disable one output channel.

## Start the Global Orchestrator

Open the dedicated Herdr session and start the global Orchestrator with one
command:

```bash
herdr-team
```

It validates the installed harness and workspace registry, opens the
`herdr-team` session, labels the pane `orchestrator`, and starts the global
Orchestrator with an onboarding prompt. If that session and Orchestrator already
exist, it focuses and reattaches instead of starting a duplicate.
The Orchestrator presents registered projects and asks which project to open or
whether to start new-project provisioning. It validates only the selected
registry entry and paths, creates or reuses the workspace, starts PM, and tells
the Human which `pm-{project}` pane to continue in. PM then inspects the project,
confirms scope, runs the team, presents authorization gates, and reports results
directly to the Human. Human-facing communication is in Thai; all inter-agent
protocol messages and task payloads are in English. Run the check without
starting an agent with:

```bash
herdr-team check
```

The default vault is `~/Workspaces/vault` and the default OKF activity log is
`~/Workspaces/vault/log.md`. Override them when needed:

```bash
herdr-team --vault-path /absolute/path/to/vault \
  --activity-log /absolute/path/to/vault/log.md
```

Orchestrator passes the configured vault and OKF activity-log paths to PM
without reading vault content. PM delegates completion journaling to the scoped
Documenter.

Validate an OKF bundle manually with:

```bash
validate-okf /Users/arsan_t/Workspaces/vault
```

The Orchestrator has a fixed Pi runtime and an Antigravity Gemini 3.8 Flash
default; `auto` resolves the default without fallback. To select its runtime
explicitly:

```bash
herdr-team --runtime pi
```

To pass the allowlisted Orchestrator model explicitly on a new startup:

```bash
herdr-team --runtime pi --model antigravity/gemini-3.8-flash
```

The model option applies only when starting an Orchestrator. If one is already
running, restart it before selecting another model.

`.agents/team.json` schema v4 stores ordered runtime/model allowlists and the
machine-readable primary/alternate route for every `standard` and
`critical` routed child assignment. Orchestrator defaults to Pi
`antigravity/gemini-3.8-flash`, PM is fixed to Pi `antigravity/gemini-3.8-flash`, and
Designer is fixed to Claude `opus`;
none has tier routing. Before every routed child
spawn, its owning controller scores Scope, Ambiguity, Reasoning, Risk, and
Evidence from 0 to 2, records the assessment, and passes `--task-tier`,
`--runtime`, and `--model`. Totals 0-7 are standard and 8-10 are critical; the
retired middle tier is folded into standard because the standard models now carry
general work, and high-risk overrides force critical. A configured alternate additionally
requires `--routing-exception`. There is no silent fallback or separate Human
model-approval round.

The top-level `disabled_model_providers` array disables a provider globally
without removing its models or routes. It is currently empty, so every
configured provider is enabled. When a configured tier
primary is disabled, the runtime selects the first enabled alternate in order,
records an explicit failover, and marks the effective launch as a routing
exception. A tier with no enabled alternate stops before launch; the runtime
never substitutes outside the tier. Explicitly selected disabled alternates and
disabled fixed-role defaults remain invalid. The setting does not stop or
change an agent session that is already running.

Controller-selected roles route each assignment to the configured tier
primary shown in `.agents/protocols/communication.md`. Researcher and
Documenter use Pi `antigravity/gemini-3.8-flash` for every tier. Planner,
Supervisor, and Verifier tiers rotate across three Pi families - `opencode-go/
deepseek-v4.1-flash`, `antigravity/claude-sonnet-4-6`, and
`antigravity/gemini-3.8-flash` - so planning and review do not run on one
model lineage; Supervisor stays on the fast Pi model at every tier. Every
judgment or implementation critical tier uses Claude `opus`, except Tester
which uses Claude `sonnet`. Reviewer and Tester carry explicit alternates so a
writer never verifies itself: Reviewer falls back to
`antigravity/gemini-3.8-flash` on both tiers, and Tester
falls back to `antigravity/gemini-3.8-flash` on standard and
`antigravity/gemini-3.8-flash` on critical. Those alternates exist only for
the independence rule - a disabled primary with no enabled alternate stops every
route whose primary uses it. The fixed Orchestrator, PM, and Designer
roles retain their policy-defined models.

| Role | Runtime | Ordered models |
|---|---|---|
| PM (fixed) | Pi | `antigravity/gemini-3.8-flash` (multimodal: the Human chat pane) |
| Supervisor | Pi | `opencode-go/deepseek-v4.1-flash` |
| SA | Pi | `antigravity/gemini-3.8-flash` |
| SA | Claude | `opus` |
| Investigator | Pi | `opencode-go/deepseek-v4.1-flash`, `antigravity/gemini-3.8-flash` |
| Investigator | Claude | `opus` |
| Researcher | Pi | `antigravity/gemini-3.8-flash` |
| Designer (fixed) | Claude | `opus` |
| Documenter | Pi | `antigravity/gemini-3.8-flash` |
| Coder | Pi | `opencode-go/deepseek-v4.1-flash`, `antigravity/gemini-3.8-flash` |
| Coder | Claude | `opus` |
| Refactor | Pi | `opencode-go/deepseek-v4.1-flash`, `antigravity/gemini-3.8-flash` |
| Refactor | Claude | `opus` |
| Reviewer | Pi | `opencode-go/deepseek-v4.1-flash`, `antigravity/claude-opus-4-6` |
| Reviewer | Claude | `opus` |
| Tester | Pi | `antigravity/claude-sonnet-4-6`, `antigravity/gemini-3.8-flash` |
| Tester | Claude | `sonnet` |

The exact routing policy is authoritative in `.agents/team.json`; the readable
assessment contract and primary routing table are documented in
`.agents/protocols/communication.md`. `spawn-agent` and `agent-runtime` reject
missing tiers for routed roles, mismatched pairs, and unmarked alternates
before launch; fixed PM and Designer resolve directly to their configured
pairs.
Any model that is not the evaluated tier's primary requires an explicit
`--routing-exception` with a recorded reason.

Claude is started with
`--dangerously-skip-permissions --agent herdr-orchestrator`.

Controller, Planner, and Verifier roles are runtime-enforced read-only. Only
Coder and Refactor receive repository write tools; Supervisor receives guarded
Git commit/push/PR capabilities for supervised execution. Git/GitHub guards
block all unapproved operations. After scope and the proposed work-branch
name are approved, `spawn-agent` safely creates or switches that branch before
starting the Worker; the Human is not asked to run local branch commands. For
an approved `protected-sync` operation, Supervisor may instead launch a
read-only Worker on an existing protected branch. The runtime permits only
`git switch {branch}` and `git pull --ff-only origin {branch}` after a clean
worktree check; edits, commits, pushes, merges, rebases, and separate fetches
remain blocked.

Normal implementation commits require independent verification. After local
checks, the original Coder or Refactor runs
`agent_prepare_verification_candidate` with the exact `Allowed files`. It
freezes a staged diff and sends `[READY_FOR_VERIFICATION]`; every selected
Reviewer or Tester must return PASS for that exact SHA-256. Only then may the
Worker run `agent_prepare_commit_review`, which rejects candidate drift and
sends `[AWAITING_HUMAN_COMMIT]` in manual mode or `[AUTO_COMMIT_READY]` if the
scope lock was approved with `AUTO_COMMIT`. PM presents a verified artifact to
the Human only in manual mode, where `APPROVE_COMMIT` permits the original
Worker on a direct path, or Supervisor on a supervised path, to run
`agent_authorized_commit`. Auto mode uses `agent_auto_commit` only after
verification and controller validation. Any candidate change requires fresh
verification and a fresh artifact. The post-commit comparison is mechanical integrity evidence;
Reviewer and Tester do not run after commit.

After the Human supplies `APPROVE_PUSH` directly to PM,
PM routes it through the internal controller chain. Supervisor handles push
and PR creation for supervised execution; the original Coder or Refactor
handles the direct path. The executor may push only its matching current `HEAD` and
non-protected branch to `origin`. A separate `APPROVE_PR_DEV` directive may
then permit that executor to create one PR from the matching remote
branch into `dev`; the Human authorizes these actions but does not need to run
Git/GitHub themselves. PR updates, reviews, close, merge, and all other remote
mutations remain blocked.

From the Orchestrator conversation, a standalone `shutdown` command closes
the active project team workspaces and hands shutdown to a detached external
finalizer. The finalizer queues `/quit` for the Orchestrator and runs
`herdr server stop` as its final command without waiting for the client
session to exit.
It does not close unrelated workspaces.

## Herdr Desktop App Runtime (`hteam`)

The desktop app (`Herdr.app` + `herdr-core`) is a **separate runtime** from the
`herdr` CLI: it owns spaces / tabs / terminals under `~/.config/herdr-app` and
`~/.local/state/herdr-core`, and it cannot see CLI sessions or panes. The team
therefore has its own entry point for it:

```bash
hteam                       # start (or reuse) the Orchestrator in the app window
hteam check                 # validate prerequisites only
hteam --watch on            # also run the ClickUp intake watcher (default: off)
hteam --voice on            # speak short Thai status from Orchestrator and PM
~/bin/herdr-app-spawn-role <role> <brief-file> --project <slug> --controller <tN>
```

Mapping between the two runtimes:

| CLI runtime | app runtime |
|---|---|
| `herdr workspace` | app space (`herdr-app do space.new`) |
| `herdr tab` | app tab (`herdr-app do tab.new`) |
| `herdr pane` | hc terminal (`t1`, `t2`, …) |
| `herdr pane run` / `read` | `hc send <t>` / `hc read <t> --lines N` |
| `HERDR_ENV` / `HERDR_PANE_ID` | `HC_TERMINAL_ID` (+ `HERDR_APP_SPACE`) |

Both launchers start every role through `bin/agent-runtime` with
`env HERDR_ENV=1`, so the canonical prompt, policy block and model allowlist
from this repo are reused unchanged; the runtime is Pi, as the routing policy
requires.

`herdr-app-team` writes its brief to
`~/.local/state/herdr-app-team/<space>/orchestrator-brief.md` and seeds it
through `pi ... --initial-prompt`, so no keystroke timing is involved. Spawned
roles receive the same file plus a transport appendix that tells them who to
report to.

Role placement mirrors the repository topology instead of one tab per role:

```text
space = project          manager-{project}    pm, supervisor
tab   = role group       planner-{project}    sa, investigator, researcher, designer
pane  = the role         worker-{project}     coder, refactor   (+ -{workstream})
                         verifier-{project}   reviewer, tester
```

Tabs hold at most three panes, left to right; the fourth role opens another tab
of the same name, exactly like the CLI runtime. Call the spawner with
`--project <slug>` to get this grouping (`--workstream <name>` suffixes a
second Worker tab); without `--project` it falls back to one tab per role.

### Bringing the app runtime to another machine

Prerequisites on the target Mac:

1. macOS with `Herdr.app` installed and opened once (`herdr-app` and
   `herdr-core` land in `~/.local/bin`).
2. `pi` installed and authenticated (`pi --version`).
3. This repo checked out somewhere stable.
4. The workspace registry at `~/Workspaces/.agents/workspace-registry.yaml`
   (or set `HERDR_TEAM_REGISTRY`).

Then:

```bash
# 1. the team tooling itself (workflow-shape, task-board) lives in agent-skills
npx skills add tomozard/agent-skills/skills/herdr-agent-team

# 2. this harness installs hteam, herdr-app-team, herdr-app-spawn-role, roles
cd /path/to/project-scaffold
./setup_harness.sh
hteam check                 # must pass
hteam                       # open the app and start the Orchestrator
```

`bin/workflow-shape` and `bin/task-board` are shims: they exec the scripts from
`~/.agents/skills/herdr-agent-team/scripts` (override with
`HERDR_AGENT_TEAM_SCRIPTS`), so the resolver and the board have one source and
cannot drift. `setup_harness.sh` refuses to install without them.

Environment overrides when the checkout or registry live elsewhere:
`HERDR_TEAM_REPO`, `HERDR_TEAM_REGISTRY`, `HERDR_TEAM_VAULT`,
`HERDR_TEAM_ACTIVITY_LOG`, `HERDR_TEAM_SPACE`, `HERDR_TEAM_STATE_DIR`.
Both launchers also auto-discover the repo from their own location when the
default `~/Workspaces/project-scaffold` is absent.

## ClickUp Intake (`clickup-watch`)

The desktop-app team can pull work from ClickUp instead of waiting for a Human
message. `bin/clickup-watch` is a plain polling loop — **not an agent**, so a
poll costs no model tokens — and it lives with the team: `hteam` starts it in
its own tab in the control space and it stops when the team stops. It follows
the project harness: every 30 minutes it visits the ClickUp lists of the
projects whose registry entry opts in, and nothing else.

```bash
clickup-watch status          # list, tag, trigger status, watcher pane, last poll/dispatch
clickup-watch check           # config + registry + ClickUp MCP login + herdr-core, no network
clickup-watch init            # write the config file with commented defaults
clickup-watch once            # one poll now (--dry-run to look without touching ClickUp)
clickup-watch start | stop    # start or stop the kept watcher pane
clickup-watch loop            # foreground loop, --interval N (default 600s)
```

What one poll does:

1. Picks its targets from the project harness registry: every project whose
   entry sets `clickup: { auto_intake: true }`, on each of the ClickUp lists
   registered for it (a project may have several). A project without that flag
   is never polled at all.
2. Reads tasks in the trigger status (default `to do`) **that carry the opt-in
   tag** (default `agent-team`) **and are assigned to this agent's own ClickUp
   user** (default `me`), over the **ClickUp MCP** the runtimes already use, with
   the stored OAuth login — no personal API token. The lists are usually shared
   with people, and each herdr-team user has their own ClickUp account, so a task
   that lacks the tag or belongs to someone else is never read further,
   commented on, moved, or assigned.
3. Resolves the project from the list it came from, so nothing is guessed. A
   `project: <slug>` line in the task description still overrides the list's
   project, which is how one list can feed two projects.
4. Resolves the pane by the same naming the spawner uses — registry
   `ap-intranet` → tab `pm-ap_intranet` → that PM's terminal. A bare `pm` pane
   belongs to another project and is never used.
5. Delivers a brief (English, file-first) to the PM: the task text verbatim, the
   project and its repos, and the dispatch policy. The brief grants **no**
   authority — PM still puts its plan, `Allowed files`, work branch, and the
   "wait at the commit gate or `AUTO_COMMIT`" question to the Human and starts
   only after approval.
6. Claims the task visibly: assigns it to the agent's ClickUp user (so people
   see it is taken), writes `in progress`, and adds a Thai `[herdr-team]`
   comment naming the project and receiving pane. An assignee a person already
   holds is never replaced — the claim is skipped and logged instead.
7. Watches its own claims: a task still `in progress` with no ClickUp activity
   (`date_updated` unchanged) for `stale_hours` (default 8, 0 disables) is
   commented and parked in `discuss` — that is how a dead pane or a forgotten
   task comes back to the Human instead of hanging forever.

### Questions go back to ClickUp

The loop is two-way, so nobody has to sit in a pane watching for a question:

```bash
clickup-watch ask --task <id> --text "คำถามสั้น ๆ"      # or --comment-file FILE
```

That writes a Thai `[herdr-team]` comment and moves the task from
`in progress` to `discuss`. The Human answers on the task and moves it back to
`to do`; the next poll re-dispatches it and quotes those answers in the brief, so
PM continues instead of asking again. `ask` only touches tasks this watcher
dispatched, and it is the only ClickUp write an agent may make.

### Who owns the ClickUp status

Silent tasks are the usual failure, so the ownership is explicit:

| Transition | Owner | How |
|---|---|---|
| `to do` → `in progress` | watcher | automatic on handoff |
| `to do` → `discuss` | watcher | ambiguous project, or no activity after `stale_hours` |
| `in progress` → `discuss` | PM | `clickup-watch ask` (question) or `mark --status discuss` (blocker) |
| `in progress` → `ready` | PM | `clickup-watch mark --task <id> --status ready --text "..."` |
| subtask → `ready` | PM | same command with the subtask id |
| `discuss` → `to do` | Human | after answering |
| `done` / `reject` / `complete` | Human | never the agent |

```bash
clickup-watch mark --task <id> --status ready --text "แก้ครบ 12 กลุ่ม, verifier ผ่าน"
clickup-watch mark --task <subtask-id> --status ready      # tick a checklist item
```

`mark` accepts only `in progress`, `discuss`, and `ready`; closing statuses are
refused. It works on tracked tasks and on any task already assigned to the
agent's user (so subtasks work without `--force`), and always writes a
`[herdr-team]` comment naming the change.

### Turning auto intake on for one project

Auto intake is off for every project until its registry entry says otherwise, so
nothing is polled by default. Add one key under that project's `clickup:` block:

```yaml
projects:
  ap-intranet:
    clickup:
      list_id: '901615751336'
      auto_intake: true      # ← this project's lists are polled every 30 minutes
```

A project with several lists (for example `crm-mobile` with three under
`clickup.lists:`) needs the flag once — all of its lists are polled. Remove the
key to stop intake for that project. Restart the watcher after editing the
registry (`clickup-watch stop && clickup-watch start`) and confirm with
`clickup-watch status`, which lists every enabled project and its list ids.

Unresolved and unstaffed tasks never disappear:

| Situation | ClickUp result |
|---|---|
| Project not enabled in the registry | not polled at all |
| No opt-in tag | untouched: no comment, no status change, no assignee |
| Tagged but assigned to another herdr-team user | untouched: another instance's watcher owns it |
| Project resolved, PM live | assigned to the agent user, `in progress`, comment naming the PM pane |
| Project resolved, no PM | stays `to do`; the Orchestrator is asked once per 30 min to open the project's PM, then the brief follows |
| Project not resolved | `discuss` + comment saying what is missing and the closest candidates |
| No PM and no Orchestrator pane | untouched, logged; retried next poll |

`clickup-watch` never closes, approves, or re-prioritises a task, never writes to
Git, and never sends to a Worker pane.

Configuration lives in a file, not in the environment:

```bash
clickup-watch init                      # write ~/.config/herdr-team/clickup-watch.yaml
$EDITOR ~/.config/herdr-team/clickup-watch.yaml
clickup-watch stop && clickup-watch start    # apply
```

`~/.config/herdr-team/clickup-watch.yaml` (override the location with
`--config PATH` or `CLICKUP_WATCH_CONFIG`) holds `list_id` (empty = follow the
registry; set it to watch one list), `workspace_id`, `status`, `require_tag`,
`require_assignee`, `claim_assignee`, `in_progress_status`, `discuss_status`,
`interval` (1800 = 30 minutes), `max_tasks`, `orch_retry_seconds`, `project`,
`registry`, `state_dir`, `terminal_name`, `team_space`, `herdr_core`, and
`mcp_url`; the file carries a comment per key.
Precedence is one-off flag >
environment variable > config file > built-in default, so `CLICKUP_WATCH_*`
variables still work for a single run without editing the file.
`clickup-watch check` and `clickup-watch status` print the config path and the
values actually in force.
Disable or enable intake for a session with `hteam --watch off|on` (the default
is off) or `HERDR_TEAM_WATCH=0|1`; the per-machine default lives in
`hteam.yaml` as `watch: on|off`.

State and audit trail: `~/.local/state/herdr-app-team/clickup-watch/` — `state.json`,
`briefs/`, and `watch.log`. If the MCP login expires, run `pi mcp login clickup`;
`clickup-watch check` reports it. Note when editing: the MCP tool
`clickup_get_task` accepts only these `include` values — `attachments`,
`checklists`, `custom_fields`, `dependencies`, `description`, `git_links`,
`linked_tasks`, `subtasks`, `watchers`; asking for `status` or `url` there is an
error, and status/url already come from the list query. Likewise
`clickup_update_task` needs numeric assignee ids: resolve `me`/names with
`clickup_resolve_assignees` (it returns `userIds`) instead of passing them
straight through.

## Spawn a Project Agent

Controllers create or reuse a pane, then call:

```bash
spawn-agent \
  --pane w1:p2 \
  --role coder \
  --project smart_ai \
  --workstream api \
  --base-branch main \
  --work-branch feature/api-change \
  --cwd ~/Workspaces/smart_ai \
  --task-tier standard \
  --runtime pi \
  --model opencode-go/deepseek-v4.1-flash
```

The resulting pane label is `coder-smart_ai-api`.

For local synchronization of an approved protected branch, use the bounded
operation below instead of an implementation Work branch:

```bash
spawn-agent \
  --pane w1:p2 \
  --role coder \
  --project smart_ai \
  --base-branch uat \
  --work-branch uat \
  --operation protected-sync \
  --sync-branch uat \
  --cwd ~/Workspaces/smart_ai \
  --task-tier standard \
  --runtime pi \
  --model opencode-go/deepseek-v4.1-flash
```

Supported roles:

```text
orchestrator pm supervisor sa investigator researcher designer
coder refactor reviewer tester
```

## Monitoring Policy

Blocking Herdr waits are forbidden. Normal coordination is push-based.

Shared delivery is serialized per target pane to prevent Reviewer and Tester
messages from interleaving. Verifiers acknowledge once, then send exactly one
final `PASS` or `CHANGES_REQUIRED` verdict with an evidence file path. Agent
panes must never receive probe, hello, or test messages.

Pane transcript access is available only to controllers and only for their
direct reports:

| Controller | May inspect |
|---|---|
| Orchestrator | PM panes across projects |
| PM | Planner panes and Supervisor in its project |
| Supervisor | Worker and Verifier panes in its project |

Transcript access is for a missing reply, blocked/unknown state, readiness
failure, or explicit human status request. It must not be placed in a polling
loop.

## Repository Layout

```text
.agents/
  team.json
  agents/                 # 11 role definitions
  extensions/             # Pi runtime extensions
  protocols/communication.md
  skills/
    herdr/
    agent-team/
    agent-shared/
bin/
  herdr-team
  agent-runtime
  tts-thai.sh             # voice adapter: VoiceStudio, gTTS fallback
  tts-speak-omni          # VoiceStudio synth + PA chain, used by all speakers
  spawn-agent
  verify-pane-agent
  agent-team-shutdown
  task-board
tests/validate.sh
  tests/task-board.test.sh
setup_harness.sh
uninstall.sh
```

The Pi runtime provides `/shutdown` as an explicit Orchestrator command. It
routes to the existing team shutdown protocol and does not replace Pi's
built-in `/quit` command. The standalone `shutdown` form remains as a
compatibility path. Pi sessions also auto-compact after the active agent run
has fully settled, with no queued messages remaining, when context usage
exceeds 50%. The manual `/compact` command remains available. There is no MCP
catalog in this runtime.

## Task Board

`task-board` provides a small Python 3 standard-library CLI for durable task
state and append-only protocol history. State is stored outside the worktree at
`{workspaces_root}/.agents/task-board/{project}/{task_id}/` (override with
`HERDR_TASK_BOARD_ROOT`). The snapshot is `state.json`; events are appended to
`events.jsonl` and never replace Herdr messages, task files, evidence, Git
history, or the OKF log.

Mutations require `HERDR_ENV=1`. Only `pm` and `supervisor` may create tasks or
transition authoritative state; any team role may append an event. Reads are
available as human-readable output or JSON:

```bash
HERDR_ENV=1 HERDR_AGENT_ROLE=pm task-board create project task-123 \
  --state planned --commit-required --verification-required
task-board show project task-123 --json
task-board list --project project --json
HERDR_ENV=1 HERDR_AGENT_ROLE=coder task-board event project task-123 \\
  --type STATUS --payload '{"state":"in_progress"}'
HERDR_ENV=1 HERDR_AGENT_ROLE=supervisor task-board transition project task-123 in_progress
```

The explicit transition table rejects invalid or terminal transitions. Updates
use an atomic snapshot replacement and a per-task mkdir lock; event history uses
append-only writes. For implementation tasks it also binds the frozen candidate
diff, verified diff, Human gate, and resulting commit SHA in order.
`uninstall.sh` removes installed binaries but deliberately never deletes
workspace Task Board history.

## Workflow Shape Resolver

`workflow-shape` turns PM's adaptive-staffing policy into a deterministic
decision. PM answers a structured intake and the resolver returns the shape, the
staff with their routed models, the verifiers, the tier, the controller, the
gates, and the reason every larger shape was rejected:

```bash
printf '%s' '{"task_class":"bug-fix","known_cause":true,"touches_behavior":true,
  "runnable_acceptance":true,"risk":"low"}' \
  | ./bin/workflow-shape --intake - --format text

./bin/workflow-shape --list          # the eleven shapes
./bin/workflow-shape --explain W4-fix-test
```

Intake fields: `task_class`, `request`, `touches_behavior`, `known_cause`,
`runnable_acceptance`, `new_behavior`, `structural_cleanup`,
`micro_deterministic`, `ui_change`, `external_facts_needed`,
`policy_sensitive_doc`, `needs_remote_delivery`, `independent_workstreams`, and
`risk`. Unknown fields are rejected rather than ignored, so a typo cannot
silently change staffing.

The resolver is read-only. It never spawns panes, never touches the worktree, and
never grants scope, commit, or remote-delivery authority. Three rules are
enforced rather than advisory: the smallest shape wins, a writer and the verifier
gating it never share a model, and more than one independent workstream forces
`git-worktree` isolation with the supervised controller.

## Validate

```bash
./tests/validate.sh
```

The validator checks shell syntax, JSON, role completeness, forbidden legacy
catalogs, Claude's required permission flag, and restricted pane access.
