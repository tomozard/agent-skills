---
name: agent-shared
description: "Shared push-message helpers for the Herdr agent team. Use for TASK_FILE, ACK, STATUS, DONE, and STUCK delivery."
---

# Agent Shared

Source the helper library in every role session:

```bash
source ~/.agents/skills/agent-shared/lib/agent-helpers.sh
```

Available functions:

```text
send_and_submit <target_pane> <from> <to> <message>
send_file_and_submit <target_pane> <from> <to> <file> [task_id]
agent_ack <target_pane> <from> <to> <task_id>
agent_status <target_pane> <from> <to> <task_id> <state>
agent_done <target_pane> <from> <to> <task_id> <summary>
agent_stuck <target_pane> <from> <to> <task_id> <reason>
agent_pass <target_pane> <from> <to> <task_id> <evidence>
agent_changes_required <target_pane> <from> <to> <task_id> <findings>
agent_revision_gate <revision> <findings_file>
agent_prepare_verification_candidate <target_pane> <from> <to> <task_id> <candidate_file> <allowed_file>...
agent_verify_staged_diff <expected-diff-sha256>
agent_prepare_commit_review <target_pane> <from> <to> <task_id> <verified-diff-sha256> <message_file> <review_file> <allowed_file>...
agent_authorized_commit <branch> <diff_sha256> <message_file> <exact_authorization>
agent_authorized_push <branch> <commit> <exact_authorization>
agent_authorized_pr_create <base> <head> <commit> <title> <body_file> <exact_authorization>
agent_jev_advisory <state_file> <questions_file>
```

The first argument is always the recipient's target pane, not the sender's
current pane. The helpers reject an accidental self-target when
`HERDR_PANE_ID` identifies the sender pane. They require `HERDR_ENV=1`.
Delivery is serialized per target pane so
multiple agents cannot interleave text in one controller input. Inside that
lock it uses `herdr pane run`, waits one second, sends an explicit
`herdr pane send-keys <pane> enter`, and allows a short settle interval before
the next sender. The second Enter is a deliberate startup-race safeguard. The
lock wait and delays are bounded and never inspect or poll Herdr state. Do not
call `herdr pane run` or `send-text` directly for inter-agent messages; always
use these helpers.

Use file-first handoff for payloads longer than ten lines or containing plans,
approvals, code, diffs, or shell commands.

When `HERDR_TASK_BOARD_PROJECT`, a task id, and an available `task-board` CLI
(or `HERDR_TASK_BOARD_BIN`) are configured, the protocol helpers append
best-effort Task Board events for ACK, STATUS, DONE, PASS,
CHANGES_REQUIRED, STUCK, READY_FOR_VERIFICATION, and
AWAITING_HUMAN_COMMIT. These hooks are guarded,
non-blocking, and never cause Herdr delivery to fail. They append events only;
authoritative state transitions remain controller-only.

File-first payloads that may be resumed by a fresh agent must also include the
`Context Handoff` block defined in `.agents/protocols/communication.md`, with
the next-session focus, current state, pending action, artifact references,
suggested skills, and a sensitive-data status. Do not copy secrets or Human
remote-delivery authorizations into that summary.

Reviewer and Tester must use `agent_pass` or `agent_changes_required` exactly
once for their final verdict. The evidence/findings argument should be a short
summary or an absolute result-file path. Do not send a result file first with
`send_file_and_submit` and then send a duplicate verdict. Never send probe,
hello, or test messages to another agent pane.

Supervisor must run `agent_revision_gate` before sending a revision. It accepts
only Revision 1 or 2, requires the matching `Revision: n/2` marker, and requires
a `BLOCKER` finding; advisory-only findings cannot start another revision.

Coder and Refactor must use `agent_prepare_verification_candidate` after local
checks. Its candidate artifact must be outside the repository. When
`HERDR_VERIFICATION_PROFILE=deterministic_micro`, the helper additionally
requires paired removed/added text lines with identical non-numeric content and
at least one changed number; otherwise it returns a blocker before delivery.
The helper rejects staged paths outside the explicit `allowed_file` arguments, stages
only those arguments, requires no remaining unstaged change in those paths,
freezes the canonical staged diff, and sends:

```text
[READY_FOR_VERIFICATION] ... artifact={path} branch={branch} diff={sha256} verification={profile}
```

Reviewer and Tester call `agent_verify_staged_diff` before and after their
approved checks. Their evidence must name the exact hash. If the hash changes,
return `[CHANGES_REQUIRED]`; prior PASS results are invalid.

Only after the assigning controller sends `[VERIFICATION_PASSED]` with the
unanimously passed hash may the Worker call `agent_prepare_commit_review`. The
message and review artifact files must be readable files outside the
repository. The helper does not restage; it requires the frozen Allowed files
and index to match the verified hash, writes the commit message and staged diff
to the review artifact, records the branch plus verified diff and message
SHA-256 values, and sends `[AWAITING_HUMAN_COMMIT]` in manual mode or
`[AUTO_COMMIT_READY]` in scope-approved auto mode:

```text
[AWAITING_HUMAN_COMMIT|AUTO_COMMIT_READY] ... artifact={path} branch={branch} diff={sha256} message_sha256={sha256}
```

Do not call raw `git commit`. In manual mode, after `APPROVE_COMMIT` returns
through the controller chain, call `agent_authorized_commit`. In auto mode,
the Human supplies `AUTO_COMMIT` while approving scope; after controller
validation of `[AUTO_COMMIT_READY]`, call `agent_auto_commit`.

```text
APPROVE_COMMIT
```

The helper and Git guard re-hash the current staged diff and message file and
reject missing, malformed, stale, or mismatched authorization. Any edit,
restaging, branch change, or message change invalidates prior verification and
requires fresh verification, a new review artifact, and new Human
authorization. After committing, the helper compares the created commit diff
to the authorized hash; this post-commit check is mechanical only.

Coder and Refactor use `agent_authorized_push` only after the controller relays
the Human directive:

```text
APPROVE_PUSH
```

The push helper passes the authorization to the Git guard for one
`git push origin {branch}`. The guard rejects protected branches, mismatched
branch or commit, force/options, deletion, tags, multiple refspecs, other
remotes, and every non-Worker role.

After the push succeeds, Coder and Refactor use `agent_authorized_pr_create`
only after the controller relays this Human directive:

```text
APPROVE_PR_DEV
```

Provide an explicit title and readable body file. The GitHub guard requires
the local and `origin` branch commits to match the token and permits only one
`gh pr create` with base `dev`. It rejects other bases, protected heads,
web/draft modes, PR updates/review/close/merge, and every non-Worker role.

## Advisory decision aid (Jev, optional)

`agent_jev_advisory` is an optional fast second signal for three controller
judgments: the five-dimension tier score, `BLOCKER` vs `ADVISORY` triage
before `agent_revision_gate`, and scope-drift/risk pre-check before
dispatching Verifiers. Write one atomic judgment per question, keep the
state/questions in English, and apply your own logic to its probabilities
afterward.

It prints the upstream decision JSON, or `{"status":"skipped",...}` with
exit 0 when disabled (`HERDR_JEV_ENABLED=0`), keyless (no
`HERDR_ZEN_API_KEY`), tool-less, or on request failure. A skip means
continue LLM-only; it never blocks. Its output is advisory only: it never
replaces an independent Verifier verdict, never starts a revision alone,
and never authorizes commits, pushes, or PRs.
