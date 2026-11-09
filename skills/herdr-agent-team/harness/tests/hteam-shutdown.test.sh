#!/usr/bin/env bash
# hteam-shutdown must close the team terminals, close itself last, and refuse to
# close someone else's session. The app core is stubbed, so nothing real dies.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "hteam-shutdown test: $*" >&2; exit 1; }

cat > "$TMP/hc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HC_TEST_LOG"
case "$1" in
  ls) cat <<'JSON'
{"terminals":[
 {"address":"t8f","agent":"zsh","state":"live"},
 {"address":"t8g","agent":"pi","state":"live"},
 {"address":"t8h","agent":"pi","state":"live"},
 {"address":"t90","agent":"pi","state":"done"}
]}
JSON
  ;;
  kill|server) exit 0 ;;
esac
STUB
chmod +x "$TMP/hc"

run() { # $@ = env assignments + args
  : > "$TMP/log"
  env HC_TEST_LOG="$TMP/log" HC_BIN="$TMP/hc" HC_TERMINAL_ID="${SELF_ID-t8g}" \
      HERDR_AGENT_ROLE="${ROLE-orchestrator}" "$ROOT/bin/hteam-shutdown" "$@" >"$TMP/out" 2>&1
}

# default: team terminals now, this pane last
run
grep -q '^kill t8f$' "$TMP/log" || fail "did not close t8f"
grep -q '^kill t8h$' "$TMP/log" || fail "did not close t8h"
grep -q 'kill t90' "$TMP/log" && fail "closed a finished terminal"
sleep 1.2
[ "$(grep -c '^kill' "$TMP/log")" = "3" ] || fail "expected three kills, got: $(grep -c '^kill' "$TMP/log")"
[ "$(grep '^kill' "$TMP/log" | tail -1)" = "kill t8g" ] || fail "this pane was not closed last"

# --keep-orchestrator leaves this pane alone
run --keep-orchestrator
sleep 1.2
grep -q 'kill t8g' "$TMP/log" && fail "--keep-orchestrator still closed this pane"

# --dry-run kills nothing
run --dry-run
grep -q '^kill' "$TMP/log" && fail "--dry-run killed something"
grep -q 'would close' "$TMP/out" || fail "--dry-run printed no plan"

# --server-stop stops the core after the team panes (the self-kill is detached
# and may land after the core is gone, which is fine: the pane dies either way)
run --server-stop
sleep 1.2
[ "$(grep -c '^kill' "$TMP/log")" = "3" ] || fail "--server-stop changed the kill count"
grep -q '^server stop$' "$TMP/log" || fail "--server-stop did not stop the core"
team_last="$(grep -n '^kill t8[^g]' "$TMP/log" | tail -1 | cut -d: -f1)"
server_line="$(grep -n '^server stop$' "$TMP/log" | cut -d: -f1)"
[ "$server_line" -gt "$team_last" ] || fail "core stopped before the team panes were closed"

# a non-orchestrator role is refused
set +e
: > "$TMP/log"
env HC_TEST_LOG="$TMP/log" HC_BIN="$TMP/hc" HC_TERMINAL_ID=t90 HERDR_AGENT_ROLE=coder \
    "$ROOT/bin/hteam-shutdown" >"$TMP/out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "coder was allowed to close the session"
grep -q '^kill' "$TMP/log" && fail "refused role still killed terminals"

# no pane identity is refused without --force
set +e
: > "$TMP/log"
env HC_TEST_LOG="$TMP/log" HC_BIN="$TMP/hc" HERDR_AGENT_ROLE=orchestrator \
    "$ROOT/bin/hteam-shutdown" >"$TMP/out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "ran without a pane identity"

echo "hteam-shutdown test: ok"