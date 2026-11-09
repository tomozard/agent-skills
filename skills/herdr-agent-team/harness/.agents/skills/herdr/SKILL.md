---
name: herdr
description: "Control Herdr workspaces, tabs, panes, and agent processes for the minimal multi-project team runtime. Requires HERDR_ENV=1 except for the installed startup launcher, an explicitly requested external read-only audit, or one Human-authorized text relay to the global Orchestrator, and enforces scoped access with no blocking waits."
---

# Herdr

Herdr is the terminal multiplexer. It owns workspaces, tabs, panes, process
state, labels, and input delivery. Team ownership is defined by the
`agent-team` skill.

This skill is based on the official Herdr agent skill and the installed CLI.
The installed binary is authoritative for syntax.

## Guard

Before any Herdr control command:

```bash
test "${HERDR_ENV:-}" = 1
```

If the check fails, stop unless the Human explicitly requested one of the two
external capabilities below. The external operator must not set `HERDR_ENV=1` to impersonate
a team pane.

### External read-only audit

A one-shot read-only audit by the Human-controlled external harness operator
is limited to these commands:

```bash
herdr workspace list
herdr tab list --workspace <workspace_id>
herdr pane list --workspace <workspace_id>
herdr pane read <pane_id> --source recent-unwrapped --lines <count>
```

### External Orchestrator relay

After a separate explicit Human request for each delivery, the external
operator may relay exactly one Human-authored text message to the global
Orchestrator pane without setting `HERDR_ENV=1`.

1. Resolve the target afresh with the allowed workspace and pane list commands.
   Continue only when exactly one pane is labelled `orchestrator`.
2. Prefix the exact Human-approved text with `[HUMAN_RELAY]` and deliver it with
   one `herdr pane run`, followed by the single explicit Enter safeguard.
3. If either command fails, report the failure and stop. Do not retry, inspect
   transcripts, or target another pane.

```bash
herdr pane run <orchestrator_pane_id> "[HUMAN_RELAY] <Human-approved message>"
sleep 1
herdr pane send-keys <orchestrator_pane_id> enter
```

The relay must not contain an `APPROVE_COMMIT`, `APPROVE_PUSH`,
`APPROVE_PR_DEV`, or `AUTO_COMMIT` directive. It must not request shutdown or embed a shell
command for execution. It authorizes no topology, process, Git, remote, or
other state mutation beyond that single input delivery.

The installed `herdr-team` launcher remains the only startup exception outside
a managed pane. Direct Human invocation authorizes it to target only its
dedicated session with `herdr status server`, `herdr agent get orchestrator`,
`herdr agent focus orchestrator`, `herdr agent start orchestrator ...`, and the
final client attach. It must not read transcripts, deliver input, control any
other agent, use a blocking wait, or poll.

Outside the explicit audit, relay, and launcher capabilities above, the
external operator must not run another Herdr command, mutate state, deliver
input, or poll.

Discover syntax without launching the TUI:

```bash
herdr --help
herdr workspace
herdr tab
herdr pane
```

Never probe a mutating nested command by omitting its arguments.

## IDs

Treat workspace, tab, pane, and terminal IDs as opaque strings. Read IDs from
list/get/create/split responses. Never construct IDs from display order or
reuse an ID remembered before a topology mutation.

Use the calling context when available:

```bash
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
herdr pane current --current
```

Prefer `--current` or an explicit ID. Do not rely on the UI-focused pane.

## Inspect Topology

```bash
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr pane get <pane_id>
herdr pane process-info --pane <pane_id>
```

Pane metadata and process information are safe for topology and readiness
checks. Transcript access is a separate restricted capability.

## Create Topology

Create one workspace per project:

```bash
herdr workspace create --cwd /absolute/project/path --label smart_ai --no-focus
```

Create a named tab:

```bash
herdr tab create --workspace <workspace_id> --cwd /absolute/project/path \
  --label manager-smart_ai --no-focus
```

Split to the right and keep focus:

```bash
herdr pane split <pane_id> --direction right --no-focus
```

The runtime layout is left-to-right with at most three panes per tab. Do not
split down. Create another labelled tab when capacity is required.

## Label and Launch

```bash
herdr pane rename <pane_id> coder-smart_ai-api
spawn-agent --pane <pane_id> --role coder --project smart_ai \
  --workstream api --base-branch main \
  --work-branch feature/api-change \
  --cwd /absolute/project/path --task-tier standard --runtime pi \
  --model opencode-go/deepseek-v4.1-flash
```

For an approved local protected-branch synchronization, Supervisor may use
the bounded operation below. The runtime makes the Worker read-only and the
Git guard permits only the exact switch and fast-forward pull for the approved
branch on a clean worktree.

```bash
spawn-agent --pane <pane_id> --role coder --project smart_ai \
  --base-branch uat --work-branch uat --operation protected-sync \
  --sync-branch uat --cwd /absolute/project/path --task-tier standard --runtime pi \
  --model opencode-go/deepseek-v4.1-flash
```

Use `spawn-agent`; before any pane or branch mutation it verifies that the
calling controller owns the target role and that the explicit `--task-tier`,
`--runtime`, and `--model` match the role's schema-v4 `team.json` routing
policy. A configured alternate requires `--routing-exception`; there is no
silent fallback. Fixed Designer is the exception: PM omits tier and model
arguments, and `spawn-agent` resolves its sole Claude `opus` pair. It
rejects any model whose provider prefix appears in the top-level
`disabled_model_providers` array, including configured alternates. Clearing
that array re-enables later launches; it does not switch an active session. It
then applies naming, runtime health checks, role prompts, and readiness
verification. For Coder or Refactor it creates a missing branch from the
approved local base, switches to an existing branch when needed, or reuses the
current Human-approved non-protected Work branch after safety checks. In
`protected-sync`, it only switches to the existing approved protected branch
and never creates or edits that branch.
Controllers record the five-dimension Task Tier Assessment and evidence-based
pair in the task, never use `auto`, and never ask the Human to perform routine
branch setup or a separate model-approval round. Do not hand-build Pi or Claude
commands in role prompts.

## Deliver Input

The CLI defines `herdr pane run` as text plus Enter, but an agent TUI may still
be finishing startup when that Enter arrives. For inter-agent delivery, use
the shared helper, which sends the message, waits one second, and sends an
explicit Enter safeguard:

```bash
herdr pane run <pane_id> "[ACK] from: pm -> to: orchestrator task=abc"
sleep 1
herdr pane send-keys <pane_id> enter
```

Never repeat these raw commands in a role session. Use `send_and_submit` or
`send_file_and_submit` so the safeguard is applied consistently. Long or
shell-sensitive messages use file-first handoff.

## Transcript Capability

Only these controllers may inspect direct reports:

| Controller | Direct reports |
|---|---|
| Orchestrator | PM |
| PM | SA, Investigator, Researcher, Designer, Supervisor, approved direct Coder, Refactor, Reviewer, Tester |
| Supervisor | Coder, Refactor, Reviewer, Tester |

After an explicit Human request, the Human-controlled external harness
operator may inspect any team pane for a one-shot read-only audit. This is an
external operational capability, not a team role capability. The audit itself
does not permit input delivery or state mutation; the separate external
Orchestrator relay permits only the single delivery defined in the Guard.

Diagnostic transcript inspection:

```bash
herdr pane read <direct_report_pane> --source recent-unwrapped --lines 80
```

It is permitted only after failed readiness, a blocked/unknown state, a
missing push reply after one status request, or an explicit human request.
Never put transcript inspection in a polling loop.

## Prohibited Coordination

- Do not use any command from the Herdr blocking-wait group.
- Do not poll with sleep plus pane metadata or transcript inspection.
- Do not run shell-delayed checks such as `sleep 30 && herdr pane list`,
  `while ...; do herdr pane ...; done`, or any repeated pane metadata/read
  check. After dispatching work, wait for pushed protocol messages.
- Team roles must not inspect a pane outside the controller's direct-report
  scope. The explicitly requested external read-only audit is the sole
  transcript-access exception; the external relay grants no transcript access.
- Do not send work directly across command layers.
- Do not close a workspace, tab, or pane you do not own unless the human
  explicitly requests it.
- Do not stop or kill the Herdr server from an active team session, except for
  the explicit Human `shutdown` flow after the Orchestrator runtime exits.

## Team Shutdown

Only the global Orchestrator handles a Human `/shutdown` request (or the
standalone compatibility form). Use the
installed `agent-team-shutdown` helper and pass only project workspace IDs
owned by that Orchestrator session. The helper uses `herdr workspace close`
for those workspaces and completes a nonblocking handoff before its own pane
can exit. The detached external finalizer then queues `/quit`, applies the
Enter safeguard, and runs `herdr server stop` as its final shutdown command
for the default session. Launcher startup must reject an unavailable live
finalizer and replace stale finalizer PID, lock, and FIFO state.

## Agent State

Pane metadata may report `idle`, `working`, `blocked`, `done`, or `unknown`.
State is a hint, not task completion. Completion is the pushed `[DONE]`,
`[STUCK]`, `[PASS]`, or `[CHANGES_REQUIRED]` message defined by the
communication protocol.
