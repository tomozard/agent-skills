---
name: agent-team
description: "Create and operate the minimal Herdr multi-project team: global Orchestrator, project PM and Supervisor, Planner, Worker, and Verifier tabs."
---

# Agent Team

Use this skill when creating a project workspace, assigning work, scaling a
workstream, or supervising Planner, Worker, and Verifier agents.

## Topology

The Orchestrator is global:

```text
Human
├── Orchestrator (registry, harness, project/PM lifecycle, cross-project)
│   └── PM bootstrap (one per project)
└── PM (primary project conversation after handoff)
    ├── Planner Team
    │   ├── SA
    │   ├── Investigator
    │   ├── Researcher
    │   └── Designer
    ├── approved direct Worker/Verifier path (minimal or focused)
    ├── approved direct Documenter path for document tasks
    └── Supervisor (full, multi-worker, or revision path)
        ├── Worker Team
        │   ├── Coder
        │   └── Refactor
        └── Optional Verifier Team
            ├── Reviewer
            └── Tester
```

The command chain is scoped, not a fixed startup roster:

- Orchestrator provisions or reuses the project workspace and starts PM.
- After PM acknowledges readiness, the Human talks to PM directly for project
  discovery, scope confirmation, plans, authorization gates, and results.
- PM assigns Planner agents and may directly assign approved Worker or
  Verifier roles for `minimal` or `focused` work.
- PM assigns Supervisor for `full`, multi-worker, or revision-loop work;
  Supervisor then assigns Worker and Verifier agents.
- Agents report to the controller that assigned them.
- Cross-project requests go through Orchestrator.

Bootstrap handoff is mandatory, not advisory. After Human project selection,
Orchestrator's next responsibility is to validate the registry entry,
create/reuse the project workspace, launch PM, and deliver one bootstrap brief.
Orchestrator must not investigate project state, confirm task scope, approve
plans, relay routine status or authorization gates, edit code, run project
checks, commit, or deliver remotely. If PM cannot be launched or acknowledged,
Orchestrator reports `[STUCK]` to the Human and does not take over PM or Worker
work.

## Language

- Communicate with the Human in Thai.
- Communicate between agents in English, including every task, plan, status,
  handoff, finding, and evidence payload.
- Keep technical identifiers, paths, commands, code, and source quotations in
  their original form.

When team voice mode is enabled, exactly one Human-facing controller owns voice
at a time. Orchestrator owns startup, registry, global/cross-project, handoff,
and shutdown speech. Direct Human input in a project PM pane transfers voice to
that PM; direct Human input in Orchestrator transfers it back. Other PMs and all
Supervisor, Planner, Worker, Documenter, and Verifier panes remain silent.
Agent-to-agent protocol messages never transfer voice. The owning PM speaks
its reply to a `[DONE]`, `[STUCK]`, or `[AWAITING_HUMAN_COMMIT]` result; other
protocol traffic produces no speech.

## Project Names

Project slugs are lowercase snake_case:

```text
smart_ai
crm_mobile
project_a
```

Do not use spaces or hyphens inside the project slug. Hyphens separate label
fields.

## Tab Names

```text
manager-{project}
planner-{project}
worker-{project}
worker-{project}-{workstream}
verifier-{project}
```

Use the generic Worker tab only when the project has one workstream. When a
project has multiple workstreams, suffix every Worker tab, for example:

```text
worker-smart_ai-api
worker-smart_ai-frontend
worker-smart_ai-admin
```

Do not mix generic and suffixed Worker tabs in one project.

## Pane Labels

```text
pm-smart_ai
supervisor-smart_ai
sa-smart_ai
investigator-smart_ai
researcher-smart_ai
designer-smart_ai
coder-smart_ai-api
refactor-smart_ai-api
reviewer-smart_ai
tester-smart_ai
```

Orchestrator is global and uses the label `orchestrator`.

## Capacity

Tabs have at most three left-to-right panes.

- Manager: PM and Supervisor.
- Planner: up to three active specialists. Researcher and Designer commonly
  share one on-demand position over time, not one pane.
- Worker: Coder and Refactor.
- Verifier: Reviewer and Tester.

If four Planner specialists must run concurrently, PM proposes a second
Planner tab and obtains the required capacity approval before creating it.

## Project Startup

Start or reattach the dedicated Herdr session and global Orchestrator with:

```bash
herdr-team
```

`herdr-team` validates the installed harness, opens its dedicated Herdr session,
and launches the Orchestrator automatically when absent. Inside Herdr it labels
the current pane `orchestrator` and launches through `agent-runtime`.

Orchestrator:

1. Read `{workspaces_root}/.agents/workspace-registry.yaml` as the canonical
   project index.
2. Welcome the Human in Thai. Present registered project names, descriptions,
   and statuses in Thai, then ask the Human to select a project or request
   new-project provisioning. An optional request summary may be passed to PM,
   but Orchestrator does not classify or scope the project task.
   Preserve the registry display name, but normalize its Herdr project slug to
   lowercase snake_case (`ap-bootcamp` becomes `ap_bootcamp`). Stop for Human
   input if two registered names normalize to the same slug.
3. After selection, validate only the registry entry and registered paths.
   Report missing, stale, or ambiguous registry data explicitly. Do not inspect
   Git, commits, TODO/diary files, or project source.
4. Reuse an existing project workspace when it matches; otherwise create one.
5. Label the initial tab `manager-{project}`.
6. Launch PM in the root pane as `pm-{project}`.
7. Send one English bootstrap brief containing the canonical project identity,
   paths, configured vault/activity-log paths, any verbatim Human request
   summary, and an Orchestrator reply target used only for readiness ACK or
   startup `[STUCK]`.
8. After PM readiness, tell the Human in Thai to continue in the exact
   `pm-{project}` pane and stop the turn. Do not monitor or relay subsequent
   project work unless the Human explicitly requests global or cross-project
   coordination.

The launcher supplies a configured vault root and OKF `log.md` path.
Orchestrator passes those exact paths to PM without reading vault content; PM
delegates the concise completion journal to Documenter with that exact
`log.md` path in `Allowed files`.

When the confirmed task class is `document`, launch PM with
`--task-class document`. PM remains read-only and launches the approved
Documenter directly for the Markdown/text/note files.

PM:

1. Acknowledge bootstrap readiness to Orchestrator, then become the primary
   Human-facing controller for the project.
2. Inspect project state, clarify the Human goal, and obtain direct Human
   confirmation of the scope lock and any material names.
3. Classify the task and create the smallest initial team selection.
4. Create Planner only when a specialist is needed.
5. Select Planner roles based on the task; do not spawn the full catalog.
6. Consolidate findings into one plan containing a `Team Proposal`. Present
   material behavior, naming, scope-expansion, destructive-recovery, commit,
   push, and PR gates directly to the Human. Routine bounded plans proceed
   without a second approval round after the scope gate.
7. After approval, use the selected `Execution path`: launch approved direct
   Worker or Verifier roles from PM for `minimal` or `focused` work; launch
   Supervisor and send one approved execution brief to it for `supervised`
   work.
8. Report status, blockers, authorization requests, and final evidence directly
   to the Human in Thai. Do not route routine single-project work through
   Orchestrator.

Supervisor:

1. Create Worker tabs for approved workstreams.
2. Spawn only the Worker agents required.
3. After Worker completion, create or reuse one `verifier-{project}` tab only
   when the approved proposal selects one. Reuse that tab and its available
   panes for revision verification; do not create suffixed verifier tabs for
   the same project.
4. Before creating a verifier tab, close only retired `verifier-{project}*`
   tabs whose panes are all `idle` or `done` and that do not contain current
   selected Verifier work. Never close a tab with a `working`, `blocked`, or
   `unknown` pane.
5. Spawn only the approved independent Reviewer, Tester, or both, once for the
   task. Record each selected Verifier's pane and reuse that same agent and pane
   throughout the task's revision loop.
6. Record `Revision: 0/2` for the initial result. Route a revision back to
   Worker only when a selected Verifier reports a `BLOCKER` finding tied to an
   approved acceptance criterion. Send the revised verification assignment to
   the existing selected Verifier pane with the incremented revision number.
   `Fresh verification` means rerunning checks on the revision; it does not
   mean spawning another Verifier instance or splitting another pane.
7. After `Revision: 2/2`, do not issue another revision. If all blockers are
   resolved, close with PASS and advisory notes; if a blocker remains, report
   `[STUCK]` to PM for a Human/controller decision.
8. Report the final evidence to PM.

For implementation work, verification precedes the Human commit gate. After
local checks, the Worker freezes only approved `Allowed files` through
`agent_prepare_verification_candidate`, which creates a readable staged-diff
artifact and sends `[READY_FOR_VERIFICATION]`. Every selected independent
Verifier checks that exact diff SHA-256 before and after its work and binds its
verdict to it. Any candidate change invalidates all earlier verdicts.

Only after every selected Verifier returns PASS does the controller send
`[VERIFICATION_PASSED]` with the exact hash to the original Worker. The Worker
then calls `agent_prepare_commit_review` with that verified hash. The helper
rejects index drift, creates the review artifact, and sends
`[AWAITING_HUMAN_COMMIT]` in manual mode or `[AUTO_COMMIT_READY]` in auto mode.
The Human selects auto mode only by including `AUTO_COMMIT` while approving the
scope lock. The assigned controller routes manual metadata to PM, which waits
for this directive:

```text
APPROVE_COMMIT
```

Route the directive unchanged to the commit executor: the original Worker for
a direct path, or Supervisor for a supervised path. In auto mode, the
controller validates `[AUTO_COMMIT_READY]` and permits only `agent_auto_commit`.
Raw commits are blocked. A changed branch, staged diff, or message invalidates
the verification results and approval, requiring fresh verification and a new
artifact before the Worker may report implementation `[DONE]`.

Replace a selected Verifier only when its current instance has exited, failed,
or remains unusable after the allowed diagnostic path. Retire that instance
first and reuse its existing role slot; never add a second Reviewer or Tester
pane while the prior same-role pane remains assigned to the task.

## Adaptive Staffing

The topology lists available roles, not roles that must all start. PM is the
team composer and includes this block in every plan:

```text
Team Proposal:
Task class: {advisory|document|operational|delivery|investigation|bug-fix|feature|refactor}
Risk: {low|medium|high}
Staffing: {minimal|focused|full}
Execution path: {direct|supervised}
Required roles: {comma-separated roles or none}
Optional roles: {comma-separated roles or none}
Skipped roles: {comma-separated roles or none}
Verification: {none|deterministic-micro|reviewer|tester|reviewer+tester}
Acceptance Gate: {BLOCKER criteria; ADVISORY criteria}
Revision budget: 2
Model budget: {economical|balanced|premium}
Premium reason: {none or short risk-based justification}
Reason: {short evidence-based rationale}
```

PM owns this staffing and execution-path decision. It treats the proposal as
routine execution when it fits the Human-confirmed scope, risk, and required
evidence. PM asks the Human directly only when staffing would expand the
confirmed repositories, files, behavior, workstreams, or other scope.

Selection rules:

- Planner roles are optional. Use Investigator for unknown repository facts or
  root cause, or an explicitly scoped read-only vault query; SA for
  architecture/API/data flow; Researcher for current external evidence; and
  Designer for UI/UX behavior.
- A vault query is `Task class: investigation` and uses Investigator directly
  under PM. Its task names `Knowledge source: vault`, one `Vault read scope`
  below the configured vault root, `Query`, `Excluded paths`, `Maximum
  results`, and `Required evidence`. PM passes `--knowledge-source vault` and
  `--vault-read-scope` at spawn. Missing or root-wide scope is `[STUCK]`.
  Investigator may search and quote matching notes but never mutate the vault.
  A requested write is a separate Documenter task with exact `Allowed files`.
- Direct PM execution is valid for `minimal` or `focused` tasks. Supervisor
  starts only for the `supervised` path, including full staffing, multiple
  workers, or verifier revision loops.
- Select Coder for behavior changes and Refactor for approved structural
  cleanup. Do not select both for one workstream without justified,
  non-overlapping file ownership.
- For `document` tasks, PM launches Documenter directly. Documenter writes only
  the approved Markdown/text/note files using the lightweight document model.
  Do not select Coder, Supervisor, Reviewer, or Tester merely to write a note;
  add an independent Verifier only for policy/security or behavior-significant
  documentation, runnable acceptance, or an explicit Human request. Tester is
  not valid for a document task without runnable acceptance.
- For routine `operational` tasks, select only the role needed to perform the
  bounded operation and use the operation's evidence as completion. Do not add
  a Verifier merely because a Worker was used.
- For an existing text-file numeric-only change, use the
  `deterministic-micro` verification profile on the direct path with minimal
  staffing. The shared candidate helper is the evidence role: it rejects
  non-numeric line changes, added/deleted lines, and staged-diff drift. Do not
  launch Supervisor, Planner, Reviewer, Tester, or Documenter for this lane.
  Any executable, API, auth, data, binary, or runtime change returns to normal
  independent verification.
- For `delivery` tasks, use the direct PM path with no Planner or Supervisor.
  If a frozen candidate already exists, inspect only its branch, staged diff,
  allowlist, and recorded acceptance evidence. Select at most one Coder when a
  commit is required and at most one Verifier only when evidence is missing.
  Do not restart repository discovery or create a new implementation plan for
  a resumed candidate.
- For a small known-cause bug, use `focused` staffing by default: Coder plus
  one evidence role, with no Planner unless the cause is unknown. Use `full`
  staffing only when breadth, risk, or acceptance evidence justifies it.
- Every implementation that changes executable behavior selects at least one
  independent Verifier. Reviewer supplies diff, scope, correctness,
  architecture, security, and maintainability evidence. Tester supplies
  runnable test, build, lint, and runtime evidence.
- Low-risk work may select one Verifier. Medium-risk work selects the evidence
  role or roles required by its acceptance criteria. High-risk work selects
  both Reviewer and Tester.
- Security, authentication, payments, destructive data changes, migrations,
  production infrastructure, and cross-repository behavior are high risk by
  default.

## Acceptance and Revision Gate

The approved brief must identify what can block completion and what is only an
advisory note. Reviewer and Tester report severity with every finding. Only a
`BLOCKER` tied to the approved `Required behavior` or an explicit acceptance
criterion may produce `[CHANGES_REQUIRED]`; wording, style, optional examples,
and unrelated improvements remain `ADVISORY` and do not trigger a revision.

Revision 0 is the initial result. The default and hard maximum is two revision
assignments, recorded as `Revision: 1/2` and `Revision: 2/2`. Each revision
task must include the blocker IDs that justify it. At `Revision: 2/2`, the
controller must stop: PASS with advisory notes when blockers are gone, or
`[STUCK]` with the remaining blocker evidence when they are not. No controller
may issue Revision 3 or force PASS over an unresolved blocker.

For a `document` task, use `Model budget: economical` and `Verification: none`
unless the brief names policy/security/behavior significance or runnable
acceptance. SA may provide analysis but cannot write the document; Documenter
is the scoped document writer. Premium model selection requires a written,
risk-based `Premium reason`.

## Minimal Change Gate

Treat the Human's requested observable behavior as a scope lock. Before PM
sends an execution brief, it must contain `Task class`, `Operation`, `Base branch`, `Work branch`,
`Allowed files`, `Required behavior`, `Forbidden scope`, and `Simplicity`. For
a targeted bug, default to one workstream and the smallest direct edit; do not
investigate or implement adjacent behavior unless it is required to identify
the direct cause.

The normal `implementation` operation requires a non-protected Work branch.
The bounded `protected-sync` operation is the sole exception: Base branch and
Work branch must equal the approved protected branch, Allowed files is `N/A`,
and Supervisor launches a Worker in runtime-enforced read-only mode. The Worker
may run only `git switch {branch}` and `git pull --ff-only origin {branch}` on a
clean worktree; all file edits, commits, pushes, merges, rebases, separate
fetches, and other mutations remain forbidden.

Supervisor rejects a brief missing any gate field. For `document` and routine
`operational` tasks, the brief may select no Verifier when it states the direct
completion evidence. Before editing, Documenter verifies the approved
allowlisted files and changes only those files. Documenter does not perform
branch preparation, commits, or remote delivery. For `protected-sync`, Worker must start
on the approved protected branch and perform no editing. Existing
non-protected Work branches may be reused even when their ancestry differs from
the stated base.
If an extra file, helper, abstraction, refactor, backend
change, test, or documentation change appears necessary, Worker returns
`[STUCK]` with a scope-expansion proposal instead of implementing it.

When a Reviewer is selected, it inspects the complete `base...HEAD` history and
the frozen staged candidate. Any file outside the allowlist, unrelated behavior, or avoidable complexity is
`[CHANGES_REQUIRED]`. Adjacent findings may be reported separately but are not
part of the current task without fresh Human confirmation in the active PM
conversation. Cross-project expansion requires the Human to invoke
Orchestrator.

PM proposes a non-protected `Work branch` name for implementation in the plan
so the Human may approve or rename it in that same decision round. For
`protected-sync`, PM records the approved protected branch in both branch
fields. After approval, the team owns routine reversible execution. Supervisor
passes `--base-branch` and `--work-branch` to `spawn-agent`; for implementation
the launcher creates a missing branch from the base, switches to an existing
branch when needed, or reuses the current non-protected Work branch before
Worker startup. For `protected-sync`, it only switches to the existing
approved branch after a clean-worktree check. Do not ask the Human to run local
Git or pane setup commands. Escalate only material behavior or naming choices,
scope expansion, destructive recovery, remote delivery, or another
Human-reserved action. Branch preparation stops safely on a dirty worktree,
detached HEAD, or missing local base.

## Role Selection

Planner:

- PM: scope, priorities, plan integration, project reporting.
- SA: architecture, API, data flow, integration design.
- Investigator: repository facts, reproduction, root cause, and approved
  scoped read-only vault retrieval.
- Researcher: official external documentation and evidence.
- Designer: UI, UX, interaction, and visual behavior.

Worker:

- Documenter: write only the approved Markdown/text/note files using the OKF
  contract, with no Git or remote mutation.
- Coder: implement the approved behavior.
- Refactor: approved structural cleanup without unapproved behavior changes.

Verifier:

- Reviewer: correctness, architecture, security, maintainability, scope.
- Tester: runnable tests, build/lint evidence, runtime verification.

Reviewer is never a Worker role. Verifier instances must be different from the
instances that produced the change.

## Monitoring

Completion is pushed through the communication protocol. Controllers may use
pane metadata at any time, but transcript access is restricted to direct
reports and diagnostic conditions defined in `AGENTS.md`.

After an explicit Human request, the Human-controlled external harness
operator may perform the one-shot read-only team audit defined by the `herdr`
skill. This does not make the operator a team role. The audit itself does not
permit input delivery or state mutation; the separate scoped Orchestrator
relay remains governed by the `herdr` skill. Neither capability permits
blocking waits or polling.

Do not use a blocking Herdr wait or polling loop. Do not emulate polling with
shell delays such as `sleep 30 && herdr pane list` or repeated pane metadata
checks. After assigning work, return to the conversation and wait for pushed
`[ACK]`, `[DONE]`, `[STUCK]`, `[PASS]`, or `[CHANGES_REQUIRED]` messages.

## Runtime

`.agents/team.json` schema v4 marks Orchestrator, PM, and Designer as `fixed` and
every other child role as `controller`. It stores the ordered allowlist plus machine-readable
`standard|critical` routes with one primary and explicit alternates for every
controller-selected child role. Orchestrator auto-resolves its configured default pair: Pi
with `antigravity/gemini-3.8-flash`; `herdr-team --model` may select only that
exact allowlisted startup model, and there is no
silent runtime fallback or active-session switching. Designer auto-resolves
its sole configured pair, Claude `opus`, when PM launches it and has no tier
routing.

The top-level `disabled_model_providers` array disables matching
`{provider}/...` model identifiers for every new launch without deleting their
allowlist or route entries. A disabled provider may remain in a
controller-selected tier primary or alternate. When a controller requests the
configured primary and its provider is disabled, the runtime selects the first
enabled alternate in configured order, emits and records an explicit failover
reason, and marks the effective launch as a routing exception. If no enabled
alternate exists, report `[STUCK]`; never substitute a model outside that
tier. An explicitly selected disabled alternate remains invalid, and a
disabled provider may not supply a fixed-role default. Clearing the array
re-enables those routes and does not alter an already-running session.

Before every routed child spawn, the owning controller scores that exact assignment
from 0 to 2 for Scope, Ambiguity, Reasoning, Risk, and Evidence using the shared
communication protocol. Totals 0-7 are `standard` and 8-10 are `critical`; a listed high-risk override forces `critical`. It records the complete
`Task Tier Assessment`, selects the configured tier primary, and records `Model Selection`
with Role, Runtime, Model, Routing, and Reason. It passes `--task-tier`,
`--runtime`, and `--model` to `spawn-agent`. A configured alternate also
requires `--routing-exception` and a concrete alternate reason. Missing tiers,
route mismatches, unmarked alternates, `auto`, cross-runtime or unlisted
identifiers, normalization, substitution, silent fallback, and switching an
active task are forbidden. `Model budget` must not downgrade the tier primary.
This operational choice does not require a separate Human approval round. Role
prompts remain shared across runtimes; never hand-build Pi or Claude launch
syntax in a role prompt.

For fixed PM, Orchestrator records `Runtime: pi`,
`Model: opencode-go/deepseek-v4.1-flash`, and `Routing: fixed`, then launches it
without tier routing. For fixed Designer, PM records `Runtime: claude`,
`Model: opus`, and
`Routing: fixed`, then calls `spawn-agent` without `--task-tier`. It must not
request a routing exception or substitute another model.

Example:

```bash
spawn-agent --pane <pane_id> --role reviewer --project smart_ai \
  --cwd /absolute/path/to/smart_ai --task-tier critical \
  --runtime claude --model opus
```

## Completion

A project task is complete only when:

1. For an implementation that changes executable behavior, Worker freezes the
   staged candidate and reports `[READY_FOR_VERIFICATION]` with its hash.
2. Every selected Reviewer and/or Tester returns `[PASS]` for that exact hash. A
   document, delivery, or routine operational task without a selected Verifier completes
   from the Worker's direct evidence and controller scope check.
3. The Worker sends `[AWAITING_HUMAN_COMMIT]` only after PASS in manual mode,
   then receives `APPROVE_COMMIT`; in scope-approved auto mode it sends
   `[AUTO_COMMIT_READY]` and the controller validates it. The original Worker
   on a direct path, or Supervisor on a supervised path, creates the commit.
4. That executor reports `[DONE]` with the commit SHA and integrity evidence.
5. Supervisor summarizes evidence to PM.
6. PM confirms the approved scope is satisfied and reports final completion
   directly to the Human.

For an approved advisory or investigation task with no Worker or Verifier, PM
may complete after every selected Planner reports `[DONE]` and PM consolidates
their evidence. PM must not perform omitted specialist work itself.

## Authorized Branch Push

After completion, the Human may authorize one non-protected branch push with:

```text
APPROVE_PUSH
```

The Human supplies the token directly to PM. PM routes it unchanged to
Supervisor for a supervised path or to the original Coder or Refactor for a
direct path. The selected Git executor verifies its current branch and `HEAD`,
then runs `agent_authorized_push` once and returns evidence through the same
controller chain. Protected branches, force push, deletion, tags, multiple
refspecs, and other remotes remain forbidden.

After the push succeeds, the Human may authorize one PR into `dev` with:

```text
APPROVE_PR_DEV
```

Route it through the same chain to the same Git executor. The executor uses
a readable PR body file and runs `agent_authorized_pr_create` once. The guard requires local
and `origin` commits to match. Other bases, protected heads, draft/web modes,
PR updates/review/close/merge, deploy, and release remain forbidden.

## Shutdown

A Human `/shutdown` command explicitly requests an orderly stop of the current
agent-team session. The Pi extension translates it to the existing standalone
`shutdown` handler. Orchestrator must run `agent-team-shutdown`
with every active project workspace ID it created or reused. The helper closes
those project workspaces and hands shutdown to a detached external finalizer
before the in-pane helper can be terminated. The finalizer queues `/quit`,
applies the Enter safeguard, and runs `herdr server stop` as its final command
outside Herdr panes without waiting for the client session to exit. With no
active project team, call the helper without workspace arguments.

The detached external finalizer never closes unrelated workspaces. Do not
report success after only writing a diary, saving a summary, or saying
goodbye. If the helper, handoff, or server stop fails, report `[STUCK]` with
the actual error.
