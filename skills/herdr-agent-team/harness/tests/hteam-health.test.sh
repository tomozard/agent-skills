#!/usr/bin/env bash
# Offline tests for bin/hteam-health (the readiness check) and the `hteam health`
# entry point. It starts no model, touches no Herdr space, and writes nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEALTH="$ROOT/bin/hteam-health"
LAUNCHER="$ROOT/bin/herdr-app-team"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "hteam health test: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

[ -x "$HEALTH" ] || fail "hteam-health is not executable"
python3 - "$HEALTH" <<'PY' || fail "hteam-health Python syntax failed"
import ast
import sys
ast.parse(open(sys.argv[1], encoding="utf-8").read())
PY

# 1. --json is machine readable and carries the documented keys.
status=0
"$HEALTH" --json > "$TMP/health.json" || status=$?
[ "$status" -le 1 ] || fail "--json exited with an unexpected code $status"
python3 - "$TMP/health.json" <<'PY' || fail "health JSON is not the documented shape"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["schema"] == 1, data.get("schema")
assert data["status"] in ("ok", "warn", "fail"), data["status"]
assert isinstance(data["host_ready"], bool)
assert isinstance(data["checks"], list) and data["checks"], "no checks reported"
for key in ("ok", "warn", "fail", "skip"):
    assert key in data["summary"], key
for check in data["checks"]:
    assert set(check) == {"section", "id", "status", "detail", "hint"}, check
    assert check["status"] in ("ok", "warn", "fail", "skip"), check
PY
ok "--json is schema 1 with a stable check shape"

# 2. --section filters to the requested section only.
"$HEALTH" --section host --json > "$TMP/host.json" || status=$?
[ "$status" -le 1 ] || fail "--section host exited with $status"
python3 - "$TMP/host.json" <<'PY' || fail "--section host leaked another section"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["checks"], "no host checks"
assert {check["section"] for check in data["checks"]} == {"host"}
PY
ok "--section returns only that section"

# 3. A missing Herdr is a host failure (exit 3), not a generic error.
if HERDR_APP_BIN=/nonexistent/herdr-app HC_BIN=/nonexistent/herdr-core \
   "$HEALTH" --json > "$TMP/missing.json"; then
  fail "missing Herdr must exit 3"
else
  [ "$?" -eq 3 ] || fail "missing Herdr must exit 3, got $?"
fi
python3 - "$TMP/missing.json" <<'PY' || fail "missing Herdr was not reported as a host failure"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["host_ready"] is False
failed = {check["id"] for check in data["checks"] if check["status"] == "fail"}
assert {"herdr-app", "herdr-core"} <= failed, failed
PY
ok "missing Herdr exits 3 and names both binaries"

# 4. The launcher hands `health` to the checker unchanged.
"$LAUNCHER" health --section policy --json > "$TMP/via-launcher.json" || status=$?
[ "$status" -le 1 ] || fail "hteam health exited with $status"
python3 - "$TMP/via-launcher.json" "$TMP/health.json" <<'PY' || fail "the launcher did not reach the checker"
import json
import sys

via = json.load(open(sys.argv[1], encoding="utf-8"))
direct = json.load(open(sys.argv[2], encoding="utf-8"))
assert via["schema"] == direct["schema"]
assert {check["section"] for check in via["checks"]} == {"policy"}
PY
ok "hteam health reaches the same checker"

# 5. The human output ends with a verdict line.
"$HEALTH" --section host > "$TMP/human.txt" || status=$?
[ "$status" -le 1 ] || fail "human output exited with $status"
grep -Eq '^(healthy|healthy with warnings|not healthy):' "$TMP/human.txt" \
  || fail "human output has no verdict line"
grep -q 'hint:' "$TMP/human.txt" \
  || fail "human output never prints a hint (the warnings lost their advice)"
ok "human output prints a verdict and hints"

echo "hteam health test: ok"
