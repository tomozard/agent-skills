#!/usr/bin/env bash
# Offline tests for bin/clickup-status: the ClickUp status helpers
# (init/ask/mark/status/check). Nothing here talks to ClickUp or to a live pane.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/bin/clickup-status"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CLICKUP_STATUS_CONFIG="$TMP/clickup-status.yaml"
export CLICKUP_STATUS_STATE_DIR="$TMP/state"

fail() { echo "clickup-status test: $*" >&2; exit 1; }

python3 -m py_compile "$CLI" || fail "python syntax failed"
[ -x "$CLI" ] || fail "clickup-status is not executable"

# 1. The intake loop is gone; only the status helpers remain.
for sub in init ask mark status check; do
  "$CLI" "$sub" --help >/dev/null 2>&1 || fail "the $sub subcommand is missing"
done
for gone in loop start stop once; do
  if "$CLI" "$gone" >/dev/null 2>"$TMP/err"; then
    fail "the removed '$gone' subcommand still works"
  fi
  grep -q "invalid choice" "$TMP/err" || fail "'$gone' did not fail as an unknown subcommand"
done

# 2. init writes only the retained keys.
"$CLI" init --force >"$TMP/init.txt" || fail "init failed"
[ -f "$CLICKUP_STATUS_CONFIG" ] || fail "init did not write the config"
grep -q '^claim_assignee: "me"$' "$CLICKUP_STATUS_CONFIG" || fail "init lost claim_assignee"
for gone in interval max_tasks stale_hours require_tag terminal_name team_space orch_retry_seconds; do
  if grep -q "^$gone:" "$CLICKUP_STATUS_CONFIG"; then
    fail "init still writes the watcher key $gone"
  fi
done
grep -q "no poll loop to restart" "$TMP/init.txt" || fail "init still mentions restarting the loop"

# 3. status reports the file in use.
printf 'workspace_id: "999"\nlist_id: "123"\n' > "$CLICKUP_STATUS_CONFIG"
out="$("$CLI" status 2>&1)" || fail "status failed"
grep -q "config:.*$TMP/clickup-status.yaml" <<<"$out" || fail "status does not name the config"
grep -q "list:        123" <<<"$out" || fail "status does not show list_id"

# 4. mark validates the writable statuses.
if "$CLI" mark --task ABC --status done --dry-run --force >"$TMP/out" 2>&1; then
  fail "mark accepted a Human-owned status"
fi
grep -q "not writable by the agent" "$TMP/out" || fail "mark refused without the reason"

# 5. mark dry-run renders the comment and the target status.
out="$("$CLI" mark --task ABC --status ready --dry-run --force 2>&1)" || fail "mark dry-run failed"
grep -q "would comment on ABC" <<<"$out" || fail "mark dry-run printed no comment"
grep -q "would set status: ready" <<<"$out" || fail "mark dry-run printed no status"

# 6. ask dry-run renders the question and parks in discuss.
out="$("$CLI" ask --task ABC --text "which branch?" --dry-run --force 2>&1)" || fail "ask dry-run failed"
grep -q "which branch?" <<<"$out" || fail "ask dry-run dropped the question"
grep -q "would set status: discuss" <<<"$out" || fail "ask dry-run did not park in discuss"

# 7. check is offline and fails closed without an MCP login.
if CLICKUP_MCP_TOKEN_FILE="$TMP/no-such-token" "$CLI" check >"$TMP/check.txt" 2>&1; then
  fail "check passed without an MCP login"
fi
grep -q "MISS: ClickUp MCP login" "$TMP/check.txt" || fail "check did not name the missing login"

# 8. the legacy env names still work.
legacy_out="$(CLICKUP_STATUS_CONFIG= CLICKUP_WATCH_CONFIG="$TMP/clickup-status.yaml" "$CLI" status 2>&1)" \
  || fail "the legacy CLICKUP_WATCH_CONFIG env is no longer accepted"
grep -q "config:.*$TMP/clickup-status.yaml" <<<"$legacy_out" || fail "legacy env did not reach the config"

echo "clickup-status test: ok"
