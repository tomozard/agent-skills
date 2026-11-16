# Team at a glance — how the work is divided

One page for the question "how many parts is this team, and how does work flow
through it?". The answer has three axes, and each axis has exactly one owner
table:

| Axis | Question it answers | Count | Section |
|---|---|---|---|
| **Authority layer** | who may decide, write, verify, report | 3 + 1 optional controller | [§1](#1-authority-layers--who-may-do-what) |
| **Delivery stage** | what happens next, in order | 8 | [§2](#2-delivery-stages--what-happens-in-order) |
| **Shape** | how big a team this task needs | 11 (`W0`–`W10`) | [§3](#3-shapes--how-big-the-team-is) |

Nothing else is a real division of the work: panes, tabs, and child terminals
are placement ([§4](#4-where-each-role-runs)), and the Human's gates
([§5](#5-what-stays-with-the-human)) cut across all three axes.

## 1. Authority layers — who may do what

```text
Human
├── Orchestrator        bootstrap only: registry, harness, project/PM lifecycle,
│                       cross-project coordination, global status, shutdown
│   └── PM bootstrap
└── PM (one per project) the single Human-facing owner of that project:
    │                   scope, staffing/gates, reporting
    ├── Planner         sa, investigator, researcher, designer   (read-only)
    ├── Worker          coder, refactor                          (write, scoped)
    ├── Verifier        reviewer, tester                         (independent)
    ├── Documenter      approved documents only
    └── Supervisor      optional controller: full / multi-worker /
                        revision-loop execution
        ├── Worker      coder, refactor
        └── Verifier    reviewer, tester
```

Three authority layers — bootstrap, project owner, execution — plus an optional
controller inserted between owner and execution. Twelve roles, and no role sits
outside those layers:

| Layer | Roles | May | May not |
|---|---|---|---|
| bootstrap | `orchestrator` | registry, harness, open/reuse a project space, start PM, cross-project, shutdown | take over discovery, planning, or implementation after handoff; relay routine project work |
| project owner | `pm` | own one project's scope, staffing, gates, and reporting; spawn approved roles; present Human gates | write repository files; verify its own work; run a second PM in the project |
| optional controller | `supervisor` | control workers and verifiers for `full` / multi-worker / revision loops; execute the guarded branch push and PR-create on a supervised path | cross human gates; invent scope |
| execution — planner | `sa`, `investigator`, `researcher`, `designer` | read; produce specs, evidence, designs | write the Spec or repository; assign work; mutate a vault |
| execution — worker | `coder`, `refactor` | edit only `Allowed files` on the approved non-protected work branch; freeze a candidate; commit after the Human token | edit outside scope; commit without a verified hash; force-push, merge, deploy |
| execution — verifier | `reviewer`, `tester` | review the frozen diff against the Acceptance Gate; one hash-bound verdict | implement what they verify; instruct other agents; poll |
| execution — document | `documenter` | write only the Human-approved Markdown/text/note files | mutate Git or any file outside `Allowed files` |

Rules that keep the layers honest:

- **The intake is the staffing gate.** One intake file per task, replayed by the
  launcher on every spawn; a role the resolved shape does not staff is a
  refused launch, not a discussion.
- **One PM per project.** A second PM splits the Human conversation and fights
  over the same work. `--force` is an explicit Human repair for a stuck PM, not
  a routine path.
- **Orchestrator hands off.** After PM readiness it reports which
  `pm-{project}` tab to continue in and stops relaying routine work.
- **Verifiers are independent instances** and never the agent (or model) that
  wrote the change. A document task is not an implementation and normally needs
  no verifier at all.
- **Cross-project work goes through Orchestrator**; a project's own work never
  does.

## 2. Delivery stages — what happens in order

| # | Stage | Owner | Output | Stop gate |
|---|---|---|---|---|
| 1 | Describe the task | PM | one intake file (JSON): task class, behavior change, risk, workstreams | intake is complete, or `[STUCK]` on a missing field |
| 2 | Resolve | `workflow-shape` | shape, staff, verifiers, tier, reasons for rejecting larger shapes | a `blocked` resolver result is `[STUCK]`, not permission to staff more |
| 3 | Lock scope | PM | `Allowed files`, `Required behavior`, `Forbidden scope`, base/work branch, `Commit mode` | Human confirms scope and proposed names |
| 4 | Execute | worker | edits inside `Allowed files` only | any out-of-scope need stops and asks for expansion |
| 5 | Freeze | worker | the staged diff as a SHA-256 plus a readable candidate artifact | staged path outside the allowlist is `[STUCK]` |
| 6 | Verify | verifier(s) | one PASS or `[CHANGES_REQUIRED]` per verifier, bound to that hash | revision budget 2, then accept or `[STUCK]` |
| 7 | Commit | worker, after the Human token | one commit whose diff is mechanically compared to the verified hash | raw `git commit` is blocked |
| 8 | Deliver | worker (direct) or controller (supervised) | one branch push and one PR into `dev`, each on its exact token | any other ref, remote, base, or PR operation is forbidden |

The freeze → verify → commit spine is the point of the discipline: a commit is
legal only for a diff hash an independent verifier already passed, and any
change to the index invalidates every prior verdict. A commit whose diff does
not match the frozen hash is `[STUCK]` — never amend or repair it without fresh
Human direction.

Stages 1–2 are resolved once for the task, stage 3 covers every workstream in
it, and stages 4–8 run per workstream.

## 3. Shapes — how big the team is

Eleven shapes, resolved from the intake. The shape names the staff, so "who
works on this?" has one answer.

| Shape | Task | Staff | Verifiers |
|---|---|---|---|
| `W0-answer` | advisory, no repository write | — | — |
| `W1-doc` | documentation only | documenter | reviewer when it changes policy or security |
| `W2-micro` | deterministic micro diff, no behavior change | coder | — (task-board proof replaces a verifier) |
| `W3-fix` | known-cause behavior fix, acceptance not runnable | coder | reviewer |
| `W4-fix-test` | known-cause behavior fix, runnable acceptance | coder | tester |
| `W5-refactor` | structural cleanup, no behavior change | refactor | reviewer |
| `W6-fix-refactor` | a fix whose root cause is structural | coder, refactor (serial) | reviewer, tester |
| `W7-feature` | new behavior; specification before code | sa (+ designer / researcher when declared), coder | reviewer, tester |
| `W8-investigate` | cause or scope unknown, or an approved vault query | investigator | — |
| `W9-ops` | operational change, no source behavior change | coder | reviewer |
| `W10-deliver` | commit/push/PR of an already verified increment | — | — |

Three knobs PM records when it executes the resolved shape:

- **Staffing mode** — `minimal` (execute and report; normally PM's direct path),
  `focused` (adds the smallest specialist or independent verifier the evidence
  needs), `full` (supervisor for multiple specialists, high risk, or revision
  loops). PM owns the choice and writes the reason in the `Team Proposal`.
- **Execution path** — `direct` is valid only for approved `minimal`/`focused`
  work; `supervised` is required for multiple workers or verifier revision
  loops.
- **Tier** — `standard` (score 0–7) or `critical` (8–10; security,
  authentication, payments, destructive data changes, migrations, production
  infrastructure, and cross-repository work always land here). The tier comes
  from the intake; a caller-supplied tier that disagrees is refused.

Selection rules the resolver enforces:

1. **Smallest shape first.** Raising the shape once needs a written reason; a
   second raise is the Human's decision. A larger shape is never justified by
   tier alone.
2. **Independent verification.** A writer and its verifier must not share a
   model. On collision the resolver tries an alternate, then a tier raise, then
   another verifier role; if none separates them it returns `partial`/`blocked`.
3. **Isolation for concurrency.** More than one independent workstream forces
   `isolation: git-worktree` and the supervised controller. Two writers never
   share one working tree.

Full fields, scoring, and the micro-config lane: `workflow-shapes.md`.

## 4. Where each role runs

| Room | Who gets it |
|---|---|
| one space per project (named by runtime slug) | every role of that project, and nothing else |
| a tab | orchestrator and PM — the two the Human talks in |
| a child terminal of its controller | every role below PM |

The controller that opens a child closes it; killing a controller ends its
descendants; depth is supported but a sidebar shows one level, so `hc ls` is the
source of truth for a parent chain. Names are `{role}-{project}` or
`{role}-{project}-{workstream}`. Details: `placement.md`.

## 5. What stays with the Human

Routine, reversible execution belongs to the team. These decisions do not:

| Gate | Directive / form | Expires when |
|---|---|---|
| Scope and work-branch approval | plan with the locked scope; `AUTO_COMMIT` may be included here to pre-authorize only the later commit | any scope change needs fresh approval |
| Local commit (manual mode) | `APPROVE_COMMIT` | branch, index, diff, or message changes |
| Branch push | `APPROVE_PUSH` | current non-protected `HEAD` only |
| PR into `dev` | `APPROVE_PR_DEV` | exactly one PR from that branch |
| Destructive recovery, scope expansion, material behavior/naming choice, cross-project work | direct conversation (cross-project via Orchestrator) | per decision |

Agents may never update, close, merge, or review a PR/MR, deploy, release,
promote, approve a production gate, force-push, delete a branch, or tag.

## 6. Where to read more

| Question | Read |
|---|---|
| start, check, or configure the app team | `launcher.md` |
| intake fields, shape catalogue, escalation, tiers | `workflow-shapes.md` |
| messages, verdicts, dispatch accounting, commit gates | `communication-protocol.md` |
| one role's identity and authority | `roles/<role>.md` |
| space, tab, and child-terminal rules | `placement.md` |
| another agent CLI, degraded modes | `runtime-adapters.md` |
