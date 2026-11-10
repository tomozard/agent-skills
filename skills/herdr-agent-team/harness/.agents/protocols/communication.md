# Communication Protocol

Herdr panes are independent processes. A reply written only in the sender's
own pane is not delivered to the controller. All inter-agent messages must be
pushed to the target pane.

## Ownership

```text
Human -> Orchestrator (registry, harness, project/PM lifecycle, cross-project, shutdown)
Orchestrator -> PM (bootstrap readiness only for routine single-project work)
Human -> PM (project discovery, scope, gates, status, and completion after handoff)
PM -> SA, Investigator, Researcher, Designer, Documenter, Supervisor, approved direct Worker/Verifier
Supervisor -> Coder, Refactor, Reviewer, Tester for supervised execution
```

Agents communicate with their controller. Cross-project communication is
routed through Orchestrator. After PM readiness, routine single-project Human
communication stays in the PM pane and is not relayed through Orchestrator.
Worker and Verifier agents do not negotiate scope directly.

## Direct PM Gateway

The Orchestrator bootstrap assignment ends after one PM readiness `[ACK]` or
startup `[STUCK]`. Its brief may carry a verbatim Human request summary, but it
does not authorize project execution. PM inspects project state and records the
Human-confirmed scope lock before dispatching any child work.

PM presents material behavior and naming choices, scope expansion, destructive
recovery, `[AWAITING_HUMAN_COMMIT]`, push, and PR gates directly to the Human.
The Human supplies exact authorization tokens in the active PM pane. PM verifies
their format and routes them unchanged to the selected Git executor. Routine
plans, status, gates, and completion do not travel through Orchestrator.

## Model Selection

Before every controller-selected direct-report spawn, the owning controller evaluates that exact
assignment, not the project as a whole. It scores five dimensions from 0 to 2,
applies any hard override, and records the result in the task or task file:

```text
Task Tier Assessment:
Scope: {0|1|2}
Ambiguity: {0|1|2}
Reasoning: {0|1|2}
Risk: {0|1|2}
Evidence: {0|1|2}
Total: {0..10}
Hard override: {none|security|authentication|payment|destructive-data|migration|production-infrastructure|cross-repository}
Tier: {standard|critical}
Evaluator: {pm|supervisor}
Reason: {short evidence-based rationale}
```

Without a hard override, totals 0-7 are `standard` and 8-10 are
`critical`. Any listed hard override forces `critical`. Scope measures the
size and spread of the assignment; ambiguity measures how much is unknown;
reasoning measures interaction and design complexity; risk measures blast
radius and reversibility; evidence measures the acceptance and verification
burden. A large mechanical assignment is not automatically hard, while a
small authentication or payment change is hard.

For a controller-selected role, the controller then chooses the tier's
machine-readable `primary` pair from the role's `routing` policy in
`.agents/team.json` schema v4 and records it:

```text
Model Selection:
Role: {direct-report role}
Runtime: {pi|claude}
Model: {exact allowlisted identifier}
Routing: {primary|alternate}
Reason: {short evidence-based rationale}
```

The controller passes the exact tier and pair to `spawn-agent` with
`--task-tier`, `--runtime`, and `--model`. A configured alternate additionally
requires `--routing-exception` and `Routing: alternate` with a concrete reason
in the task. `spawn-agent` and `agent-runtime` reject a missing tier, a pair
outside that tier, an unmarked alternate, an exception marker on the primary,
`auto`, cross-runtime identifiers, unlisted models, identifier normalization
or substitution, and switching after launch. The sole automatic failover is
from a disabled configured primary to the first enabled alternate in that
tier; the runtime records the reason and marks the effective launch as a
routing exception. If no enabled alternate exists, launch is `[STUCK]`.
Model choice is routine execution inside the existing staffing and plan
approval; it does not create a separate Human approval round. `Model budget`
records cost intent but must never downgrade the primary required by the
evaluated tier.

PM is fixed: Orchestrator does not score or pass a task tier for it. Record
`Runtime: pi`, `Model: opencode-go/deepseek-v4.1-flash`, and `Routing: fixed`, then
call `spawn-agent` without tier routing arguments.

Designer is fixed rather than controller-selected. PM does not score or pass a
task tier for Designer; it records `Runtime: claude`, `Model: opus`, and
`Routing: fixed`, then lets `spawn-agent` resolve that sole configured pair.

Model tier routing:

| Role | Easy | Advanced | Critical |
|---|---|---|---|
| PM (fixed) | Fixed: Pi / `opencode-go/deepseek-v4.1-flash` | Fixed: Pi / `opencode-go/deepseek-v4.1-flash` | Fixed: Pi / `opencode-go/deepseek-v4.1-flash` |
| SA | Pi / `antigravity/gemini-3.8-flash` | Pi / `antigravity/gemini-3.8-flash` | Claude / `opus` |
| Investigator | Pi / `opencode-go/deepseek-v4.1-flash` | Pi / `opencode-go/deepseek-v4.1-flash` | Claude / `opus` |
| Researcher | Pi / `antigravity/gemini-3.8-flash` | Pi / `antigravity/gemini-3.8-flash` | Pi / `antigravity/gemini-3.8-flash` |
| Designer (fixed) | Fixed: Claude / `opus` | Fixed: Claude / `opus` | Fixed: Claude / `opus` |
| Supervisor | Pi / `opencode-go/deepseek-v4.1-flash` | Pi / `opencode-go/deepseek-v4.1-flash` | Pi / `opencode-go/deepseek-v4.1-flash` |
| Coder | Pi / `opencode-go/deepseek-v4.1-flash` | Pi / `opencode-go/deepseek-v4.1-flash` | Claude / `opus` |
| Refactor | Pi / `opencode-go/deepseek-v4.1-flash` | Pi / `antigravity/gemini-3.8-flash` | Claude / `opus` |
| Reviewer | Pi / `kiro/claude-opus-5-5` | Pi / `kiro/claude-opus-5-5` | Claude / `opus` |
| Tester | Pi / `kiro/claude-sonnet-5-5` | Pi / `kiro/claude-sonnet-5-5` | Claude / `sonnet` |
| Documenter | Pi / `antigravity/gemini-3.8-flash` | Pi / `antigravity/gemini-3.8-flash` | Pi / `antigravity/gemini-3.8-flash` |

This table is a human-readable view of the primary routes; `.agents/team.json`
is authoritative. Orchestrator is fixed to Pi / `antigravity/gemini-3.8-flash`,
PM to Pi / `opencode-go/deepseek-v4.1-flash`, and Designer to Claude / `opus`;
none of them has task-tier routing. Reviewer and Tester carry explicit
alternates so a writer never verifies itself; those are the only configured
alternates, so a disabled primary is `[STUCK]` unless its own tier lists an
enabled alternate. A controller may
use only a configured alternate for the evaluated tier and must mark the
exception explicitly; it must not choose any other pair or switch after
launch.

## Scope Lock

Every plan and execution task file must include:

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

`implementation` requires a non-protected Work branch. For the bounded
`protected-sync` operation, Base branch and Work branch must both equal the
approved protected branch, Allowed files is `N/A`, and the Worker is
runtime-enforced read-only. It may run only `git switch {branch}` and
`git pull --ff-only origin {branch}` on a clean worktree; edits, commits,
pushes, merges, rebases, separate fetches, and other mutations are forbidden.

Controllers must preserve these fields unchanged down the command chain.
Agents may report adjacent findings, but must not implement, assign, or require
them. Any new path, behavior, abstraction, or workstream requires a scope
expansion confirmed by the Human directly in the PM conversation. Until then,
return `[STUCK]` with the smallest concrete expansion proposal. Cross-project
expansion requires the Human to invoke Orchestrator.

The plan approval also confirms the proposed `Work branch` name. After that
approval, routine reversible mechanics belong to the team: the launching
controller (PM for a direct path, Supervisor for a supervised path) passes
`Base branch` and `Work branch` to `spawn-agent`, and the launcher creates or
switches the branch before starting Coder or Refactor. An existing
non-protected Work branch may be reused as-is, even when its ancestry differs
from `Base branch`; for `protected-sync`, the launcher only switches to the
existing approved protected branch after a clean-worktree check.
Controllers must not ask the Human to run branch or other local setup commands.
Ask the Human again only for a material behavior or naming choice, scope
expansion, destructive recovery, commit or remote-delivery token, or another
Human-reserved action. A dirty worktree when creating or switching, detached
HEAD, or missing local base is `[STUCK]` with evidence rather than permission
to discard local work.

## Team Proposal

PM includes the smallest task-specific staffing proposal in every plan:

```text
Team Proposal:
Task class: {advisory|document|operational|delivery|investigation|bug-fix|feature|refactor}
Workflow shape: {W0-answer|W1-doc|W2-micro|W3-fix|W4-fix-test|W5-refactor|W6-fix-refactor|W7-feature|W8-investigate|W9-ops|W10-deliver}
Risk: {low|medium|high}
Staffing: {minimal|focused|full}
Execution path: {direct|supervised}
Required roles: {comma-separated roles or none}
Optional roles: {comma-separated roles or none}
Skipped roles: {comma-separated roles or none}
Verification: {none|deterministic-micro|reviewer|tester|reviewer+tester}
Model independence: {ok|escalated|adjusted|partial|blocked} {unresolved verifiers, if any}
Acceptance Gate: {BLOCKER criteria; ADVISORY criteria}
Revision budget: 2
Model budget: {economical|balanced|premium}
Premium reason: {none or short risk-based justification}
Reason: {short evidence-based rationale}
```

### Workflow shape resolution

PM does not choose the shape by feel. It answers the intake questions and lets
the resolver decide:

```bash
printf '%s' '{"task_class":"bug-fix","known_cause":true,
  "touches_behavior":true,"runnable_acceptance":true,"risk":"low"}' \
  | ~/bin/workflow-shape --intake - --format json
```

The resolver returns the shape, staff with models, verifiers, tier, controller,
gates, the parallel-isolation decision, the model-independence result, and the
reason every larger shape was rejected. PM records the whole `Team Proposal`
including `Workflow shape`, the shape's `Tier`, and its `Model independence`
status, then executes that shape.

Rules the resolver enforces:

- The smallest matching shape wins. Raising the shape once is allowed and must
  carry a written reason; a second raise is a Human decision.
- Every behavior change has at least one verifier. The verifier must not run the
  same model as the writer; when the routed models collide the resolver raises
  the tier, substitutes an alternate verifier, or reports the collision as
  `partial`/`blocked` with the exact fix.
- More than one independent workstream sets `isolation: git-worktree` and the
  supervised controller. Concurrent writers never share one working tree.
- `W0-answer` and `W10-deliver` open no worker pane; PM answers or delivers on
  its own authority.

A resolver result is advisory on staffing only. It never grants scope, commit,
or remote-delivery authority: those gates still come from the Human.

PM owns the staffing and execution-path choice and records why the selected
mode and controller fit the task.
For `Task class: document`, PM remains read-only and launches Documenter as the
writing agent; its `Allowed files` remain the scope lock and Documenter may not
edit source code or mutate Git.
Every completed normal project task also includes one concise OKF journal entry
in the configured `log.md`, written by Documenter through the same allowlist.
An approved `deterministic-micro` task uses its immutable Task Board event and
candidate artifact as the completion audit and may be included in the next OKF
batch; it does not launch a separate Documenter round. PM owns
routine plan execution when it fits confirmed scope, risk, and required
evidence. PM then
launches only the selected direct reports when `Execution path: direct`, and
Supervisor launches only the approved Worker and Verifier roles for the
`supervised` path. A document or routine operational task may
select `Verification: none` when its direct completion evidence is explicit.
An implementation that changes executable behavior must select at least one
Verifier unless the approved `deterministic-micro` profile proves a numeric-only
text diff. High-risk work selects both Reviewer and Tester; low-risk work may
select one; medium-risk work selects the evidence role or roles required by
the acceptance criteria. Staffing that expands confirmed project scope still
requires fresh Human confirmation in the PM conversation.

## Scoped Vault Retrieval

Vault retrieval reuses the read-only Investigator; it does not create a
Librarian role and it never turns Documenter into a search agent. PM may select
this mode only when the Human-confirmed scope requires internal vault evidence
that is unavailable from the selected repository or configured activity log.

The Investigator assignment must contain:

```text
Task class: investigation
Knowledge source: vault
Vault read scope: {one file or directory below the configured vault root}
Query: {bounded question or exact search terms}
Excluded paths: {vault-relative paths or none}
Maximum results: {positive integer}
Required evidence: {vault-relative paths plus short matching excerpts}
Mutation: forbidden
```

PM launches the assignment with `--knowledge-source vault` and
`--vault-read-scope`. `spawn-agent` and `agent-runtime` reject another role,
another task class, a missing configured vault, a missing or unreadable scope,
the vault root itself, and a path or symlink that resolves outside the vault.
Investigator searches only the resolved scope and returns evidence to PM. A
subsequent note write is a separate `Task class: document` assignment to
Documenter with exact `Allowed files`; neither the retrieval nor its evidence
implicitly authorizes a vault mutation.

## Delivery Fast Path

Use `Task class: delivery` when the Human requests a bounded commit, branch
handoff, push, or PR preparation for an existing candidate and does not request
source-code changes. Delivery work is not a bug investigation. PM must use the
direct path, skip Planner and Supervisor, and perform only this preflight:

1. inspect current branch and worktree status;
2. inspect the staged diff, allowlist, and any existing candidate hash;
3. run one explicitly named acceptance check when evidence is missing.

If the candidate state is already recorded, resume from that state. Do not
search sibling repositories, re-derive the root cause, or run repeated tests.
The fast path does not bypass the frozen-diff, independent-verification, or
Human commit authorization gates when a code commit is required. It removes
only redundant discovery and plan-approval rounds.

## Deterministic Micro Fast Lane

Use `Verification: deterministic-micro` only for an existing text-file change
where the staged candidate has paired removed/added lines with identical
non-numeric content and at least one changed number. It is direct, minimal, and
economical: Coder plus the shared deterministic candidate helper, no
Supervisor, Planner, Reviewer, Tester, or Documenter. The helper still freezes
the exact allowlist and staged-diff SHA-256, and normal commit and remote
authorization gates remain unchanged. Any non-numeric, added/deleted, binary,
behavioral, API, auth, data, or runtime change exits this lane immediately.

## Acceptance and Revision Gate

Every execution brief must define `BLOCKER` criteria and `ADVISORY` criteria.
Reviewer and Tester findings must include one of those severities and evidence.
Only a `BLOCKER` tied to `Required behavior` or an approved acceptance
criterion can produce `[CHANGES_REQUIRED]`. Wording, style, optional examples,
and unrelated improvements are `ADVISORY` notes and must not trigger a
revision.

Revision 0 is the initial result. The hard ceiling is two revision assignments,
recorded as `Revision: 1/2` and `Revision: 2/2`. A revision task must name the
blocker IDs that justify it. After `Revision: 2/2`, the controller must stop:
return PASS with advisory notes when no blocker remains, or return `[STUCK]`
with the remaining blocker evidence for a Human/controller decision. Revision
3 and a forced PASS over an unresolved blocker are forbidden.

For `Task class: document` and low-risk `Task class: operational`, use
`Model budget: economical`. A document uses `Verification: none` unless the
brief names policy/security/behavior significance or runnable acceptance, or
the Human explicitly requests verification. SA may provide analysis but cannot write
the document; `Documenter` is the scoped document writer. Tester is not valid
for a document without runnable acceptance. A balanced or premium model
requires a written risk-based `Premium reason`.

## Language

- Human-facing communication is in Thai.
- Every inter-agent envelope and body is in English, including task files,
  plans, status, review findings, test evidence, and completion summaries.
- Preserve code, commands, paths, identifiers, and source quotations exactly
  when either language is used.

## Prose Quality

Apply these rules only to narrative prose: Human-facing explanations,
document bodies, OKF journal entries, PR bodies, and prose summaries in task or
evidence files. They do not authorize rewriting machine-readable or exact-value
content.

- Lead with the concrete outcome, fact, or required action. Use plain, specific
  words, prefer active voice when it improves clarity, and split sentences that
  require rereading.
- Remove filler, flattery, promotional wording, vague attribution, generic
  conclusions, and unsupported claims. Name the source or evidence behind an
  attributed claim.
- Match the intended tone and language. Do not apply an English word blacklist
  or punctuation ban to Thai or technical writing, add opinions or personality
  to neutral operational text, or sacrifice precision to sound more human.
- Preserve verbatim code, commands, paths, identifiers, hashes, model names,
  protocol tags and fields, authorization tokens, quoted source text, and
  structured templates. Do not rewrite, reorder, translate, normalize, or
  decorate them.
- Run one self-audit before delivery and remove wording that adds no meaning,
  evidence, or action. This is an editing check, not another agent,
  verification stage, or retry loop.

These rules never alter protocol envelopes, state tags, task fields, candidate
metadata, or authorization tokens. Correctness and protocol fidelity take
precedence over style.

## Envelope

Task:

```text
[TASK] from: {sender} -> to: {receiver}
{short instruction}
Reply required: [ACK], then [DONE] or [STUCK], to pane {sender_pane}
```

At every delegation hop, `{sender_pane}` means the pane of the agent that is
assigning this task. A controller must not copy the upstream task's reply pane
when creating a child task. The child envelope must include an explicit
`Controller pane: {actual assigning controller pane}`. For supervised Reviewer
or Tester work, that pane is the Supervisor's pane; the PM pane is not a valid
verdict target.

Acknowledgement:

```text
[ACK] from: {receiver} -> to: {sender} task={id}
```

Completion:

```text
[DONE] from: {receiver} -> to: {sender} task={id} summary={summary}
```

Blocker:

```text
[STUCK] from: {receiver} -> to: {sender} task={id} reason={reason}
```

Status is sent only when requested or when a material milestone changes:

```text
[STATUS] from: {receiver} -> to: {sender} task={id} state={state}
```

Frozen verification candidate:

```text
[READY_FOR_VERIFICATION] from: {worker} -> to: {controller} task={id} artifact={path} branch={branch} diff={sha256}
```

Controller release after every selected Verifier passes the same hash:

```text
[VERIFICATION_PASSED] from: {controller} -> to: {worker} task={id} diff={sha256} evidence={references}
```

Commit review wait:

```text
[AWAITING_HUMAN_COMMIT] from: {worker} -> to: {controller} task={id} artifact={path} branch={branch} diff={sha256} message_sha256={sha256}
```

Auto-commit readiness, sent instead in scope-approved auto mode:

```text
[AUTO_COMMIT_READY] from: {worker} -> to: {controller} task={id} artifact={path} branch={branch} diff={sha256} message_sha256={sha256}
```

Controller release after it verifies that hash equals the independent
verification result:

```text
[AUTO_COMMIT_APPROVED] from: {controller} -> to: {executor} task={id} diff={sha256}
```

These are waiting states, not `[DONE]`. Controllers route the artifact metadata
upward and the exact authorization token downward without rewriting hashes.

## File-First Handoff

Write the full payload to `.agents/inbox/{role}/task-{id}.md` inside the target
project or another mutually readable absolute path when the payload is:

- longer than ten lines;
- a task specification or plan;
- an approval or revision request;
- a code snippet, diff, or shell command; or
- sensitive to shell quoting.

Then send only:

```text
[TASK_FILE] from: {sender} -> to: {receiver} file={absolute_path}
Reply required: [ACK], then [DONE] or [STUCK], to pane {sender_pane}
```

Do not stream file contents into a TUI input.

### Context Handoff Contents

When a file-first payload may be read by a fresh or resumed agent, include this
context block in English. Preserve the execution fields above; reference them
instead of duplicating their content:

```text
Context Handoff:
Next session focus: {what the receiving agent must continue}
Current state: {one concise state summary}
Completed:
- {completed work and evidence, or none}
Pending next action:
- {the smallest next action, or none}
Open decisions / blockers:
- {unresolved decision or blocker, or none}
Artifacts:
- {absolute path or URL} — {why it matters}
Suggested skills:
- {skill name and reason, or none}
Sensitive data: none / redacted
```

The `Next session focus`, `Current state`, `Pending next action`, and
`Artifacts` fields are required for a true session handoff. `Suggested skills`
must be present even when its value is `none`. Do not include API keys,
passwords, personal data, or live credentials in task files. Human remote-
delivery authorizations remain on the controller chain and must not be copied
into a context summary.

Keep the task's `Operation`, branch, allowlist, behavior, staffing, model, and
verification fields authoritative. The context block summarizes progress and
references those fields; it does not expand scope or override them.

## Delivery

Source the helpers once:

```bash
source ~/.agents/skills/agent-shared/lib/agent-helpers.sh
```

Use `send_and_submit` for short messages and `send_file_and_submit` for task
file handoffs. Delivery is serialized per target pane, then uses
`herdr pane run`, waits one second, and issues an explicit
`herdr pane send-keys <pane> enter` safeguard. This prevents concurrent
senders from interleaving text and gives the target TUI time to submit. The
bounded lock wait never polls Herdr state. Never use raw `herdr pane run` or
`send-text` for an inter-agent message.

Never send probe text such as `hello`, `test message`, or delivery experiments
to an agent pane. A successful helper exit is the delivery result; a failed
helper call must be reported as `[STUCK]` through the sender's controller.

### Dispatch Records

Controllers keep one local Dispatch Record for every child-task delivery. The
record must contain the exact `Task ID`, `Target pane`, `from`, `to`, intended
role, and delivery status. The first argument to `send_and_submit` and
`send_file_and_submit` is the recipient's `Target pane`; creating or splitting
a pane does not assign a task to it. Mark the record `status: sent` only after
the helper returns successfully. A failed helper call is a delivery failure,
not an assumed delivery, and must be escalated as `[STUCK]`.

When `[ACK]`, `[DONE]`, or `[STUCK]` arrives, the controller must match its
exact `Task ID`, sender, recipient, sender pane, and current revision to the
Dispatch Record before accepting the message as evidence or launching the
next stage. A message that does not match is `UNEXPECTED_REPLY`: do not use it
as completion evidence, do not launch follow-up work, and perform one bounded
diagnostic check of the dispatch command/target pane or the relevant child
transcript. If the route remains unresolved, send one clarification request
to the responsible child or report `[STUCK]` upstream. Do not infer delivery
from a truncated transcript, pane split, pane layout, or memory alone.

## Progress and Diagnostics

Normal progress is push-based. Do not block on Herdr state transitions.

If a required reply is missing, the controller may:

1. inspect pane metadata with `herdr pane get`;
2. send one `[STATUS_REQ]` message;
3. inspect the direct report's transcript only when the state is blocked or
   unknown, readiness failed, the status request receives no response, or a
   human explicitly requested diagnostics;
4. send `[STUCK]` to its own controller if the issue remains unresolved.

Transcript inspection must never be placed in a loop.

## Verification Loop

Every selected Verifier sends exactly one final verdict with `agent_pass` or
`agent_changes_required`:

```text
[PASS] from: {verifier} -> to: {assigning-controller} task={id} evidence={summary-or-absolute-file}
[CHANGES_REQUIRED] from: {verifier} -> to: {assigning-controller} task={id} findings={summary-or-absolute-file}
```

Do not send a result through `send_file_and_submit` and then send a second
verdict. Put detailed evidence in a file and pass its absolute path in the one
verdict message. Verifiers must not call `agent_done` after the verdict; the
single verdict is the completion handoff to their controller.

Every Verifier assignment includes `Candidate artifact` and `Candidate Diff
SHA-256`. Verifiers run `agent_verify_staged_diff` before and after their
approved work, record that hash in the evidence file, and PASS only that frozen
candidate. Mixed-hash verdicts or any index drift invalidate all PASS evidence
for the prior candidate.

Verifier does not silently implement fixes. The assigning controller sends only blocker-backed
required changes to Worker, then requests a fresh pass from every selected
Verifier. Within the same parent task, the controller sends each revision
assignment to the same selected Verifier agent in its existing pane. A fresh
pass means rerunning the approved verification against the revised result; it
does not mean spawning a fresh agent, splitting another pane, or creating
another verifier tab.

Each revision assignment uses a new revision task ID, carries `Revision: n/2`
and the blocker IDs, and receives one new verdict. Replace a Verifier only when
its current instance has exited, failed, or remains unusable after the allowed
diagnostic path. Retire that instance first and reuse the same role slot; never keep duplicate same-role Verifier
panes for one task. Verifiers return `[PASS]`
for the latest revision when no blocker remains, including any advisory notes.
At `Revision: 2/2`, the controller must not send another revision: unresolved
blockers require `[STUCK]`, not a forced PASS.

Before delivery, the assigning controller sources the shared helpers and runs
`agent_revision_gate {revision} {findings_file}`. The helper accepts only
Revision 1 or 2, requires the matching `Revision: n/2` marker, and requires a
`BLOCKER` finding.

## Human Commit Review

After local checks, the original Coder or Refactor first freezes the staged
candidate for independent verification:

```bash
agent_prepare_verification_candidate "{controller-pane}" "{worker}" \
  "{controller}" "{task-id}" "{/absolute/candidate.txt}" \
  "{allowed-file}" ...
```

The helper stages only Allowed files, requires no remaining unstaged changes
in them, writes the canonical staged diff, and sends
`[READY_FOR_VERIFICATION]`. The controller dispatches every selected Verifier
with the artifact and diff hash. After unanimous same-hash PASS, it sends
`[VERIFICATION_PASSED]` to the original Worker.

Only then does the Worker write the proposed message and Human review artifact
outside the repository and run:

```bash
agent_prepare_commit_review "{controller-pane}" "{worker}" "{controller}" \
  "{task-id}" "{verified-diff-sha256}" "{/absolute/message.txt}" \
  "{/absolute/review.txt}" \
  "{allowed-file}" ...
```

The helper does not restage. It rejects paths outside the allowlist, remaining
Allowed-files changes, or an index hash that differs from the verified hash.
It writes a readable artifact containing the message and canonical staged
diff, computes the branch, diff SHA-256, and message SHA-256, and sends
`[AWAITING_HUMAN_COMMIT]` in manual mode or `[AUTO_COMMIT_READY]` in
scope-approved auto mode.

The assigned controller routes manual artifact metadata to PM. PM presents it
directly to the Human and accepts this directive:

```text
APPROVE_COMMIT
```

The directive returns unchanged to the commit executor: the original Worker for
a direct path or Supervisor for a supervised path. In auto mode, the Human
includes `AUTO_COMMIT` with scope approval; controller validation of
`[AUTO_COMMIT_READY]` permits `agent_auto_commit`. Manual execution runs:

```bash
agent_authorized_commit "{branch}" "{diff-sha256}" \
  "{/absolute/message.txt}" \
  "APPROVE_COMMIT"
```

The helper and Git guard independently re-hash the current staged diff and
message and verify the current branch. Raw commits and missing, malformed,
stale, or mismatched tokens are blocked. Any change to the branch, index,
diff, or message invalidates prior PASS evidence and requires fresh
verification, a new artifact, and new Human authorization. Worker reports
`[DONE]` only after the authorized commit succeeds and its mechanical
committed-diff hash equals the authorized hash. Independent verification does
not run after commit.

## Remote Delivery

After the authorized local commit, a branch push requires this Human directive:

```text
APPROVE_PUSH
```

The Human supplies the token directly to PM. PM forwards it unchanged to the
Git executor: Supervisor for a supervised path, or the original Coder or
Refactor for a direct path. The executor runs:

```bash
agent_authorized_push "{branch}" "{commit}" \
  "APPROVE_PUSH"
```

The helper and Git guard require the executor's current branch and `HEAD` to
match the token and allow only `git push origin {branch}`. Protected branches,
force push, deletion, tags, multiple refspecs, and other remotes are blocked.
After the push succeeds, the Human may authorize one PR into `dev`:

```text
APPROVE_PR_DEV
```

PM routes this token through the same internal controller chain to the same
executor, which uses an explicit title and readable body file:

```bash
agent_authorized_pr_create dev "{branch}" "{commit}" \
  "{title}" "{/absolute/pr-body.md}" \
  "APPROVE_PR_DEV"
```

The GitHub guard requires matching local and `origin` commits and permits only
`gh pr create --base dev --head {branch} --title ... --body-file ...`.
Other bases, web/draft modes, PR updates, review, close, merge, auto-merge,
deployment, release, promotion, and production approval remain forbidden.

## Task Board Integration
The Task Board is a durable workspace-level operational snapshot and append-only
event history. It supplements this protocol and never replaces Herdr messages,
task files, evidence artifacts, Git history, or the OKF log. Its state root is
outside the project worktree. Use `task-board show --json` for resume/status and
never infer completion from pane metadata.

Only PM and Supervisor may create tasks or perform authoritative `transition`
commands. All team roles may append an `event`; shared helpers do this on a
best-effort, non-blocking basis for ACK, STATUS, DONE, READY_FOR_VERIFICATION,
AWAITING_HUMAN_COMMIT, AUTO_COMMIT_READY, PASS, CHANGES_REQUIRED, and STUCK. A hook failure must
not fail delivery.
Controllers confirm authoritative transitions through the explicit state table:
controller dispatch creates `queued|planned`; ACK leads to `in_progress`; a
selected Worker READY_FOR_VERIFICATION leads to `awaiting_verification` with
`--artifact` and `--candidate-diff`; unanimous same-hash PASS leads to
`verified` with `--verification`; the matching Human artifact leads to
`awaiting_human_commit`, while a scope-approved auto artifact leads to
`awaiting_auto_commit`, each with `--artifact` and `--human-gate`;
CHANGES_REQUIRED leads to `revision_required`; STUCK leads to `stuck`; and PM's
post-commit confirmation leads to `complete` with `--commit`.
Implementation tasks use `commit_required: true` and
`verification_required: true`, so the enforced order is
`in_progress -> awaiting_verification -> verified -> awaiting_human_commit|awaiting_auto_commit ->
complete`. The snapshot binds `candidate_diff_sha256`,
`verified_diff_sha256`, and `commit_sha` to those transitions. No role may
replace the push-based coordination chain, poll, block-wait, or silently
unstick a terminal task.
