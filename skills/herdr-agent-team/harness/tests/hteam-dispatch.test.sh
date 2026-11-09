#!/usr/bin/env bash
# Offline tests for bin/hteam-dispatch: the resolver decides the shape, the
# spawner is stubbed, so nothing here touches the Herdr app or starts a model.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$ROOT/bin/hteam-dispatch"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "hteam-dispatch test: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

python3 -m py_compile "$DISPATCH" || fail "dispatch does not compile"
[ -x "$DISPATCH" ] || fail "hteam-dispatch is not executable"

mkdir -p "$TMP/bin" "$TMP/state"
printf '[TASK] stub brief\n' > "$TMP/brief.md"

cat > "$TMP/bin/herdr-app-spawn-role" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
printf '{"space":"demo","terminal":"t99","mode":"child"}\n'
STUB
chmod +x "$TMP/bin/herdr-app-spawn-role"

run_dispatch() {
  STUB_LOG="$TMP/calls.log" PATH="$TMP/bin:$PATH" \
    HERDR_TEAM_STATE_DIR="$TMP/state" HERDR_TEAM_REPO="$ROOT" \
    "$DISPATCH" "$@"
}

# --- 1. a routed role is dispatched with the tier the resolver chose --------
: > "$TMP/calls.log"
OUT="$(run_dispatch coder --brief "$TMP/brief.md" --project demo --controller t1 \
  --request "Remove the pinned region line from one CI file" \
  --task-class operational --risk medium --known-cause --micro-deterministic \
  --runnable-acceptance)" || fail "dispatch failed: $OUT"
printf '%s' "$OUT" | grep -q "shape W9-ops" || fail "did not report the resolved shape: $OUT"
grep -q -- "--task-tier standard" "$TMP/calls.log" || fail "tier did not reach the spawner: $(cat "$TMP/calls.log")"
grep -q -- "--role coder" "$TMP/calls.log" && fail "the spawner takes the role positionally"
grep -q -- "coder $(printf '%s' "$TMP/brief.md")" "$TMP/calls.log" || fail "role/brief not passed: $(cat "$TMP/calls.log")"
grep -q -- "--commit-mode manual" "$TMP/calls.log" || fail "commit mode not forwarded"
INTAKE="$(sed -n 's/.*--intake \([^ ]*\).*/\1/p' "$TMP/calls.log" | head -1)"
[ -f "$INTAKE" ] || fail "intake file was not written: $INTAKE"
python3 - "$INTAKE" <<'PY' || fail "the written intake is not the one that was scored"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["task_class"] == "operational", data
assert data["risk"] == "medium", data
assert data["micro_deterministic"] is True, data
PY
ok "dispatch resolves the shape, writes the intake and calls the spawner once"

# --- 2. a role the shape does not staff is refused, nothing is launched ----
: > "$TMP/calls.log"
if run_dispatch reviewer --brief "$TMP/brief.md" --project demo \
  --request "Explain what the team does" --task-class advisory --risk low \
  >"$TMP/out" 2>"$TMP/err"; then
  fail "an unstaffed role was dispatched"
fi
grep -q "does not staff" "$TMP/err" || fail "refusal did not name the reason: $(cat "$TMP/err")"
[ -s "$TMP/calls.log" ] && fail "the spawner ran despite the refusal"
ok "a role outside the resolved shape never reaches the spawner"

# --- 3. --explain answers the self-service question -----------------------
OUT="$(run_dispatch --explain --request "Explain what the team does" \
  --task-class advisory --risk low)" || fail "--explain failed: $OUT"
printf '%s' "$OUT" | grep -q "none — PM answers itself" \
  || fail "--explain does not name an unstaffed shape: $OUT"
ok "--explain reports that the shape staffs nobody"

# --- 4. a missing brief is refused before anything is spawned -------------
: > "$TMP/calls.log"
if run_dispatch coder --project demo --request "Remove one line" \
  --task-class operational --risk medium --known-cause --micro-deterministic \
  --runnable-acceptance >"$TMP/out" 2>"$TMP/err"; then
  fail "dispatch without --brief succeeded"
fi
grep -q -- "--brief is required" "$TMP/err" || fail "missing brief was not explained: $(cat "$TMP/err")"
[ -s "$TMP/calls.log" ] && fail "the spawner ran without a brief"
ok "a missing brief is refused before the spawner runs"

echo "hteam-dispatch test: ok"