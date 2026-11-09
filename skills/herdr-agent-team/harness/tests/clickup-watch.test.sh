#!/usr/bin/env bash
# Offline tests for bin/clickup-watch: project inference, brief rendering, and
# the no-PM path. Nothing here talks to ClickUp or to a live Herdr pane.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/clickup-watch"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "clickup-watch test: $*" >&2; exit 1; }

python3 -m py_compile "$CLI" || fail "python syntax failed"
[ -x "$CLI" ] || fail "clickup-watch is not executable"

# A registry fixture keeps the test independent of the machine's projects.
# alpha-shop opts into auto intake; beta-portal does not, so beta-portal's list
# must never be polled in registry mode.
cat > "$TMP/registry.yaml" <<'YAML'
projects:
  alpha-shop:
    name: alpha-shop
    path: /tmp/work/alpha-shop
    description: Alpha shop frontend checkout
    clickup:
      list_id: '111000111'
      auto_intake: true
    repos:
      alpha-shop-web:
        path: /tmp/work/alpha-shop/alpha-shop-web
        description: Next.js storefront and checkout pages
  beta-portal:
    name: beta-portal
    path: /tmp/work/beta-portal
    description: Beta employee portal
    clickup:
      list_id: '222000222'
    repos:
      beta-portal-api:
        path: /tmp/work/beta-portal/beta-portal-api
        description: FastAPI backend for documents and news
YAML

cat > "$TMP/tasks.json" <<'JSON'
{"tasks": [
  {"id": "A1", "name": "alpha-shop: add a gift wrap checkbox to checkout",
   "description": "On alpha-shop-web checkout step 2 add an optional gift wrap checkbox.",
   "tags": [{"name": "agent-team"}],
   "assignees": [{"id": 60695437}],
   "url": "https://app.clickup.com/t/A1"},
  {"id": "B1", "name": "improve the form", "description": "make validation better",
   "tags": [{"name": "agent-team"}],
   "assignees": [{"id": 60695437}],
   "url": "https://app.clickup.com/t/B1"},
  {"id": "C1", "name": "Export documents list to CSV",
   "description": "project: beta-portal. The document list needs a CSV export button.",
   "tags": [{"name": "agent-team"}],
   "assignees": [{"id": 60695437}],
   "url": "https://app.clickup.com/t/C1"},
  {"id": "D1", "name": "alpha-shop: a colleague's own task",
   "description": "This one has no agent-team tag, so the watcher must not touch it.",
   "tags": [],
   "assignees": [{"id": 60695437}],
   "url": "https://app.clickup.com/t/D1"},
  {"id": "E1", "name": "alpha-shop: another herdr-team user's task",
   "description": "Tagged, but assigned to a different ClickUp user, so not ours.",
   "tags": [{"name": "agent-team"}],
   "assignees": [{"id": 111222333}],
   "url": "https://app.clickup.com/t/E1"}
]}
JSON

export CLICKUP_WATCH_REGISTRY="$TMP/registry.yaml"
export CLICKUP_WATCH_STATE_DIR="$TMP/state"
export CLICKUP_WATCH_CONFIG="$TMP/no-config.yaml"   # isolate from the user's real config
export CLICKUP_WATCH_REQUIRE_ASSIGNEE="60695437"   # "our" ClickUp user for this test
export CLICKUP_WATCH_CLAIM_ASSIGNEE=""             # never write assignees in tests
unset CLICKUP_WATCH_LIST_ID

"$CLI" check >/dev/null 2>&1 || true   # token/herdr-core may be absent; not asserted

# --- registry mode: follow the project harness ------------------------------
out="$("$CLI" once --fixture "$TMP/tasks.json" --dry-run --max-tasks 5 2>&1)"

# A. Only projects with clickup.auto_intake are polled, on their own lists.
grep -q "alpha-shop list 111000111" <<<"$out" || fail "alpha-shop's list was not polled:
$out"
grep -q "222000222" <<<"$out" && fail "beta-portal has no auto_intake but its list was polled"

# B. The tag is the opt-in marker: an untagged task is never touched.
grep -q "skip-untagged .*task=D1" <<<"$out" || fail "D1 (untagged) was not skipped:
$out"
grep -q "task=D1 .*project=" <<<"$out" && fail "D1 was dispatched despite having no tag"

# C. Ownership: tagged but assigned to another ClickUp user is not ours.
grep -q "skip-not-mine .*task=E1" <<<"$out" || fail "E1 (other user's task) was not skipped:
$out"
grep -q "task=E1 .*project=" <<<"$out" && fail "E1 was dispatched despite belonging to another user"

# D. A task on alpha-shop's list is dispatched to alpha-shop without guessing.
grep -q "task=A1 .*project=alpha-shop" <<<"$out" || fail "A1 was not mapped to alpha-shop by its list:
$out"

# E. An explicit `project:` line still wins over the list mapping.
grep -q "task=C1 .*project=beta-portal" <<<"$out" || fail "C1 did not follow its project: line:
$out"

# F. With a list mapping there is nothing to guess, so B1 is dispatched too.
grep -q "escalate .*task=B1" <<<"$out" && fail "B1 was escalated although its list maps to a project"

# G. The brief carries the verbatim task text and grants no authority.
brief="$(ls "$TMP"/state/briefs/*a1-*.md 2>/dev/null | head -1)"
[ -n "$brief" ] || fail "no brief written for A1"
grep -q "Task text (verbatim)" "$brief" || fail "brief misses the verbatim task text"
grep -q "gift wrap checkbox" "$brief" || fail "brief does not quote the task text"
grep -q "pre-authorizes nothing" "$brief" || fail "brief does not withhold authority"
grep -q "AUTO_COMMIT" "$brief" || fail "brief does not ask the gate/auto question"

# --- single-list override: project inference still works -------------------
override_out="$(CLICKUP_WATCH_LIST_ID=999000999 CLICKUP_WATCH_STATE_DIR="$TMP/state-ov" \
  "$CLI" once --fixture "$TMP/tasks.json" --dry-run --max-tasks 5 2>&1)"
grep -q "single list 999000999\|list 999000999" <<<"$override_out" \
  || fail "the single-list override was not honoured:
$override_out"
grep -q "task=A1 .*project=alpha-shop" <<<"$override_out" \
  || fail "A1 did not resolve by inference in override mode:
$override_out"
grep -q "escalate .*task=B1" <<<"$override_out" \
  || fail "B1 was not escalated when no list mapping exists:
$override_out"
grep -q "would set status: discuss" <<<"$override_out" \
  || fail "escalation does not move B1 to discuss"

# 5. No PM and no Orchestrator must not move the task or lose it.
CLICKUP_WATCH_STATE_DIR="$TMP/state2" HC_BIN=/usr/bin/false \
  "$CLI" once --fixture "$TMP/tasks.json" --dry-run --max-tasks 1 >"$TMP/no-target.txt" 2>&1 || true
grep -q "would keep status: to do\|would set status: in progress" "$TMP/no-target.txt" \
  || fail "no-target path printed neither a kept nor a dispatched status"

# 6. Fixture mode never writes to ClickUp.
grep -q "fixture mode is read-only" <<<"$(
  CLICKUP_WATCH_STATE_DIR="$TMP/state3" "$CLI" once --fixture "$TMP/tasks.json" --max-tasks 1 2>&1
)" || fail "fixture mode without --dry-run is not forced read-only"

# 7. Status is discoverable without touching ClickUp, and names the projects
#    that opted into auto intake.
status_out="$("$CLI" status 2>&1)"
grep -q "watching:    registry" <<<"$status_out" || fail "status does not report registry mode:
$status_out"
grep -q "alpha-shop" <<<"$status_out" || fail "status does not list the auto_intake project"

# 7b. The brief tells PM how to ask the Human in ClickUp and to mark status.
grep -q "clickup-watch ask --task" "$brief" || fail "brief does not document the ask helper"
grep -q "mark --task" "$brief" || fail "brief does not require PM to mark ClickUp status"

# 7c. `ask` refuses a task this watcher never dispatched.
if "$CLI" ask --task NOSUCH --text "hello" >"$TMP/ask-guard.txt" 2>&1; then
  fail "ask accepted a task that was never dispatched"
fi
grep -q "was not dispatched by this watcher" "$TMP/ask-guard.txt" \
  || fail "ask guard message missing:
$(cat "$TMP/ask-guard.txt")"

# 7d. `ask --dry-run` on a dispatched task prints the comment and the target status.
ask_out="$("$CLI" ask --task A1 --text "ควรใช้ branch ไหนครับ" --dry-run 2>&1)"
grep -q "มีคำถามก่อนดำเนินการต่อ" <<<"$ask_out" || fail "ask does not compose the question comment"
grep -q "would set status: discuss" <<<"$ask_out" || fail "ask does not park the task in discuss"

# 7f. `mark` advances a tracked task but refuses closing statuses.
mark_out="$("$CLI" mark --task A1 --status ready --text "เสร็จแล้ว" --dry-run 2>&1)"
grep -q "งานเสร็จแล้ว" <<<"$mark_out" || fail "mark does not compose the progress comment:
$mark_out"
grep -q "would set status: ready" <<<"$mark_out" || fail "mark does not target ready"
if "$CLI" mark --task A1 --status done --text "x" --dry-run >"$TMP/mark-done.txt" 2>&1; then
  fail "mark allowed the Human-only 'done' status"
fi
grep -q "not writable by the agent" "$TMP/mark-done.txt" || fail "mark refusal message missing"

# 7e. status shows the queue: what waits for the Human, what the team holds.
mkdir -p "$TMP/state-q"
cat > "$TMP/state-q/state.json" <<'JSON'
{"version":1,
 "tasks":{
   "T1":{"outcome":"awaiting_human","project":"alpha-shop","asked_at":"2026-01-01T00:00:00Z","question":"ควรใช้ branch ไหน"},
   "T2":{"outcome":"dispatched","project":"beta-portal","at":"2026-01-01T00:00:00Z"}},
 "last_poll":{"at":"2026-01-01T00:00:00Z","tasks":0,"handled":0}}
JSON
q_out="$(CLICKUP_WATCH_STATE_DIR="$TMP/state-q" "$CLI" status 2>&1)"
grep -q "queue:       1 waiting for you, 1 with the team" <<<"$q_out" || fail "queue counts wrong:
$q_out"
grep -q "T1 alpha-shop — waiting" <<<"$q_out" || fail "status does not list the waiting task"
grep -q "T2 beta-portal — with the team" <<<"$q_out" || fail "status does not list the held task"

# 8. The config file drives list, status, tag, interval, and state dir.
cat > "$TMP/watch.yaml" <<'YAML'
list_id: "999000111222"
workspace_id: "9003040618"
status: "backlog"
require_tag: "robot-squad"
require_assignee: "1234567"
claim_assignee: ""
interval: 42
max_tasks: 1
registry: "/tmp/work/registry.yaml"
state_dir: "/tmp/work/state"
YAML
config_out="$(env -u CLICKUP_WATCH_REQUIRE_ASSIGNEE CLICKUP_WATCH_CONFIG="$TMP/watch.yaml" "$CLI" status 2>&1)"
grep -q "999000111222" <<<"$config_out" || fail "config list_id was not applied:
$config_out"
grep -q "robot-squad" <<<"$config_out" || fail "config require_tag was not applied"
grep -q "1234567" <<<"$config_out" || fail "config require_assignee was not applied"
CLICKUP_WATCH_CONFIG="$TMP/watch.yaml" "$CLI" init >"$TMP/init.txt" 2>&1 || true
grep -q "already exists" "$TMP/init.txt" || fail "init overwrote an existing config without --force"
echo "clickup-watch test: ok"