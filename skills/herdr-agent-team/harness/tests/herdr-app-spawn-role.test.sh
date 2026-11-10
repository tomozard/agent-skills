#!/usr/bin/env bash
# Offline tests for bin/herdr-app-spawn-role: placement (child vs tab), the
# one-space-per-project rule, and tab naming. Both app binaries are stubbed, so
# nothing here touches a live Herdr app or starts a model.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPAWN="$ROOT/bin/herdr-app-spawn-role"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "herdr-app-spawn-role test: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

bash -n "$SPAWN" || fail "bash syntax failed"
[ -x "$SPAWN" ] || fail "herdr-app-spawn-role is not executable"
mkdir -p "$TMP/work"
printf '[TASK] stub brief\n' > "$TMP/brief.md"
printf '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true,"risk":"low"}' > "$TMP/intake-fix.json"
printf '{"task_class":"refactor","structural_cleanup":true,"risk":"low"}' > "$TMP/intake-refactor.json"
printf '{"task_class":"document"}' > "$TMP/intake-doc.json"
printf '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true,"risk":"high"}' > "$TMP/intake-critical.json"
printf '{"task_class":"feature","new_behavior":true,"runnable_acceptance":true}' > "$TMP/intake-feature.json"

# --- stubs ----------------------------------------------------------------
cat > "$TMP/app" <<'STUB'
#!/usr/bin/env bash
# Records every call; answers the shapes herdr-app-spawn-role parses.
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1" in
  ls)
    if [ "${STUB_SPACES:-none}" = "project" ]; then
      printf '{"spaces":[{"id":"sp1","name":"demo","tabs":[]}]}'
    else
      printf '{"spaces":[{"id":"sp0","name":"Herdr Team","tabs":[]}]}'
    fi
    ;;
  do)
    case "$2" in
      space.new) printf '{"space":"sp1","tab":"tb1","terminal":"t10"}' ;;
      tab.new)   printf '{"tab":"tb1","terminal":"t11"}' ;;
      pane.split) printf '{"pane":"p1","terminal":"t12"}' ;;
      *) printf '{}' ;;
    esac
    ;;
  *) printf '{}' ;;
esac
STUB
cat > "$TMP/hc" <<'STUB'
#!/usr/bin/env bash
printf 'hc %s\n' "$*" >> "$STUB_LOG"
case "$1" in
  ls)
    if [ "${STUB_LIVE_PM:-0}" = "1" ]; then
      printf '{"terminals":[{"address":"t99","labels":{"role":"pm","where":"demo / manager-demo"}}]}'
    else
      printf '{"terminals":[]}'
    fi
    ;;
  run) printf '{"address":"t20"}' ;;
  get)
    if [ "${STUB_LIVE_REGISTERED:-0}" = "1" ]; then
      printf '{"address":"%s","state":"live"}' "$2"
    else
      printf '{"address":"%s","state":"finished"}' "$2"
    fi
    ;;
  label) printf '{}' ;;
  *) printf '{}' ;;
esac
STUB
chmod +x "$TMP/app" "$TMP/hc"

# A fixture intake per task class keeps every executing role inside its shape;
# callers that pass their own --intake keep it.
intake_for() {
  case "$1" in
    coder|tester)    echo "$TMP/intake-fix.json" ;;
    refactor|reviewer) echo "$TMP/intake-refactor.json" ;;
    documenter)      echo "$TMP/intake-doc.json" ;;
    sa|researcher|designer) echo "$TMP/intake-feature.json" ;;
    *) echo "" ;;
  esac
}

run_spawn() {
  local role="$1"; shift
  local extra=()
  case " $* " in
    *" --intake "*) ;;
    *) local auto; auto="$(intake_for "$role")"
       [ -n "$auto" ] && extra=(--intake "$auto") ;;
  esac
  STUB_LOG="$TMP/calls.log" STUB_SPACES="${STUB_SPACES:-none}" \
    HERDR_APP_BIN="$TMP/app" HC_BIN="$TMP/hc" \
    HERDR_TEAM_REPO="$ROOT" HERDR_APP_SPACE="Herdr Team" \
    bash "$SPAWN" "$role" "$@" ${extra[@]+"${extra[@]}"} --cwd "$TMP/work" 2>"$TMP/err"
}

# --- 1. a project role without --project is refused ------------------------
if STUB_LOG="$TMP/calls.log" HERDR_APP_BIN="$TMP/app" HC_BIN="$TMP/hc" \
     HERDR_TEAM_REPO="$ROOT" bash "$SPAWN" pm "$TMP/brief.md" --cwd "$TMP/work" \
     >"$TMP/out" 2>"$TMP/err"; then
  fail "pm without --project was accepted"
fi
grep -q "pass --project" "$TMP/err" || fail "missing --project was refused without the reason"
ok "project role without --project is refused"

# --- 2. pm opens the project's own space, not the control space ------------
: > "$TMP/calls.log"
OUT="$(run_spawn pm "$TMP/brief.md" --project demo)" || fail "pm --project demo failed: $(cat "$TMP/err")"
python3 - "$OUT" <<'PY' || fail "pm placement is not the project space"
import json, sys
d = json.loads(sys.argv[1])
assert d["mode"] == "tab", d
assert d["space"] == "demo", d
assert d["tab"] == "manager-demo", d
PY
grep -q "do space.new --name demo " "$TMP/calls.log" \
  || fail "pm did not create a space named after the project: $(head -2 "$TMP/calls.log")"
grep -q -- "--tab manager-demo" "$TMP/calls.log" || fail "pm tab is not manager-demo"
ok "pm --project demo opens space 'demo' (tab manager-demo)"

# --- 3. --space alongside --project is refused -----------------------------
if run_spawn pm "$TMP/brief.md" --project demo --space "Herdr Team" >/dev/null; then
  fail "--space was accepted together with --project"
fi
grep -q "exclusive" "$TMP/err" || fail "ambiguous --space/--project was refused without the reason"
ok "--space + --project is refused"

# --- 4. an existing project space is reused, not duplicated ---------------
: > "$TMP/calls.log"
OUT="$(STUB_SPACES=project run_spawn pm "$TMP/brief.md" --project demo)" || fail "pm reuse failed: $(cat "$TMP/err")"
grep -q "do tab.new --space sp1 --name manager-demo" "$TMP/calls.log" \
  || fail "existing project space was not reused: $(cat "$TMP/calls.log")"
ok "existing project space is reused"

# --- 5. a role below pm runs as a child of its controller ------------------
: > "$TMP/calls.log"
OUT="$(run_spawn coder "$TMP/brief.md" --project demo --controller t32 --task-tier standard)" \
  || fail "coder child spawn failed: $(cat "$TMP/err")"
python3 - "$OUT" <<'PY' || fail "coder placement is not a child terminal"
import json, sys
d = json.loads(sys.argv[1])
assert d["mode"] == "child", d
assert d["parent"] == "t32", d
assert d["tab"] == "", d
PY
grep -q "hc run --bg --name coder-demo" "$TMP/calls.log" \
  || fail "coder did not start through hc run: $(cat "$TMP/calls.log")"
grep -q -- "--parent t32" "$TMP/calls.log" || fail "child has no hc parent"
grep -q "do tab.new" "$TMP/calls.log" && fail "a below-pm role opened a tab"
grep -q "HERDR_VOICE_MODE=off" "$TMP/calls.log" || fail "child does not default voice to off"
ok "coder runs as a child of t32 with no tab"

# --- 4b. the dispatch tells the controller how to wait ---------------------
grep -q "wait --children any" "$TMP/err" \
  || fail "the spawn hint does not name the one cheap wait: $(cat "$TMP/err")"
grep -q "never:" "$TMP/err" || fail "the spawn hint does not forbid polling"
ok "dispatch prints the single wait call and forbids sleep/poll"

# --- 5a. the tier decides the runtime: critical launches claude ------------
# Regression: the spawner used to hardcode --runtime pi, so every critical
# role (claude/opus primary) was refused by agent-runtime's policy check.
: > "$TMP/calls.log"
run_spawn coder "$TMP/brief.md" --project demo --controller t32 --task-tier critical \
  --intake "$TMP/intake-critical.json" >/dev/null \
  || fail "critical coder spawn failed: $(cat "$TMP/err")"
grep -q -- "--runtime claude" "$TMP/calls.log" \
  || fail "critical coder did not launch the claude runtime: $(head -3 "$TMP/calls.log")"
grep -q -- "--model opus" "$TMP/calls.log" || fail "critical coder did not get the opus model"
: > "$TMP/calls.log"
run_spawn coder "$TMP/brief.md" --project demo --controller t32 --task-tier standard >/dev/null \
  || fail "standard coder spawn failed: $(cat "$TMP/err")"
grep -q -- "--runtime pi" "$TMP/calls.log" \
  || fail "standard coder stopped using the pi runtime: $(head -3 "$TMP/calls.log")"
: > "$TMP/calls.log"
run_spawn coder "$TMP/brief.md" --project demo --controller t32 --task-tier standard \
  --runtime claude --model opus >/dev/null \
  || fail "--runtime override failed: $(cat "$TMP/err")"
grep -q -- "--runtime claude" "$TMP/calls.log" || fail "--runtime claude was ignored"
: > "$TMP/calls.log"
run_spawn reviewer "$TMP/brief.md" --project demo --controller t32 --task-tier critical \
  --intake "$TMP/intake-critical.json" --runtime pi \
  --model "kiro/claude-opus-5-5" --routing-exception >/dev/null \
  || fail "reviewer alternate spawn failed: $(cat "$TMP/err")"
grep -q -- "--routing-exception" "$TMP/calls.log" \
  || fail "the configured alternate was launched without --routing-exception"
grep -q -- "--runtime pi" "$TMP/calls.log" || fail "reviewer alternate did not use the pi runtime"
: > "$TMP/calls.log"
run_spawn coder "$TMP/brief.md" --project demo --controller t32 --task-tier critical \
  --intake "$TMP/intake-critical.json" --commit-mode auto >/dev/null \
  || fail "auto commit spawn failed: $(cat "$TMP/err")"
grep -q -- "--commit-mode auto" "$TMP/calls.log" || fail "--commit-mode auto was not forwarded"
if run_spawn pm "$TMP/brief.md" --project demo --controller t32 --commit-mode auto >"$TMP/out" 2>"$TMP/err"; then
  fail "auto commit was allowed for pm"
fi
grep -q "valid only for coder, refactor or supervisor" "$TMP/err" \
  || fail "auto commit on pm was refused without the reason: $(cat "$TMP/err")"
if run_spawn coder "$TMP/brief.md" --project demo --controller t32 --commit-mode sometimes >"$TMP/out" 2>"$TMP/err"; then
  fail "an invalid --commit-mode was accepted"
fi
ok "critical tier launches claude/opus, standard stays pi, --runtime overrides"

# --- 5b. voice mode is inherited by children ------------------------------
: > "$TMP/calls.log"
HERDR_VOICE_MODE=on run_spawn reviewer "$TMP/brief.md" --project demo --controller t32 --task-tier standard >/dev/null \
  || fail "reviewer child spawn with voice failed: $(cat "$TMP/err")"
grep -q "HERDR_VOICE_MODE=on" "$TMP/calls.log" || fail "child did not inherit HERDR_VOICE_MODE=on"
ok "child inherits HERDR_VOICE_MODE=on"

# --- 6. documenter gets a real group tab name ------------------------------
: > "$TMP/calls.log"
run_spawn documenter "$TMP/brief.md" --project demo --place tab --task-tier standard >/dev/null \
  || fail "documenter tab spawn failed: $(cat "$TMP/err")"
grep -q -- "--tab doc-demo" "$TMP/calls.log" || fail "documenter tab name is not doc-demo: $(head -2 "$TMP/calls.log")"
ok "documenter tab is doc-demo (never '-demo')"

# --- 7. orchestrator keeps the control space ------------------------------
: > "$TMP/calls.log"
OUT="$(run_spawn orchestrator "$TMP/brief.md")" || fail "orchestrator spawn failed: $(cat "$TMP/err")"
python3 - "$OUT" <<'PY' || fail "orchestrator is not in the control space"
import json, sys
d = json.loads(sys.argv[1])
assert d["space"] == "Herdr Team", d
assert d["tab"] == "orchestrator", d
PY
ok "orchestrator stays in the control space"

# --- 8. a project gets exactly one PM -------------------------------------
if STUB_LIVE_PM=1 run_spawn pm "$TMP/brief.md" --project demo >/dev/null 2>"$TMP/err"; then
  fail "a second PM was allowed in a project that already has one"
fi
grep -q "already has a live PM" "$TMP/err" || fail "duplicate PM was refused without the reason: $(cat "$TMP/err")"
ok "a second PM in the same project is refused"

OUT="$(STUB_LIVE_PM=1 run_spawn pm "$TMP/brief.md" --project demo --force)" \
  || fail "--force did not bypass the duplicate-PM guard: $(cat "$TMP/err")"
ok "--force bypasses the duplicate-PM guard"

# --- 9. the spawn-time PM registry closes the label race -----------------
REGISTRY="$TMP/pm-registry"
mkdir -p "$REGISTRY"
printf 't77\n' > "$REGISTRY/demo.terminal"
if STUB_LIVE_REGISTERED=1 HERDR_TEAM_PM_REGISTRY="$REGISTRY" run_spawn pm "$TMP/brief.md" --project demo \
     >/dev/null 2>"$TMP/err"; then
  fail "a PM recorded as live in the registry was not refused"
fi
grep -q "already has a PM: t77" "$TMP/err" || fail "registry refusal lacks the terminal id: $(cat "$TMP/err")"
ok "a live PM in the spawn-time registry is refused"

STUB_LIVE_REGISTERED=0 HERDR_TEAM_PM_REGISTRY="$REGISTRY" run_spawn pm "$TMP/brief.md" --project demo \
  >/dev/null 2>"$TMP/err" || fail "a stale registry entry blocked a fresh PM: $(cat "$TMP/err")"
grep -q "$TMP/work" "$TMP/calls.log" || true
ok "a stale registry entry does not block a fresh PM"

# --- 10. --intake makes the resolver the staffing authority ---------------
cat > "$TMP/intake.json" <<'JSON'
{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true,"risk":"low"}
JSON
: > "$TMP/calls.log"
OUT="$(run_spawn coder "$TMP/brief.md" --project demo --controller t32 --intake "$TMP/intake.json")" \
  || fail "coder with --intake failed: $(cat "$TMP/err")"
grep -q -- "--task-tier standard" "$TMP/calls.log" \
  || fail "the intake tier was not passed through: $(head -2 "$TMP/calls.log")"
ok "--intake supplies the tier (standard) without --task-tier"

if run_spawn sa "$TMP/brief.md" --project demo --controller t32 --intake "$TMP/intake.json" \
     >/dev/null 2>"$TMP/err"; then
  fail "a role outside the resolved shape was allowed"
fi
grep -q "not part of shape W4-fix-test" "$TMP/err" || fail "shape refusal lacks the shape name: $(cat "$TMP/err")"
grep -q "coder | tester" "$TMP/err" || fail "shape refusal does not list the allowed roles: $(cat "$TMP/err")"
ok "a role outside the resolved shape is refused"

if run_spawn coder "$TMP/brief.md" --project demo --controller t32 --intake "$TMP/intake.json" \
     --task-tier critical >/dev/null 2>"$TMP/err"; then
  fail "a --task-tier that disagrees with the intake was accepted"
fi
grep -q "disagrees with the intake" "$TMP/err" || fail "tier disagreement was not explained: $(cat "$TMP/err")"
ok "a --task-tier that fights the intake is refused"

if run_spawn pm "$TMP/brief.md" --project demo --intake "$TMP/intake.json" >/dev/null 2>"$TMP/err"; then
  fail "PM bootstrap accepted --intake"
fi
grep -q "PM is bootstrap" "$TMP/err" || fail "PM + --intake was refused without the reason"
if run_spawn coder "$TMP/brief.md" --project demo --controller t32 --intake "$TMP/nope.json" \
     >/dev/null 2>"$TMP/err"; then
  fail "a missing intake file was accepted"
fi
grep -q "intake file not readable" "$TMP/err" || fail "missing intake was refused without the reason"
ok "PM bootstrap and a missing intake file are refused"

echo "herdr-app-spawn-role test: ok"