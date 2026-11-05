---
name: herdr-agent-team
description: Run a multi-agent delivery team with enforced staffing, scope locks and verification gates. Use when coordinating several AI agents on one codebase — sizing the smallest team for a task, freezing a verified diff before a commit, keeping a writer's work independent from its verifier, or auditing why a change shipped. Ships a workflow-shape resolver, a durable task board, role contracts and the delivery protocol. Tuned for the Herdr app; the policy and scripts run with any agent runtime.
---

# Herdr agent team

A delivery discipline for agent teams working on real repositories. The point is
not more agents: it is that staffing, scope, and the commit gate are decided by
rules instead of by whoever is holding the conversation.

Everything here runs without a multiplexer. Herdr is the recommended runtime —
it gives you one space per project and child terminals under each controller —
but the policy, the resolver, and the task board work with any runtime that can
spawn a process and send a message.

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

```
intake.json ──► workflow-shape ──► shape + staff + verifiers + tier
                                        │
                                        ▼
                          scope lock (Allowed files, Required behavior)
                                        │
                     worker edits ──► freeze staged diff (SHA-256)
                                        │
                     verifier(s) PASS that exact hash ──► revision budget 2
                                        │
                       Human token ──► commit ─► push ─► PR
```

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

| Layer | Roles |
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

## Communication

`references/communication-protocol.md` is the full contract: envelope, ACK /
STATUS / DONE / STUCK, file-first handoffs, dispatch accounting, the verification
loop, and the commit-review and remote-delivery gates. Two rules carry most of
the weight:

- every assignment names its reply target, and a completion is only ever pushed
  to the controller — never announced to your own session;
- a verifier sends exactly one verdict, bound to the diff hash it checked.

## What is not included

- Spawning, panes, and multiplexer plumbing. Use your runtime's own spawn
  primitive; the shape tells you which roles to start.
- Model routing enforcement. `examples/team.json` shows the expected schema
  (`model_selection`, ordered allowlists, per-tier `primary`/`alternates`); your
  launcher is what enforces it.
- Trackers and issue sync. Intake is a file here; wire it to whatever tracker you
  use and keep the same shape.

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