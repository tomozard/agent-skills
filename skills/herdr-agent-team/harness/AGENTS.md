# AGENTS.md

This repository is the single source of truth for a minimal Herdr multi-project
agent-team runtime. It contains no product workflows, MCP catalog, presentation
tooling, or domain-specific skills. It may receive a configured vault path for
scoped daily activity journaling and explicitly approved read-only retrieval;
vault content remains outside this repository.

## Hard Rules

1. Edit this repository first. Install managed runtime files only with
   `./setup_harness.sh`; never copy them into `~/.agents`, `~/.claude`, or
   `~/bin` manually.
2. Herdr is the only supported multiplexer. Before any Herdr control command,
   require `HERDR_ENV=1`. The installed `herdr-team` launcher is the sole
   startup exception: after direct Human invocation it may target only its
   dedicated session to check server state, get/focus the global Orchestrator,
   start that Orchestrator when absent, and attach the Human client. The
   Human-controlled external harness operator may also run a one-shot read-only
   audit from outside Herdr after an explicit Human request, limited to
   `herdr workspace list`, `herdr tab list`, `herdr pane list`, and
   `herdr pane read`. After a separate explicit Human request for each
   delivery, that operator may relay one Human-authored, non-authorizing text
   message to the freshly resolved global Orchestrator pane using one
   `herdr pane run` plus one explicit Enter safeguard. This relay is the only
   input-delivery exception outside Herdr and does not require `HERDR_ENV=1`.
   The operator must not set `HERDR_ENV=1` to impersonate a team pane, target
   any other pane, relay commit or remote-delivery authorization tokens,
   perform any other mutation, retry delivery, or poll.
3. The installed CLI is authoritative. Check `herdr --help` and the relevant
   command group before changing command syntax. Check official Pi and Claude
   documentation plus each installed binary's help before changing adapters.
4. Coordination is push-based: after a dispatch, end your turn and let the
   child's message wake you. No wait, anywhere: not `hc wait`, not
   `herdr-core wait --children`, not `sleep`, not a polling loop. Earlier
   revisions permitted one `hc wait --children any` per turn; that exception is
   retired, because a two-minute block in the manager pane is a stall the Human
   pays for and the report was already on its way.
   The runtime now enforces this instead of asking for it:
   `~/.agents/extensions/role-guard.ts` refuses `hc wait`, `herdr-core wait`,
   `sleep N`, `watch -n` and `while true` at command position for every Pi role
   (log: `~/.config/herdr/role-guard.log`), and the Claude runtime carries the
   same commands as `permissions.deny`. A blocked call is the system saying the
   plan is wrong: dispatch, end the turn, and do not retry the wait in another
   form.
   A controller inspects a child's pane only when the Human asks it to, or for
   one diagnostic check when a report is overdue, the child reports itself
   blocked, or readiness failed. "See how it is going" is not a reason: the
   Human tracks the work when the Human wants to, not on the controller's
   initiative.
5. Context pressure is a stopping condition. Above 85% of the context window,
   stop starting work: write the state where the next turn can find it and end
   the turn. A pane past that point repeats itself, re-reads its whole
   transcript, and produces less than it costs. Compaction is automatic
   (`~/.agents/extensions/auto-compact.ts`, threshold 55%, log at
   `~/.config/herdr/auto-compact.log`), but it is a safety net, not an excuse to
   fill a pane.
6. Pane transcript access is restricted:
   - Orchestrator may inspect PM panes.
   - PM may inspect its Planner agents, Supervisor, and any direct Worker or
     Verifier it assigned.
   - Supervisor may inspect its Worker and Verifier agents.
   - All other roles must not inspect another agent's pane.
   - After an explicit Human request, the Human-controlled external harness
     operator may inspect any team pane read-only for a one-shot audit.
   Transcript access is diagnostic only: missing reply, blocked/unknown state,
   failed readiness, or explicit human status request. Never poll.
7. Keep each tab to at most three panes, laid out left-to-right. Create another
   labelled tab when concurrent capacity is required. This limit governs
   tab-placed panes only: roles below PM normally run as child terminals of
   their controller instead of tabs (see Child Terminals), with no tab or pane
   limit of their own.
8. Claude sessions must be launched by the runtime adapter with
   `--dangerously-skip-permissions`. The adapter must still enforce project,
   branch, role, and remote-delivery policy.
9. Shell hooks, if introduced, must be tested in an isolated process. No hook
   may assume `$?` belongs to a previous tool invocation.
10. Remote delivery is Human-authorized, not Human-executed. Supervisor may
   manage Git for supervised execution, while Coder and Refactor retain the
   direct path. They may push the exact current commit on an authorized
   non-protected branch or create an authorized PR from that branch into `dev`
   after receiving the short approval directive required below. Agents must not update/close/
   merge a PR/MR, deploy, release, or approve a production gate.
11. Local commits are verification-gated. Coder
    and Refactor must first freeze only approved `Allowed files` through
    `agent_prepare_verification_candidate`. Every selected independent
    Verifier must pass that exact staged-diff SHA-256 before the Worker may call
    `agent_prepare_commit_review` and send `[AWAITING_HUMAN_COMMIT]` in manual
    mode or `[AUTO_COMMIT_READY]` after Human scope approval with `AUTO_COMMIT`.
    Raw `git commit` is blocked; only `agent_authorized_commit` or
    `agent_auto_commit` may create the verified commit.
12. The smallest correct change is the default. For a confirmed bug fix,
    preserve the Human's stated behavior as the scope lock and do not add
    adjacent fixes, refactors, abstractions, compatibility layers, new files,
    or documentation unless they are necessary for that behavior or the Human
    explicitly expands scope.
13. After the Human approves scope and proposed names, the team owns routine,
    reversible execution. Do not ask the Human to create or switch branches,
    run local commands, prepare panes, or perform other in-scope mechanics.
    Ask again only for a material behavior or naming choice, scope expansion,
    destructive recovery, commit or remote-delivery token, or another action reserved to
    the Human by this policy.
14. Direct PM is the default Human interaction model. Orchestrator owns only
    registry, harness, project-workspace lifecycle, PM startup, cross-project
    coordination, global status, and shutdown. After PM readiness is confirmed,
    the Human continues the project conversation in the PM pane; Orchestrator
    must not relay routine plans, status, authorization gates, or completion.

## Team Model

The Orchestrator is the global bootstrap and lifecycle control plane. It opens
or reuses a project workspace and PM, then the Human works directly with that
PM:

```text
Human
├── Orchestrator (registry, harness, project/PM lifecycle, cross-project)
│   └── PM bootstrap
└── PM (primary project conversation after handoff)
    ├── Planner Team: SA, Investigator, Researcher, Designer
    ├── approved direct Worker/Verifier path (minimal or focused)
    ├── approved direct Documenter path for document tasks
    └── Supervisor (full, multi-worker, or revision path)
        ├── Worker Team: Coder, Refactor
        └── Optional Verifier Team: Reviewer, Tester
```

- Orchestrator controls PM startup and project lifecycle only. It does not
  approve or relay routine single-project work after handoff.
- PM is the Human-facing owner of one project. It confirms scope, presents
  gates, receives exact Human authorization tokens, and reports completion
  directly to the Human.
- PM controls Planner agents, Documenter, Supervisor, and approved direct
  Worker/Verifier roles for `minimal` or `focused` tasks.
- Supervisor controls Worker and Verifier agents for `full`, multi-worker, or
  revision-loop execution.
- Cross-project communication goes through Orchestrator.
- The role list is a catalog, not a startup roster. PM proposes the smallest
  task-specific team and controllers spawn only approved roles when needed.
- Every selected Reviewer or Tester must be an independent instance and must
  not implement the change it verifies. A Verifier is conditional on the task
  class and acceptance evidence; it is not a default stage for every file
  change.
- SA is a read-only Planner and must never write the Spec or assign work.
  `Documenter` is the only role that may write an approved document. Reviewer
  and Tester may report findings only to their assigning controller; they must
  never instruct SA or another agent directly.
- Within one task's revision loop, reuse each selected Verifier instance in
  its existing pane. `Fresh verification` means rerunning the approved checks
  against the new revision, not spawning a fresh agent or splitting another
  pane. Replace an unavailable Verifier only after retiring that instance, and
  reuse the same role slot rather than adding a duplicate pane.
- Reviewer and Tester verify the frozen staged candidate before any Human
  commit-review request. Each selected Verifier must check the assigned
  staged-diff SHA-256 before and after its work and bind its verdict to that
  hash. An index or Allowed-files change invalidates every prior verdict and
  requires fresh verification.
- Every approved brief must define an Acceptance Gate with `BLOCKER` criteria,
  `ADVISORY` criteria, `Revision budget: 2`, and a `Model budget`. A revision
  may be issued only for a recorded `BLOCKER` finding tied to the gate.
  `ADVISORY` findings are notes and must not cause another revision.
- Revision 0 is the initial result. The hard ceiling is two revision
  assignments (Revision 1 and Revision 2). After Revision 2, accept when no
  blocker remains, or report `[STUCK]` for Human/controller decision when a
  blocker remains; never start Revision 3 and never force a PASS over a blocker.

### Adaptive Staffing

PM owns team selection. Its plan must include a `Team Proposal` with the task
class, risk, required roles, optional roles, skipped roles, verification
selection, staffing mode, and a short reason. PM is the staffing decision-maker:
it chooses the smallest suitable team from the task class, risk, and evidence
needed. PM owns that choice as routine plan execution. The Human is consulted
only when the plan changes a material behavior or name, expands scope, needs
destructive recovery, or reaches an authorization gate; no separate staffing
approval round is required.

Supported task classes are `advisory`, `document`, `operational`, `delivery`,
`investigation`, `bug-fix`, `feature`, and `refactor`. The task class describes
the work shape; it does not force a fixed team. Staffing follows the smallest
team and evidence needed for the selected class.

Staffing modes are `minimal`, `focused`, and `full`. `minimal` uses only the
roles needed to execute and report the task and normally uses PM's direct
execution path. `focused` adds the smallest specialist or independent Verifier
needed by the acceptance evidence and may still use PM's direct path. `full`
uses Supervisor for multiple specialists, high risk, or verifier revision
loops. PM chooses the mode and records why.

### Workflow Shapes (resolver-backed)

The staffing rules below are prose; `bin/workflow-shape` is their executable
mirror, so the same intake is staffed the same way every time. PM answers the
intake questions, pipes them to the resolver, and executes the returned shape
instead of re-deriving staffing from the rules each task.

`bin/workflow-shape` and `bin/task-board` are shims: the implementation is the
`herdr-agent-team` skill in the **agent-skills** repository, installed at
`~/.agents/skills/herdr-agent-team/scripts` (`npx skills add
tomozard/agent-skills/skills/herdr-agent-team`; `HERDR_AGENT_TEAM_SCRIPTS`
overrides the path). agent-skills is the single source for both tools — never
copy them back into this repository's `bin/`, and `setup_harness.sh` refuses to
install when the skill is absent.

A controller delegates with one call: `bin/hteam-dispatch <role> --brief FILE
--request "…" --risk low|medium|high [flags]` builds the intake from flags, asks
the resolver for shape and tier, writes the intake file, and calls
`bin/herdr-app-spawn-role`. `--explain` prints the shape without a role, and the
launcher refuses any role the resolved shape does not staff. Hand-written intake
files are not part of the flow: the flags are the score.

Delegation is the default: a task that produces an outcome — evidence-based
analysis, code, config, docs, tests, a review — belongs to the role the shape
staffs. A controller works inline only when the answer needs no file or artifact
reading, changes nothing in the repository, and is a clarification, status,
direct question or tracker update; even then it records the `--explain` line
showing the resolver staffs nobody. Security, credential and CVE findings always
dispatch at `risk: high`.

| Shape | Selected when | Opens |
|---|---|---|
| `W0-answer` | advisory only, no repository write | no worker pane; PM answers |
| `W1-doc` | documentation-only change | Documenter (plus Reviewer when the document changes policy or security) |
| `W2-micro` | deterministic micro diff with no behavior change | Coder; the immutable Task Board proof replaces a Verifier |
| `W3-fix` | known-cause behavior fix, acceptance not runnable | Coder, then Reviewer |
| `W4-fix-test` | known-cause behavior fix with runnable acceptance | Coder, then Tester |
| `W5-refactor` | approved structural cleanup, no behavior change | Refactor, then Reviewer |
| `W6-fix-refactor` | a behavior fix whose root cause is structural | Coder and Refactor serially, then Reviewer and Tester |
| `W7-feature` | new behavior; specification before code | SA (plus Designer or Researcher when declared), Coder, then Reviewer and Tester |
| `W8-investigate` | cause or scope unknown, or vault discovery | Investigator (read-only) |
| `W9-ops` | operational change with no source behavior change | Coder, then Reviewer |
| `W10-deliver` | commit/push/PR of an already verified increment | no worker pane; the delivery gates only |

Four rules the resolver enforces and PM may not override:

1. **Smallest shape first.** Raising the shape once needs a written reason; a
   second raise is a Human decision. A larger shape is never justified by tier
   alone.
2. **Independent verification.** A writer and the Verifier that gates it must not
   run the same model. When the routed models collide, the resolver raises the
   tier, substitutes the other Verifier, or returns `partial`/`blocked` naming
   the exact alternate model to add. A `blocked` result is `[STUCK]`, not
   permission to verify with the writer's model.
3. **Isolation for concurrency.** Declaring more than one independent
   workstream forces `isolation: git-worktree` and the supervised controller.
   Two writers must never share one working tree.
4. **The intake is the staffing gate.** PM writes one intake file per task and
   passes `--intake <file>` on every spawn. `bin/herdr-app-spawn-role` replays
   `bin/workflow-shape` on that file, takes the task tier from it, and refuses
   any role the resolved shape does not include — so over-staffing is a refused
   launch, not a judgement call. A runnable refusal names the shape and the
   allowed roles; raising the shape needs a written reason, and asking for a
   bigger team than the shape allows is a Human decision. PM bootstrap never
   passes `--intake` (it is not a shape member).

The resolver decides staffing only. Scope, commit, and remote-delivery authority
remain Human gates exactly as specified below.

PM also records `Execution path: direct|supervised`. Direct is valid only for
approved `minimal` or `focused` work and lets PM launch selected Coder,
Refactor, Reviewer, or Tester roles directly. Supervised uses Supervisor for
multiple workers or verifier revision loops. On either path, the launching
controller passes `Base branch` and `Work branch` to `spawn-agent`.

- Planner roles are optional. Select only the specialist needed for facts that
  PM cannot establish without performing that specialist's work.
- Use Investigator for a Human-confirmed vault query without adding another
  role. The task must be `investigation`, name one read scope below the
  configured vault root plus its query, exclusions, result limit, and evidence
  format, and remain read-only. Missing or root-wide scope is `[STUCK]`.
- Supervisor is required only when the approved task selects the supervised
  path. Do not launch Supervisor during PM startup by default.
- Select Coder for behavior changes and Refactor for approved structural
  cleanup. Do not select both for one workstream unless their file ownership is
  explicitly non-overlapping and the plan justifies both.
- Every implementation that changes executable behavior must select at least
  one independent Verifier, unless the approved `deterministic-micro` profile
  proves a numeric-only text diff. Select Reviewer for diff, scope, correctness,
  architecture, security, or maintainability evidence. Select Tester for
  runnable acceptance, build, lint, or runtime evidence. A document-only change
  is not an implementation requiring a Verifier.
- Low-risk work may use one Verifier. Medium-risk work selects the evidence
  role or roles required by its acceptance criteria. High-risk work must use
  both Reviewer and Tester.
- `document` and routine `operational` tasks are lightweight by default. For a
  `document` task, PM delegates the approved Markdown/text/note files to
  Documenter; do not spawn Coder, Supervisor, Reviewer, or Tester merely to
  write a note. Add an independent Verifier only when the document changes
  policy, security, or executable behavior, or the Human explicitly requests
  it. Tester is permitted for a document only when the brief names runnable
  acceptance; otherwise use no Verifier or one Reviewer.
- `document` and low-risk `operational` tasks use the `economical` Model budget
  by default. A balanced or premium model requires a written risk-based
  reason in the plan and task; model availability alone is never sufficient.
- A small known-cause bug normally uses `focused` staffing and the direct path:
  Coder plus one evidence role, with no Planner unless the cause is unknown. A broad,
  cross-repository, or high-risk change may use `full` staffing.
- Treat security, authentication, payments, destructive data changes,
  migrations, production infrastructure, and cross-repository behavior as
  high risk unless the Human explicitly narrows the verified risk. Narrowing
  changes only the staffing risk; it never lifts the Task Tier hard override
  that forces `critical`.

## Workspace and Tab Names

Use a lowercase snake_case project slug, such as `smart_ai`.

```text
manager-{project}
planner-{project}
worker-{project}
worker-{project}-{workstream}
verifier-{project}
```

Examples:

```text
manager-smart_ai
planner-smart_ai
worker-smart_ai-api
worker-smart_ai-frontend
verifier-smart_ai
```

Pane labels use `{role}-{project}` or `{role}-{project}-{workstream}`. The
global Orchestrator pane is simply `orchestrator`.

### Child Terminals (app runtime)

In the Herdr app runtime, `bin/herdr-app-spawn-role` starts every role below PM
as a **child terminal** of the controller that assigns it (`hc run --parent`)
rather than as a tab. A child owns no tab, is listed nested under its agent in
the app sidebar, and dies with its parent. Orchestrator and PM stay tab-placed
because the orchestrator owns the global space and PM is the tab the Human
talks in; `--place tab|child` overrides the default for one launch.

- The runtime follows the tier: `herdr-app-spawn-role` reads the tier's
  `routing.primary` from `.agents/team.json`, so a `critical` coder or reviewer
  starts on `claude`/`opus` and a `standard` one on its `pi` model. `--runtime
  pi|claude` and `--model` override it; a fixed role keeps its first `pi` model.
  Hardcoding `pi` here made every critical launch fail agent-runtime's policy
  check, which is why Claude Code could never come up in the app.
- The controller that opens a child closes it. PM closes its own children when
  the task ends — reports collected, verification and commit gate reached, or
  `[STUCK]` — and a worker closes any child it opened before it reports.
- Cleanup cascades: `hc kill` on a parent also ends its descendants, so a
  controller never has to hunt grandchildren.
- Nesting is runtime-supported (a child may open its own children; `hc ls`
  shows the `parent` chain at any depth), but the app sidebar renders one level.
  Deeper descendants are visible only through `hc ls` and `hc read`.

### One space per project

Every project gets its **own app space named after its runtime slug**; the
control space holds only the Orchestrator (and the ClickUp intake watcher). A
project role is always launched with `--project <slug>`, which creates or
reuses that space, and the launcher refuses a project role without it and
refuses `--space` alongside it. Opening a project therefore never mixes its
panes into another project's space, and closing a project's last terminal
closes only that project's space.

### One PM per project

A project has exactly one PM — its chief of staff: the single Human-facing owner
of that project's scope, staffing, gates, and completion. `bin/herdr-app-spawn-role`
refuses to start a second PM in a project's space. It keeps a spawn-time registry
(`$HERDR_TEAM_STATE_DIR/pm/{project}.terminal`, override
`HERDR_TEAM_PM_REGISTRY`) because the app assigns its own `where` label a moment
after a terminal appears — a guard that only reads `hc ls` misses a PM spawned
seconds earlier. A live-terminal scan remains as a fallback for panes started
outside the launcher. `--force` is the explicit Human override for a genuinely
stuck PM; it is never a routine path.

## Workspace Registry

The global Orchestrator uses
`{workspaces_root}/.agents/workspace-registry.yaml` as the canonical project
index. At startup it presents the registered projects and asks the Human to
select one or request new-project provisioning. After selection it validates
only the registry entry and project paths, then creates or reuses the project
workspace and starts PM. Orchestrator does not inspect project Git/TODO/diary
state or confirm task scope; PM performs project discovery and scope
confirmation directly with the Human after handoff.
Registry display names may contain hyphens; convert only the Herdr runtime slug
to lowercase snake_case and keep the registered name and path unchanged.

The launcher supplies the vault root and the configured OKF `log.md` path.
Orchestrator passes those exact paths to PM without reading or writing vault
content. PM delegates one concise OKF completion journal entry to Documenter with
that exact `log.md` path in `Allowed files` for normal tasks. An approved
`deterministic-micro` task uses its immutable Task Board event and candidate
artifact as the completion audit and may be batched into the next OKF entry;
it must not be blocked on a separate Documenter round.

PM may separately launch Investigator for an approved scoped vault query using
`Task class: investigation`, `Knowledge source: vault`, and one `Vault read
scope` below the configured root. The assignment must also state `Query`,
`Excluded paths`, `Maximum results`, `Required evidence`, and `Mutation:
forbidden`. Investigator returns vault-relative paths and excerpts to PM. It
must not scan the vault root, escape the scope through symlinks, read excluded
or unrelated notes, or mutate vault content. A requested write is a separate
Documenter task with exact `Allowed files`.

## ClickUp Intake

`bin/clickup-watch` is Human-authorized intake infrastructure, not a role. When
`hteam` runs it, it polls the ClickUp lists of the projects whose registry entry
sets `clickup: { auto_intake: true }` — every 30 minutes, and no other project's
list — for tasks in the trigger status (`to do`) and pushes a brief to that
project's PM pane. It is a plain loop, not an agent: a poll spends no model
tokens. It never writes code, never touches Git, and never assigns a Worker.
Auto intake is off for every project until that flag is set, so the watcher
polls nothing by default.

- The project is the list the task came from. A `project: <slug>` line in the
  task description overrides it; the watcher must never guess a project from
  free text. Only when it is run against a single unmapped list (config
  `list_id`) does it fall back to matching the task text, and an unresolved task
  is then moved to `discuss` with a comment stating what is missing.
- The watched list is shared with people, so intake is opt-in on two counts:
  the task must carry the configured tag (default `agent-team`) **and** be
  assigned to this instance's own ClickUp user (default `me`). Each herdr-team
  person has a different ClickUp login, so this keeps two instances from taking
  each other's work. A task failing either test is never read further,
  commented on, moved, or assigned.
- A claimed task is assigned to the agent's ClickUp user, moved to
  `in progress`, and annotated with a comment naming the project and receiving
  pane. An assignee a person already holds is never replaced; the claim is
  skipped and logged.
- The loop is two-way. When PM needs a decision or missing information it runs
  `clickup-watch ask --task <id> --text "<question>"`, which writes a
  `[herdr-team]` comment and parks the task in `discuss`. The Human answers in
  ClickUp and moves the task back to `to do`; the next poll re-dispatches it with
  those answers quoted in the brief. PM may run that one helper (ClickUp only —
  it grants no file, Git, scope, commit, push, or PR authority); no other
  ClickUp write by an agent is allowed.
- The watcher also watches its own claims: a task it dispatched that stays
  `in progress` with no ClickUp activity for `stale_hours` (default 8) is
  commented and moved to `discuss`, so a dead pane or a forgotten task returns
  to the Human instead of hanging. This nudge needs no Human authorization.
- Delivery target is the PM pane whose tab is `pm-{runtime_slug}` (registry
  `ap-intranet` → `pm-ap_intranet`). A bare `pm` pane belongs to another project
  and is never used. With no PM live, the watcher asks the Orchestrator to open
  that project's workspace and PM, and leaves the task in `to do` until a PM
  exists; the request repeats at most every 30 minutes.
- An intake brief grants no scope, commit, push, or PR authority. PM must still
  present its plan, `Allowed files`, `Required behavior`, `Forbidden scope`, the
  non-protected `Work branch`, and the explicit gate-versus-`AUTO_COMMIT`
  question to the Human in its own pane, and wait for approval before dispatch.
- Status ownership is explicit, because otherwise nobody updates it:
  the watcher writes `to do` → `in progress` on handoff and `to do` → `discuss`
  on ambiguity or a stale claim; **PM owns every later status** and does it with
  `clickup-watch mark --task <id> --status "in progress|discuss|ready"`, which
  also comments. PM marks a finished task (or a finished subtask) `ready`;
  `done`, `reject`, `complete`, merging, and re-prioritising stay with the Human.
  Workers never touch ClickUp.

## Minimal Change and Scope Lock

Before execution, the approved brief must state:

```text
Operation: {implementation|protected-sync}
Base branch: {intended PR base}
Work branch: {approved non-protected implementation branch}
Allowed files: {exact paths}
Required behavior: {one observable outcome}
Forbidden scope: {adjacent behavior that must not change}
Simplicity: {smallest direct change; no new abstraction unless required}
Commit mode: {manual|auto}
```

For the bounded `protected-sync` operation, `Base branch` and `Work branch`
must both equal the approved protected branch, `Allowed files` is `N/A`, and
the required behavior must be local branch synchronization only. Supervisor
may launch Coder or Refactor for this operation, but the runtime downgrades the
Worker to read-only and permits only `git switch {branch}` and
`git pull --ff-only origin {branch}` on a clean worktree. Editing files,
committing, pushing, merging, rebasing, fetching separately, and every other
mutation remain forbidden.

- A targeted bug fix defaults to one workstream and only the Planner specialist
  needed to locate its direct cause. Possible adjacent bugs are findings, not
  authorization to change them.
- Before editing, Coder or Refactor must verify that the current branch is the
  approved non-protected `Work branch`. Existing non-protected Work branches
  may be reused, including when their ancestry differs from `Base branch`;
  never repair that branch by deleting/recreating it, rebasing, or force
  pushing without a new Human instruction. A `protected-sync` Worker must not
  edit at all and must follow only its two approved sync commands.
- After local checks, Coder or Refactor must stage only the exact `Allowed
  files` through `agent_prepare_verification_candidate`. The helper freezes a
  canonical staged diff, writes a readable candidate artifact, and sends
  `[READY_FOR_VERIFICATION]` with its SHA-256. Any staged path outside the
  allowlist is `[STUCK]`; do not unstage or overwrite unrelated Human work.
- After every selected Verifier returns PASS for that exact hash, the assigning
  controller sends `[VERIFICATION_PASSED]` with the hash to the original
  Worker. Only then may the Worker call `agent_prepare_commit_review` with that
  verified hash. The helper rejects changed Allowed files or an index whose
  hash differs, then writes the review artifact and sends
  `[AWAITING_HUMAN_COMMIT]` or `[AUTO_COMMIT_READY]` according to the approved
  commit mode.
- PM proposes the non-protected work-branch name during implementation plan
  approval. For `protected-sync`, PM records the approved protected branch in
  both branch fields and Supervisor passes `--operation protected-sync` and
  `--sync-branch` to `spawn-agent`. The launcher only switches to an existing
  sync branch after confirming a clean worktree; it never creates, deletes, or
  repairs that branch. A dirty worktree when creating or switching, detached
  HEAD, or missing local base is `[STUCK]` because resolving it could overwrite
  or mix unapproved work.
- Worker may modify only the allowed files. If another file, helper,
  abstraction, refactor, backend change, test, or documentation change becomes
  necessary, stop and request a scope expansion through the controller chain.
- Reviewer must inspect both the complete `base...HEAD` history and the frozen
  staged candidate, reject files outside the allowlist, and reject avoidable
  complexity even when tests pass. Tester must run acceptance against the same
  candidate hash. Both recheck the hash before their final verdict.
- Scope expansion requires fresh Human confirmation directly in the active PM
  conversation and an updated scope lock before any new work is dispatched.
  Cross-project expansion requires the Human to invoke Orchestrator.

## Communication

### Language Policy

- Every agent must communicate with the Human in Thai. Keep code, commands,
  paths, identifiers, and quoted source text in their original form.
- All agent-to-agent tasks, acknowledgements, status messages, plans,
  handoffs, findings, and evidence must be written in English.
- The Orchestrator's first Human-facing response must welcome the Human in
  Thai before presenting registered projects and asking which project to open.
- After handoff, PM is the primary Human-facing agent for that project and must
  communicate with the Human in Thai. Orchestrator remains on demand only.
- With voice mode enabled, exactly one Human-facing controller owns speech:
  Orchestrator for startup/global/cross-project/handoff/shutdown, or the PM that
  most recently received direct Human input. Agent-to-agent protocol traffic,
  background PMs, and every other role remain silent.
- Voice is enabled per launch, never left implicit: `hteam --voice on` (or
  `HERDR_VOICE_MODE=on`) puts `HERDR_VOICE_MODE` into the Orchestrator's argv and
  `bin/herdr-app-spawn-role` forwards it to every child it starts, so the whole
  team agrees on one mode. `hteam check` reports the effective mode and whether
  the TTS adapter (`bin/tts-thai.sh`) is present; `off` is the default. The
  engine is VoiceStudio `omnivoice` through `bin/tts-speak-omni` — the voice the
  Human picked is the Thai-native profile `c3141426` at speed 0.9 with a light
  band-pass chain (120 Hz–7.5 kHz, gentle compression, -16 LUFS, no reverb) — and gTTS is the fallback when VoiceStudio is not running,
  so a machine without the backend still speaks. `HERDR_GTTS_CLI` selects the
  gTTS binary, `HERDR_VOICE_SPEED` the rate, `VS_URL`/`TTS_OMNI_VOICE` the
  VoiceStudio backend and profile. There is still no macOS `say` fallback: the
  team never speaks in a voice nobody chose.
- The ClickUp intake watcher follows the same rule: `hteam --watch on` (or
  `HERDR_TEAM_WATCH=1`) starts it in its own tab of the control space, and
  `off` is the default, so a plain `hteam` never polls ClickUp behind the
  Human's back. `--watch` takes the same `on|off` vocabulary as `--voice`
  (`--no-watch` survives as an alias for `--watch off`), and `hteam check`
  reports the effective mode.
- `hteam` is also a Pi command: `/hteam [check] [--voice on|off] [--watch on|off]` from any Pi
  session runs the same launcher (`~/.pi/agent/extensions/hteam.ts`), and refuses
  to start a second team when the session is already a team pane. Install it with
  `./setup_harness.sh`; never copy the extension by hand.
- `/hteam setup` writes the per-machine launcher config
  (`~/.config/herdr-team/hteam.yaml`: space, folder, voice, watch, repo,
  registry, vault, activity log) and lets the Human pick the depth: `เริ่มต้น`
  asks space/folder/voice/watch, `เร็ว` accepts the detected values after one
  confirmation, `ละเอียด` edits each path and ends with a review. Precedence is
  flag > env > config file > default; `hteam-config show` prints the source of
  every value and refuses an invalid file before any launcher reads it.

Every assignment has an explicit reply target:

```text
[TASK] from: {sender} -> to: {receiver}
{short body}
Reply required: [ACK], then [DONE] or [STUCK], to pane {sender_pane}
```

- Use `[ACK]`, `[STATUS]`, `[DONE]`, and `[STUCK]`.
- Task specifications, plans, approvals, revision requests, code snippets,
  diffs, shell commands, payloads sensitive to shell quoting, or messages
  longer than ten lines must be written to a readable file. Send only a short file
  path ping with `send_file_and_submit`.
- Use only the shared helpers for inter-agent delivery. They call
  `herdr pane run`, wait one second, then send an explicit Enter safeguard,
  with delivery serialized per target pane. Roles must not call raw
  `herdr pane run` or `send-text` for messages.
- Reviewer and Tester send exactly one final verdict with `agent_pass` or
  `agent_changes_required` when selected. The assigning controller's own pane
  is the verdict target; when Supervisor delegates, the Verifier must not reuse
  PM's upstream reply pane. Never send duplicate result pings or probe/test
  messages to another agent pane.
- Never send a completion only to your own pane. Push it to the controller.

## Runtime Policy

- Supported runtimes: Pi and Claude.
- `auto` is valid only for fixed roles and resolves their configured default
  pair; it never falls back. The global Orchestrator defaults to Pi
  `antigravity/gemini-3.8-flash`; `herdr-team --model` accepts only that exact
  allowlisted model. PM is fixed to Pi `antigravity/gemini-3.8-flash` and is launched
  by Orchestrator without tier routing. PM is the Human-facing pane in a chat
  surface that accepts images, so it shares the multimodal Orchestrator model
  rather than a text-first one. Designer is the fixed child role and
  resolves only Claude `opus` when PM launches it. Documenter and Researcher
  use Pi `antigravity/gemini-3.8-flash` for every tier, and the Planner,
  Supervisor, and Verifier tiers rotate across three Pi families
  (`opencode-go/deepseek-v4.1-flash`, `kiro/gpt-5-6-luna`,
  `antigravity/gemini-3.8-flash`) so planning and review never run on a single
  model lineage; Supervisor uses the fast Pi model at every tier. Every judgment
  or implementation critical tier uses Claude `opus`, except Tester which uses
  Claude `sonnet`.
- A runtime is selected only at spawn time; do not switch an active task.
- `.agents/team.json` schema v4 is the canonical ordered model allowlist and
  machine-readable tier-routing policy. It uses
  `model_selection: fixed|controller`, runtime-keyed arrays under `models`, and
  `standard|critical` routes with one `primary` and zero or more explicit
  `alternates` for every controller-selected role. Reviewer and Tester carry
  alternates so a writer never verifies itself. Fixed Orchestrator, PM, and
  Designer have no tier routing.
- The top-level `disabled_model_providers` array disables matching
  `{provider}/...` model identifiers for every new launch while preserving the
  allowlist and routes for one-line re-enablement. A disabled provider may
  remain in a controller-selected tier primary or alternate. When the requested
  tier primary is disabled, the runtime must select the first enabled alternate
  in configured order, emit and record an explicit failover reason, and mark
  the launch as a routing exception. If no enabled alternate exists, launch is
  `[STUCK]`; never substitute a model outside that tier. A disabled provider
  must not supply a fixed-role default. Changing this setting does not switch
  or stop an active agent session.
- Before every routed direct-report spawn, the owning controller scores that exact
  assignment from 0 to 2 for Scope, Ambiguity, Reasoning, Risk, and Evidence.
  Totals 0-7 are `standard` and 8-10 are `critical` (the retired middle tier
  is folded into `standard` because the standard models now carry general work
  that used to need it); security,
  authentication, payments, destructive data changes, migrations, production
  infrastructure, and cross-repository behavior force `critical`. It records the
  complete `Task Tier Assessment` and a `Model Selection` block containing
  Role, Runtime, Model, Routing, and an evidence-based Reason.

### Micro-config lane (Human-approved default)

A change that only edits configuration — a CI/CD file, a pinned variable, a
dead workflow file being deleted, ≤ ~5 changed lines, no application or runtime
behaviour — is scored on its blast radius, not on the subject it mentions. It is
`risk: low|medium`, resolves `standard`, and runs on the tier's `pi` primary
with **one** independent Verifier (Reviewer). Do not add a second Verifier for
it, and do not mark it `critical` merely because the file lives in CI or touches
infrastructure: `critical` is for decisions that need judgement — logic,
security, payments, migrations, cross-file behaviour, destructive data changes.

Two shapes are deliberately cheaper and are expected for repetitive work:

- **One Coder, several repositories.** When the same edit repeats across
  repositories, one Coder walks them in sequence in one session instead of a
  fresh Coder per repository. Parallel Coders are allowed only while each has
  its own worktree.
- **Deterministic lane.** A literal edit the Human spelled out (delete this
  line, rename this key) may run as `W2-micro`, where the Task Board proof —
  hash, Allowed files, commit gate — replaces a model Verifier. Never use this
  lane for anything the Human did not state explicitly.

Spawning four `opus` Coders to delete four lines is a policy error, not
diligence: the mechanical guarantees (staged-diff SHA-256, Allowed files, commit
gate and post-commit integrity check) are what produce quality here, and they
cost the same on `pi`. Record the lane you chose in the `Task Tier Assessment`
with one line of why.
- The controller passes `--task-tier`, `--runtime`, and `--model` to
  `spawn-agent`. An alternate additionally requires `--routing-exception` and
  a recorded alternate reason. Missing tiers, mismatched pairs, unmarked
  alternates, exception markers on primaries, `auto`, cross-runtime or unlisted
  identifiers, normalization, substitution, silent fallback, and switching
  after launch are forbidden. `Model budget` must not downgrade the evaluated
  tier's primary. For fixed Designer, PM records Claude `opus` as
  `Routing: fixed` and launches it without `--task-tier`; Orchestrator does the
  same for fixed PM. `spawn-agent` resolves each sole configured pair. Model selection is routine execution
  and has no separate Human approval round.
- Agent roles are runtime-agnostic and live in `.agents/agents/*.md`.
- Pi receives the common and role prompts through its system-prompt interface.
- Claude starts the corresponding main-session custom agent.
- The runtime does not install CLIs, authenticate accounts, or manage secrets.
- Coder and Refactor must not start on protected branches for implementation:
  `dev`, `uat`, `main`, `master`, or `prod`. The only exception is the
  runtime-enforced `protected-sync` operation described in the scope lock;
  that exception is read-only and cannot authorize code changes or remote
  delivery.

### Role Enforcement

- `orchestrator`, `supervisor`, Planner roles, Reviewer, and Tester are
  runtime-enforced read-only roles. PM is read-only. A Documenter launched
  with `Task class: document` may write only the Human-approved Markdown/text/
  note files and still cannot mutate Git. The branch-bootstrap exceptions are
  the trusted `spawn-agent` path: for implementation it may create or switch
  to the approved non-protected `Work branch` from the approved local `Base
  branch`; for `protected-sync` it may only switch to the existing approved
  protected branch after safety checks.
- Only `documenter` has scoped document-write capability without Git mutation;
  only `investigator` has scoped vault-read capability, and only for an
  approved `investigation` task launched by PM with a validated descendant
  scope;
  only `coder` and `refactor` have repository write capability. The original
  Worker on a direct path, or Supervisor on a supervised path, may create a
  local commit on an approved non-protected branch only after `APPROVE_COMMIT`
  is relayed, or after scope-approved `AUTO_COMMIT` and controller validation;
  the corresponding helper revalidates the live candidate.
- After Human project selection, Orchestrator must create/reuse project
  topology and spawn PM. It sends one bootstrap brief, waits only for PM
  readiness, and tells the Human which `pm-{project}` pane to continue in. If
  startup fails, it reports `[STUCK]`; it never takes over discovery,
  planning, or implementation.
- Supervisor performs authorized branch push and PR creation for supervised
  execution; Coder and Refactor may do so for the direct path. PM receives the
  exact Human token directly in the PM conversation and forwards it to
  Supervisor, which runs the guarded Git operation for supervised execution.
  The same chain routes an exact PR-create token to
  `agent_authorized_pr_create`; these two token-authorized actions are carried
  out by the selected Git executor, not by the Human. All other PR/MR operations
  remain with the Human-controlled external operator.
- The Human-facing Pi `/shutdown` command (and the standalone `shutdown`
  compatibility form) requires Orchestrator to run the
  installed `agent-team-shutdown` helper. It closes only owned project
  workspaces and hands shutdown to a detached external finalizer. The
  finalizer queues `/quit`, applies the Enter safeguard, and runs the
  default-session `herdr server stop` command as its final command outside
  Herdr panes.

## Commit and Remote Delivery

After local checks, the original Coder or Refactor freezes only approved files
with `agent_prepare_verification_candidate`. The assigning controller launches
the selected independent Verifiers against its candidate artifact and staged
diff SHA-256. Every PASS must name that same hash. A blocker or any candidate
change returns the task to the Worker and invalidates all earlier PASS results.

Only after all selected Verifiers pass does the controller send the exact
`[VERIFICATION_PASSED]` hash to the original Worker. Every implementation scope
lock records `Commit mode: manual|auto`. The Human may include `AUTO_COMMIT`
when approving that scope lock; it pre-authorizes only the later commit for the
verified candidate, never push or PR creation. The runtime records this mode at
Worker launch and the Worker still calls `agent_prepare_commit_review`, which
re-hashes the frozen index and creates a readable artifact.

Manual mode sends `[AWAITING_HUMAN_COMMIT]`; PM presents the evidence and the
Human replies `APPROVE_COMMIT`. Auto mode sends `[AUTO_COMMIT_READY]`; the
controller verifies its hash equals the independent verification result,
records `awaiting_auto_commit`, and sends `[AUTO_COMMIT_APPROVED]` to the
executor without another Human round. Only `agent_authorized_commit` or
`agent_auto_commit` may commit. Raw `git commit` is blocked. Both helpers and
the Git guard independently verify the non-protected branch, staged-diff hash,
and message hash. Any branch, index, diff, or message change requires fresh
verification and a new artifact; auto approval never survives that drift.

After the authorized commit, the helper mechanically compares the created
commit diff with the verified staged-diff SHA-256. This is an integrity check,
not another review or test stage. A mismatch is `[STUCK]`; do not amend or
repair the commit without fresh Human direction.

After a successful local commit, the Human may authorize one branch push by
sending `APPROVE_PUSH`, and one PR into `dev` by sending `APPROVE_PR_DEV`.
The selected executor may push only its current non-protected `HEAD` to
`origin` through `agent_authorized_push`, then create only one matching PR with
`agent_authorized_pr_create`. Guards bind each short directive to the actual
current branch and commit. Force push, deletion, tags, multiple refspecs,
other remotes, other PR bases, PR updates, review, close, merge, auto-merge,
deployment, release, promotion, and production approval remain forbidden.

## Routing Map

- `.agents/team.json`: canonical roles, ownership, and runtime order
- `.agents/agents/`: runtime-agnostic role definitions
- `.agents/skills/herdr/`: Herdr command and safety baseline
- `.agents/skills/agent-team/`: topology, naming, and lifecycle
- `.agents/skills/agent-shared/`: communication helpers
- `.agents/protocols/communication.md`: message and escalation contract
- `~/Workspaces/.agents/workspace-registry.yaml`: global project index
- `bin/herdr-team`: validate the harness and start the global Orchestrator
- `bin/agent-runtime`: launch a role in the current Herdr pane
- `bin/spawn-agent`: launch a role in another Herdr pane
- `bin/verify-pane-agent`: verify pane metadata without transcript access
- `bin/agent-team-shutdown`: close owned project teams and exit Orchestrator
- `bin/guard-bin/`: runtime Git and GitHub command guards
- `tests/validate.sh`: repository validation
- `setup_harness.sh`: the only supported installer
