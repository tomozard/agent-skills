---
name: herdr-agent-team
description: Run a multi-agent delivery team with enforced staffing, scope locks and verification gates, and start or check that team in the Herdr desktop app with the `hteam` launcher. Use when coordinating several AI agents on one codebase — sizing the smallest team for a task, freezing a verified diff before a commit, keeping a writer's work independent from its verifier, auditing why a change shipped — or when the Human types hteam or /hteam to open the app team. Ships a workflow-shape resolver, a durable task board, role contracts, the delivery protocol, and the launcher docs. Tuned for the Herdr app; the policy and scripts run with any agent runtime.
---

# Herdr agent team

A delivery discipline for agent teams working on real repositories. The point is
not more agents: it is that staffing, scope, and the commit gate are decided by
rules instead of by whoever is holding the conversation.

Everything here runs without a multiplexer. Herdr is the recommended runtime —
it gives you one space per project and child terminals under each controller —
but the policy, the resolver, and the task board work with any runtime that can
spawn a process and send a message.

## Team at a glance

The team divides work three ways: by **authority layer** (who may decide), by
**delivery stage** (what happens next), and by **shape** (how large the team
is). Twelve roles sit in three layers, plus an optional controller:

```text
Human
├── Orchestrator   bootstrap only: registry, harness, project lifecycle, cross-project
└── PM             one per project; the Human's only project conversation
    ├── Planner      sa, investigator, researcher, designer   (read-only)
    ├── Worker       coder, refactor                           (scoped writes)
    ├── Verifier     reviewer, tester                          (independent)
    ├── Documenter   approved documents only
    └── Supervisor   optional: full / multi-worker / revision loops
```

| Division | Count | Decided by |
|---|---|---|
| Authority layers | 3 + optional controller | who may write, verify, approve, and report |
| Delivery stages | 8 | describe → resolve → lock → execute → freeze → verify → commit → deliver |
| Shapes | 11 (`W0`–`W10`) | the smallest team the task's evidence needs |

Each layer's authority, each stage's owner and stop gate, the full shape
catalogue, and the decisions that stay with the Human are in
[`references/team-at-a-glance.md`](references/team-at-a-glance.md).

## Two entry points

- **Start or check the team** — the Human types `hteam` or `/hteam`, or the app
  team is not running yet: read [`references/launcher.md`](references/launcher.md)
  first. It covers the launcher's commands, the per-machine config, and the
  failure modes worth recognising.
- **Do the work** — a task needs staffing, scope, verification, a commit, or an
  audit: start with the four rules and the flow below.

## The four rules

1. **Smallest shape first.** Resolve a shape from the intake; raising it once
   needs a written reason, and a second raise is the Human's decision. A bigger
   team is never justified by model tier alone.
2. **Independent verification.** The agent that wrote the change must not be the
   agent that verifies it, and not on the same model. When routing collides,
   substitute an alternate, raise the tier, or report `partial`/`blocked`.
3. **Isolation for concurrency.** More than one independent workstream means
   separate git worktrees and one supervised controller. Two writers must never
   share a working tree.
4. **The intake is the staffing gate.** One intake file per task; every spawn
   passes the same file, and the launcher refuses any role the resolved shape
   does not include. Over-staffing becomes a refused launch, not a judgement
   call.

## Flow

| Step | Owner | Output |
|---|---|---|
| 1. Describe the task | PM | one intake file (JSON): task class, behavior change, risk, workstreams |
| 2. Resolve | `workflow-shape` | shape, staff, verifiers, tier, and why larger shapes were rejected |
| 3. Lock scope | PM | `Allowed files`, `Required behavior`, `Forbidden scope`, work branch |
| 4. Execute | worker | edits inside the allowed files only |
| 5. Freeze | worker | the staged diff frozen as a SHA-256 plus a readable artifact |
| 6. Verify | verifier(s) | PASS on that exact hash, with a revision budget of two |
| 7. Commit | worker, after the Human token | one commit whose diff is compared mechanically to the verified hash |
| 8. Deliver | worker or controller | push and PR only on exact Human authorization |

"Intake" here means only that task-description file — the resolver's input. No
tracker, issue sync, or external service is involved; wire one up yourself and
keep this same file as the contract.

The freeze-verify-commit step is the reason this exists: a commit is allowed
only for a diff hash that an independent verifier already passed, and any change
to the index invalidates every prior verdict.

## Quick start

```bash
# 1. Resolve the shape for this task (pure function: intake + team.json)
scripts/workflow-shape --intake examples/intake.json --team examples/team.json --format text

# 2. Read the catalogue when you need the full table
scripts/workflow-shape --list
scripts/workflow-shape --explain W4-fix-test

# 3. Record the task so the state is durable and auditable
export TASK_BOARD_ENV=1 TASK_AGENT_ROLE=pm
scripts/task-board create demo_task demo-1 --state planned --owner pm --controller pm
scripts/task-board transition demo_task demo-1 --to in_progress
scripts/task-board event demo_task demo-1 VERIFIER_ASSIGNED --payload '{"role":"tester"}'
scripts/task-board show demo_task demo-1
```

Copy `examples/team.json` into your project, edit the roles/models you actually
have, and pass `--team` (or set `TASK_TEAM_FILE`). The resolver is a pure
function: it never spawns anything and never writes files.

## Shapes

| Shape | Task | Opens |
|---|---|---|
| `W0-answer` | advisory, no repository write | nobody |
| `W1-doc` | documentation only | documenter |
| `W2-micro` | deterministic micro diff, no behavior change | coder (task-board proof replaces a verifier) |
| `W3-fix` | known-cause fix, acceptance not runnable | coder → reviewer |
| `W4-fix-test` | known-cause fix, runnable acceptance | coder → tester |
| `W5-refactor` | structural cleanup, no behavior change | refactor → reviewer |
| `W6-fix-refactor` | a fix whose root cause is structural | coder + refactor → reviewer + tester |
| `W7-feature` | new behavior, spec before code | sa + coder → reviewer + tester |
| `W8-investigate` | cause unknown | investigator |
| `W9-ops` | operational change, no source behavior change | coder → reviewer |
| `W10-deliver` | commit/push/PR of an already verified increment | nobody |

Full definitions, input fields, and the scoring rubric: `references/workflow-shapes.md`.

## Roles

Twelve role contracts live in `references/roles/`. They are written as identity
and policy, not as transport: replace "session" with your runtime's unit of an
agent process.

| Group | Roles |
|---|---|
| bootstrap | `orchestrator` |
| project owner | `pm` |
| optional controller | `supervisor` |
| planner | `sa`, `investigator`, `researcher`, `designer` |
| worker | `coder`, `refactor` |
| verifier | `reviewer`, `tester` |
| document | `documenter` |

The organisation is deliberately flat: the orchestrator bootstraps a project and
hands off; the PM is the project's chief of staff and owns scope, staffing,
gates and reporting; specialists execute and are leaves. Keep exactly one PM per
project — a second one splits the Human conversation and fights over the same
work.

### Placement

Every project gets its own app space; the orchestrator and PM are the tabs the
Human talks in, and every role below PM is a child terminal of its controller.
The room table, the child-terminal rules, and the naming convention are in
[`references/placement.md`](references/placement.md).

## Runtimes

A runtime is judged by verbs, not by name: `launch`, `ask`, `send`, `resume`,
`model`, `permissions`. Probe this machine with `scripts/runtime-probe` and
resolve a role with `scripts/roster`; the contract, the per-CLI invocations, and
the degraded modes are in [`references/runtime-adapters.md`](references/runtime-adapters.md).

## Memory vault

The vault is an optional memory root — long-term notes plus the OKF activity log
— configured per machine with `/hteam setup` or
`hteam-config set vault <path> activity_log <path>/log.md`. It is opt-in: with no
vault configured the team works normally and nothing reads or writes notes.

Two roles touch it, and only this way:

- **Investigator** reads one scope named in an approved `investigation` task
  (`Knowledge source: vault`, a `Vault read scope` below the configured root,
  plus query, exclusions, result limit, and evidence format). It is read-only:
  no root scan, no symlink escape, no mutation.
- **Documenter** writes only the approved `log.md` completion entry.

`uninstall.sh` never deletes the vault. Full rules: phase 4 of [`setup.md`](setup.md)
and [`roles/investigator.md`](references/roles/investigator.md).

## Communication

`references/communication-protocol.md` is the full contract: envelope, ACK /
STATUS / DONE / STUCK, file-first handoffs, dispatch accounting, the verification
loop, and the commit-review and remote-delivery gates. Two rules carry most of
the weight:

- every assignment names its reply target, and a completion is only ever pushed
  to the controller — never announced to your own session;
- a verifier sends exactly one verdict, bound to the diff hash it checked.

Delivery is Herdr's job. In the Herdr app (herdr-core) a message is
`hc send <terminal> "<text>"`; with the terminal CLI it is
`herdr agent prompt <agent> "<text>"`, falling back to `herdr pane run` plus
`herdr pane send-keys <pane> enter`. Children are `hc run --bg --parent`, while
spaces, tabs, and splits belong to `herdr-app do …`. Serialize per target,
file-first above ten lines, and never wait or poll — `hc wait`, `herdr agent wait`,
`herdr agent prompt --wait`, and `herdr pane wait-output` are blocking commands
this policy forbids, and reading a terminal is diagnostic only.

## Installing the runtime

`npx skills add` installs this policy layer only — the skills CLI copies files
and cannot run install scripts. The runtime needs one more command, and both
run from any directory:

```bash
npx skills add tomozard/agent-skills/skills/herdr-agent-team -g -y -a pi claude-code
~/.agents/skills/herdr-agent-team/harness/setup_harness.sh
```

Then `hteam check` and `hteam`. `-a pi claude-code` scopes the skill to the two
runtimes the team supports; without it `npx skills` links every detected agent.
A one-command wrapper runs both phases and verifies the result with
`hteam check --deep`:

```bash
npx -y github:tomozard/agent-skills --yes
```

`setup.md` (next to this file) is the guided procedure when the Human asks to
install, configure, or repair the team: it covers the runtime choices, the
install phase, and verification of the 55 installed artifacts.

## What is not included

- Spawning and pane layout. The launcher starts roles and owns the topology;
  delivery into a running agent is Herdr's (`herdr agent prompt`), and the exact
  commands and prohibitions are in the protocol.
- Launching. `scripts/roster` resolves role and tier to one runtime/model pair
  from `examples/team.json`'s schema (`model_selection`, ordered allowlists,
  per-tier `primary`/`alternates`), and `scripts/runtime-probe` reports what the
  machine has — but the spawn command, panes, and enforcement of the result stay
  with your launcher.
- Trackers and issue sync. Intake is a file here; wire it to whatever tracker you
  use and keep the same shape.

## Reference map

| Question | Read |
|---|---|
| how the work is divided (layers, stages, shapes, gates) | `references/team-at-a-glance.md` |
| start, check, or configure the app team | `references/launcher.md` |
| who should work on this task | `references/workflow-shapes.md` |
| messages, verdicts, commit gates | `references/communication-protocol.md` |
| one role's identity and authority | `references/roles/<role>.md` |
| where a role runs (space, tab, child terminal) | `references/placement.md` |
| another agent CLI | `references/runtime-adapters.md` |
| memory vault (opt-in, scoped read-only) | `setup.md` phase 4, `references/roles/investigator.md` |

## Pitfalls

- **The tier comes from the intake.** If a caller passes a tier that disagrees
  with the resolved shape, the resolver and the launcher should refuse rather
  than silently pick one.
- **Hash drift is a real failure.** Staging one extra file after a verifier
  passed invalidates the verdict. Re-freeze and re-verify; never amend.
- **Revision budget is two.** After that, accept what has no blocker or report
  `[STUCK]`. "One more round" is how a team burns a day.
- **A document task is not an implementation.** It does not need a coder, and
  normally needs no verifier at all.
- **A verifier reviews the diff against the gate, not the repository.** The
  `Acceptance Gate` with stable criterion IDs is the whole mandate; an assignment
  without it gets one `[STUCK] missing: acceptance gate`, not a self-invented
  standard. The `Verification Scope` block bounds the same work to the files the
  diff actually changed. Findings outside that boundary are `ADVISORY` and never
  produce `[CHANGES_REQUIRED]`. If a review is slow or is demanding a rewrite,
  check the brief's criteria and scope block before blaming the reviewer.
  Copy the shape from `examples/verifier-assignment.md`.
