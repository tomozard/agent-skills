#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/task-board"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HERDR_ENV=1 HERDR_TASK_BOARD_ROOT="$TMP/board"
DIFF_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
DIFF_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
COMMIT_A="cccccccccccccccccccccccccccccccccccccccc"

run_as() {
  HERDR_AGENT_ROLE="$1" "$CLI" "${@:2}"
}

run_as pm create demo task-1 --owner coder --controller pm >/dev/null
python3 - "$TMP/board/demo/task-1/state.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
required = {
    "schema_version", "project", "task_id", "run_id", "state", "owner",
    "controller", "verification_required", "verification_profile", "commit_required", "candidate_diff_sha256",
    "verified_diff_sha256", "commit_sha",
    "current_node", "depends_on", "revision", "attempt",
    "artifacts", "verification", "human_gate", "created_at", "updated_at",
    "last_event_id",
}
missing = required - set(state)
assert not missing, missing
assert state["schema_version"] == 1 and state["state"] == "queued"
assert isinstance(state["depends_on"], list)
assert state["verification_required"] is True
assert state["verification_profile"] == "independent"
assert state["commit_required"] is False
assert state["candidate_diff_sha256"] is None
assert state["verified_diff_sha256"] is None
assert state["commit_sha"] is None
PY

run_as pm transition demo task-1 planned >/dev/null
run_as pm transition demo task-1 in_progress >/dev/null
if run_as pm transition demo task-1 verified >/dev/null 2>&1; then
  echo "invalid transition accepted" >&2; exit 1
fi
if run_as coder transition demo task-1 blocked >/dev/null 2>&1; then
  echo "unauthorized transition accepted" >&2; exit 1
fi
run_as coder event demo task-1 --type STATUS --payload '{"state":"blocked"}' >/dev/null
before=$(wc -c < "$TMP/board/demo/task-1/events.jsonl")
run_as tester event demo task-1 --type EVIDENCE --payload '{"ok":true}' >/dev/null
after=$(wc -c < "$TMP/board/demo/task-1/events.jsonl")
[ "$after" -gt "$before" ] || { echo "event log was not append-only" >&2; exit 1; }
python3 - "$TMP/board/demo/task-1/events.jsonl" <<'PY'
import json, sys
lines = open(sys.argv[1]).read().splitlines()
assert len(lines) == 5, lines
for line in lines:
    json.loads(line)
PY

run_as pm transition demo task-1 blocked >/dev/null
run_as pm transition demo task-1 in_progress >/dev/null
run_as pm transition demo task-1 awaiting_verification \
  --artifact /tmp/task-1-candidate.txt --candidate-diff "$DIFF_A" >/dev/null
run_as pm transition demo task-1 revision_required --current-node coder --payload '{"reason":"review"}' >/dev/null
run_as pm transition demo task-1 in_progress >/dev/null
run_as pm transition demo task-1 awaiting_verification \
  --artifact /tmp/task-1-candidate-2.txt --candidate-diff "$DIFF_A" >/dev/null
run_as pm transition demo task-1 verified \
  --verification "{\"diff\":\"$DIFF_A\",\"reviewer\":\"PASS\"}" >/dev/null
run_as pm transition demo task-1 complete >/dev/null
if run_as pm transition demo task-1 in_progress >/dev/null 2>&1; then
  echo "terminal task changed" >&2; exit 1
fi
python3 - "$TMP/board/demo/task-1/state.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state["state"] == "complete"
assert state["revision"] == 1
assert state["current_node"] == "coder"
PY

# Concurrent appenders serialize through the mkdir lock and leave valid JSONL.
run_as pm create demo concurrent >/dev/null
for n in $(seq 1 20); do
  HERDR_AGENT_ROLE=coder "$CLI" event demo concurrent --type STATUS \
    --payload "{\"n\":$n}" >/dev/null &
done
wait
python3 - "$TMP/board/demo/concurrent/events.jsonl" <<'PY'
import json, sys
lines = open(sys.argv[1]).read().splitlines()
assert len(lines) == 21, len(lines)
for line in lines:
    json.loads(line)
PY

# The override is used, and no state file is written in this worktree.
[ ! -e "$ROOT/.agents/task-board" ] || { echo "state root is in worktree" >&2; exit 1; }
HERDR_AGENT_ROLE=pm "$CLI" list --json > "$TMP/list.json"
python3 - "$TMP/list.json" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))
assert {item["task_id"] for item in items} == {"task-1", "concurrent"}
PY

# Push-based Phase 2 protocol flow: events are append-only; controllers own transitions.
run_as pm create demo flow --state planned --controller supervisor \
  --commit-required >/dev/null
if run_as pm create demo invalid-controller --controller coder >/dev/null 2>&1; then
  echo "invalid controller accepted" >&2; exit 1
fi
[ ! -e "$TMP/board/demo/invalid-controller/state.json" ] || {
  echo "invalid controller created state" >&2; exit 1;
}
if run_as pm transition demo flow in_progress >/dev/null 2>&1; then
  echo "mismatched controller transition accepted" >&2; exit 1
fi
run_as coder event demo flow --type ACK --payload '{"state":"in_progress"}' >/dev/null
run_as supervisor transition demo flow in_progress >/dev/null
run_as coder event demo flow --type READY_FOR_VERIFICATION \
  --payload "{\"diff\":\"$DIFF_A\"}" >/dev/null
run_as supervisor transition demo flow awaiting_verification \
  --artifact /tmp/flow-candidate.txt --candidate-diff "$DIFF_A" >/dev/null
run_as tester event demo flow --type PASS --payload '{"state":"verified"}' >/dev/null
if run_as supervisor transition demo flow verified \
  --verification "{\"diff\":\"$DIFF_B\",\"tester\":\"PASS\"}" >/dev/null 2>&1; then
  echo "verification accepted a non-candidate diff" >&2; exit 1
fi
run_as supervisor transition demo flow verified \
  --verification "{\"diff\":\"$DIFF_A\",\"tester\":\"PASS\"}" >/dev/null
if run_as pm transition demo flow complete >/dev/null 2>&1; then
  echo "commit-required task completed before Human gate" >&2; exit 1
fi
run_as supervisor transition demo flow awaiting_human_commit \
  --artifact /tmp/flow-review.txt --human-gate "{\"diff\":\"$DIFF_A\"}" >/dev/null
if run_as supervisor transition demo flow complete >/dev/null 2>&1; then
  echo "supervisor completed commit-gated task" >&2; exit 1
fi
if run_as pm transition demo flow complete >/dev/null 2>&1; then
  echo "commit-required task completed without a commit SHA" >&2; exit 1
fi
run_as pm transition demo flow complete --commit "$COMMIT_A" >/dev/null
[ "$(run_as pm show demo flow --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')" = complete ]

run_as pm create demo gate --commit-required >/dev/null
run_as pm transition demo gate in_progress >/dev/null
if run_as pm transition demo gate awaiting_human_commit \
  --artifact /tmp/gate-review.txt --human-gate "{\"diff\":\"$DIFF_A\"}" >/dev/null 2>&1; then
  echo "Human gate accepted before verification" >&2; exit 1
fi
run_as pm transition demo gate awaiting_verification \
  --artifact /tmp/gate-candidate.txt --candidate-diff "$DIFF_A" >/dev/null
run_as pm transition demo gate verified \
  --verification "{\"diff\":\"$DIFF_A\"}" >/dev/null
if run_as pm transition demo gate awaiting_human_commit \
  --artifact /tmp/gate-review.txt --human-gate "{\"diff\":\"$DIFF_B\"}" >/dev/null 2>&1; then
  echo "Human gate accepted a non-verified diff" >&2; exit 1
fi
run_as pm transition demo gate awaiting_human_commit \
  --artifact /tmp/gate-review.txt --human-gate "{\"diff\":\"$DIFF_A\"}" >/dev/null
run_as pm transition demo gate in_progress >/dev/null
[ "$(run_as pm show demo gate --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["verified_diff_sha256"])')" = None ]
[ "$(run_as pm show demo gate --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["candidate_diff_sha256"])')" = None ]
run_as pm create demo stuck >/dev/null
run_as pm transition demo stuck stuck >/dev/null

run_as pm create demo supervisor-complete --controller supervisor --no-verification >/dev/null
run_as supervisor transition demo supervisor-complete in_progress >/dev/null
if run_as supervisor transition demo supervisor-complete complete >/dev/null 2>&1; then
  echo "supervisor completed task" >&2; exit 1
fi
run_as pm transition demo supervisor-complete complete >/dev/null

# A commit-gated implementation may not disable verification.
if run_as pm create demo no-verifier-commit --controller supervisor \
  --no-verification --commit-required >/dev/null 2>&1; then
  echo "commit-required task disabled verification" >&2; exit 1
fi

# The deterministic micro profile keeps the commit gate but replaces a full
# independent verifier loop with the hash-bound numeric-only candidate proof.
run_as pm create demo micro --commit-required --auto-commit \
  --verification-profile deterministic-micro >/dev/null
run_as pm transition demo micro in_progress >/dev/null
run_as pm transition demo micro awaiting_verification \
  --artifact /tmp/micro-candidate.txt --candidate-diff "$DIFF_A" >/dev/null
if run_as pm transition demo micro verified \
  --verification "{\"mode\":\"independent\",\"diff\":\"$DIFF_A\",\"evidence\":\"wrong profile\"}" >/dev/null 2>&1; then
  echo "micro task accepted the wrong verification mode" >&2; exit 1
fi
run_as pm transition demo micro verified \
  --verification "{\"mode\":\"deterministic_micro\",\"diff\":\"$DIFF_A\",\"evidence\":\"numeric-only staged text replacement\"}" >/dev/null
run_as pm transition demo micro awaiting_auto_commit \
  --artifact /tmp/micro-review.txt --human-gate "{\"mode\":\"auto\",\"diff\":\"$DIFF_A\"}" >/dev/null
run_as pm transition demo micro complete --commit "$COMMIT_A" >/dev/null
[ "$(run_as pm show demo micro --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')" = complete ]

# A direct PM task with Verification: none may complete without a verifier.
run_as pm create demo direct --no-verification >/dev/null
run_as pm transition demo direct in_progress >/dev/null
if run_as pm transition demo direct awaiting_human_commit \
  --artifact /tmp/direct-review.txt --human-gate "{\"diff\":\"$DIFF_A\"}" >/dev/null 2>&1; then
  echo "non-commit task entered Human commit gate" >&2; exit 1
fi
run_as pm transition demo direct complete >/dev/null
[ "$(run_as pm show demo direct --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')" = complete ]

# Revision attempts are capped at two; a third revision is rejected.
run_as pm create demo revision-limit >/dev/null
run_as pm transition demo revision-limit in_progress >/dev/null
for round in 1 2; do
  run_as pm transition demo revision-limit awaiting_verification \
    --artifact "/tmp/revision-limit-$round.txt" --candidate-diff "$DIFF_A" >/dev/null
  run_as pm transition demo revision-limit revision_required >/dev/null
  run_as pm transition demo revision-limit in_progress >/dev/null
done
run_as pm transition demo revision-limit awaiting_verification \
  --artifact /tmp/revision-limit-final.txt --candidate-diff "$DIFF_A" >/dev/null
if run_as pm transition demo revision-limit revision_required >/dev/null 2>&1; then
  echo "revision ceiling was not enforced" >&2; exit 1
fi

# A state root inside the repository is rejected even from a subdirectory.
mkdir -p "$ROOT/tests/task-board-subdir"
if (cd "$ROOT/tests/task-board-subdir" && run_as pm create demo inside-worktree \
    --root "$ROOT/tests/task-board-state"); then
  echo "state root inside worktree was accepted" >&2; exit 1
fi
[ ! -e "$ROOT/tests/task-board-state" ] || { echo "worktree state was written" >&2; exit 1; }
rm -rf "$ROOT/tests/task-board-subdir"

# A target root nested in another repository is also rejected.
EXTERNAL_REPO="$TMP/external-repo"
mkdir -p "$EXTERNAL_REPO/target/nested"
git -C "$EXTERNAL_REPO" init -q
if run_as pm create demo external-repo-root --root "$EXTERNAL_REPO/target/nested"; then
  echo "state root in external repository was accepted" >&2; exit 1
fi
[ ! -e "$EXTERNAL_REPO/target/nested/demo" ] || {
  echo "external repository state was written" >&2; exit 1
}

# Shared helper payloads remain valid JSON with shell-special characters.
FAKE_BIN="$TMP/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/herdr" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$FAKE_BIN/herdr"
run_as pm create demo helper >/dev/null
PATH="$FAKE_BIN:$PATH" HERDR_TASK_BOARD_BIN="$CLI" HERDR_TASK_BOARD_PROJECT=demo \
  HERDR_PANE_ID=helper-sender HERDR_AGENT_ROLE=coder \
  bash -c 'source .agents/skills/agent-shared/lib/agent-helpers.sh; \
    agent_done helper-target coder supervisor helper $'"'"'quote "slash \\\\ and
newline'"'"''
# Failed delivery must not append a Task Board event.
FAIL_BIN="$TMP/fail-bin"
mkdir -p "$FAIL_BIN"
cat > "$FAIL_BIN/herdr" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$FAIL_BIN/herdr"
run_as pm create demo delivery-failure >/dev/null
if PATH="$FAIL_BIN:$PATH" HERDR_TASK_BOARD_BIN="$CLI" HERDR_TASK_BOARD_PROJECT=demo \
  HERDR_AGENT_ROLE=coder HERDR_PANE_ID=sender bash -c \
  'source .agents/skills/agent-shared/lib/agent-helpers.sh; \
   agent_done target coder supervisor delivery-failure failed'; then
  echo "failed delivery accepted" >&2; exit 1
fi
[ "$(wc -l < "$TMP/board/demo/delivery-failure/events.jsonl")" -eq 1 ] || {
  echo "event appended before failed delivery" >&2; exit 1
}

# A successful delivery remains successful when the optional JSON encoder fails.
ENCODER_FAIL_BIN="$TMP/encoder-fail-bin"
mkdir -p "$ENCODER_FAIL_BIN"
cat > "$ENCODER_FAIL_BIN/herdr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_DELIVERY_LOG"
exit 0
SH
cat > "$ENCODER_FAIL_BIN/python3" <<'SH'
#!/usr/bin/env bash
exit 127
SH
chmod +x "$ENCODER_FAIL_BIN/herdr" "$ENCODER_FAIL_BIN/python3"
HERDR_DELIVERY_LOG="$TMP/delivery.log" HERDR_TASK_BOARD_BIN="$CLI" \
  HERDR_TASK_BOARD_PROJECT=demo HERDR_AGENT_ROLE=coder HERDR_PANE_ID=sender \
  PATH="$ENCODER_FAIL_BIN:$PATH" bash -c \
  'source .agents/skills/agent-shared/lib/agent-helpers.sh; \
   agent_done target coder supervisor encoder-failure delivered'
 grep -q '^pane run target \[DONE\] from: coder -> to: supervisor task=encoder-failure summary=delivered$' \
  "$TMP/delivery.log" || { echo "delivery was not recorded" >&2; exit 1; }

python3 - "$TMP/board/demo/helper/events.jsonl" <<'PY'
import json
import sys

entries = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
entry = entries[-1]
assert entry["type"] == "DONE"
assert entry["payload"]["summary"] == 'quote "slash \\\\ and\nnewline'
assert list(entry["payload"]) == sorted(entry["payload"])
PY

# The override is used, and no state file is written in this worktree.
[ ! -e "$ROOT/.agents/task-board" ] || { echo "state root is in worktree" >&2; exit 1; }

printf '%s\n' "task-board tests: ok"
