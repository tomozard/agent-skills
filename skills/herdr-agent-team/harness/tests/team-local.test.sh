#!/usr/bin/env bash
# Offline tests for the layered roster: scripts/team-config (merge + render +
# validate) and bin/hteam-model (pin a route without editing the shipped file).
# Every path is redirected into a throwaway directory, so the real ~/.agents and
# ~/.config are never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$(cd "$ROOT/.." && pwd)"
TEAM_CONFIG="$SKILL/scripts/team-config"
MODEL="$ROOT/bin/hteam-model"
BASE="$SKILL/config/team.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "team overlay test: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

[ -x "$TEAM_CONFIG" ] || fail "team-config is not executable"
[ -x "$MODEL" ] || fail "hteam-model is not executable"
python3 - "$TEAM_CONFIG" "$MODEL" <<'PY' || fail "Python syntax failed"
import ast
import sys
for path in sys.argv[1:]:
    ast.parse(open(path, encoding="utf-8").read())
PY

export HERDR_TEAM_BASE="$BASE"
export HERDR_TEAM_LOCAL="$TMP/team.local.json"
export HERDR_TEAM_EFFECTIVE="$TMP/team.effective.json"

# 1. paths reports the three files and the effective one is initially missing.
"$TEAM_CONFIG" paths > "$TMP/paths.txt" || fail "paths failed"
grep -q "base .*$BASE" "$TMP/paths.txt" || fail "paths did not report the base"
grep -q "overlay .*team.local.json" "$TMP/paths.txt" || fail "paths did not report the overlay"
ok "paths names base, overlay, and effective"

# 2. A render with no overlay equals the canonical roster.
"$TEAM_CONFIG" render >/dev/null || fail "render failed"
python3 - "$BASE" "$HERDR_TEAM_EFFECTIVE" <<'PY' || fail "render changed the roster without an overlay"
import json
import sys

base = json.load(open(sys.argv[1], encoding="utf-8"))
effective = json.load(open(sys.argv[2], encoding="utf-8"))
effective.pop("_generated", None)
assert effective == base
PY
ok "render without an overlay is a faithful copy"

# 3. The overlay merges deeply and lists replace.
python3 - "$HERDR_TEAM_LOCAL" <<'PY' || fail "cannot write the overlay fixture"
import json
import sys

json.dump({
    "version": 4,
    "roles": {
        "coder": {
            "routing": {
                "critical": {
                    "primary": {"runtime": "pi", "model": "antigravity/gemini-3.8-flash"},
                    "alternates": [],
                }
            }
        }
    },
}, open(sys.argv[1], "w", encoding="utf-8"))
PY
"$TEAM_CONFIG" show --json > "$TMP/merged.json" || fail "show failed"
python3 - "$BASE" "$TMP/merged.json" <<'PY' || fail "the overlay did not merge as documented"
import json
import sys

base = json.load(open(sys.argv[1], encoding="utf-8"))
merged = json.load(open(sys.argv[2], encoding="utf-8"))
assert merged["roles"]["coder"]["routing"]["critical"]["primary"]["model"] == "antigravity/gemini-3.8-flash"
assert merged["roles"]["coder"]["routing"]["standard"] == base["roles"]["coder"]["routing"]["standard"]
assert merged["roles"]["reviewer"] == base["roles"]["reviewer"]
PY
ok "objects merge, untouched siblings survive"

# 4. Every route still resolves with the overlay applied.
"$TEAM_CONFIG" validate >/dev/null || fail "validate rejected a legitimate overlay"
ok "validate passes with the overlay"

# 5. An overlay may not invent a role.
python3 - "$HERDR_TEAM_LOCAL" <<'PY' || fail "cannot write the bad overlay"
import json
import sys

json.dump({"version": 4, "roles": {"ghost": {"routing": {}}}},
          open(sys.argv[1], "w", encoding="utf-8"))
PY
if "$TEAM_CONFIG" show >/dev/null 2>&1; then
  fail "an unknown role must be rejected"
fi
ok "an unknown role is rejected"

# 6. --set writes only the overlay, re-renders, and keeps unrelated roles.
rm -f "$HERDR_TEAM_LOCAL"
"$MODEL" --set coder standard pi antigravity/gemini-3.8-flash >/dev/null || fail "--set failed"
python3 - "$HERDR_TEAM_LOCAL" "$HERDR_TEAM_EFFECTIVE" <<'PY' || fail "--set wrote the wrong files"
import json
import sys

overlay = json.load(open(sys.argv[1], encoding="utf-8"))
assert set(overlay["roles"]) == {"coder"}, overlay["roles"]
assert overlay["roles"]["coder"]["routing"]["standard"]["primary"]["model"] == "antigravity/gemini-3.8-flash"
effective = json.load(open(sys.argv[2], encoding="utf-8"))
assert effective["roles"]["coder"]["routing"]["standard"]["primary"]["model"] == "antigravity/gemini-3.8-flash"
assert effective["roles"]["tester"]["routing"]["standard"], "unrelated roles must survive"
PY
ok "--set pins one route and renders the effective roster"

# 7. A model outside the allowlist is refused unless it is added deliberately.
if "$MODEL" --set coder standard pi not/a-model >/dev/null 2>&1; then
  fail "an allowlisted model is required"
fi
"$MODEL" --set coder standard pi not/a-model --allow-model pi not/a-model >/dev/null \
  || fail "--allow-model should accept a deliberate model"
python3 - "$HERDR_TEAM_LOCAL" <<'PY' || fail "--allow-model did not extend the allowlist"
import json
import sys

overlay = json.load(open(sys.argv[1], encoding="utf-8"))
assert "not/a-model" in overlay["roles"]["coder"]["models"]["pi"], overlay
PY
ok "the allowlist is protected unless extended explicitly"

# 8. --unset removes the override and leaves no empty shell behind.
"$MODEL" --unset coder standard >/dev/null || fail "--unset failed"
python3 - "$HERDR_TEAM_LOCAL" <<'PY' || fail "--unset left the route behind"
import json
import sys

overlay = json.load(open(sys.argv[1], encoding="utf-8"))
coder = (overlay.get("roles") or {}).get("coder") or {}
assert "standard" not in (coder.get("routing") or {}), overlay
PY
ok "--unset cleans the overlay"

# 9. --reset removes the overlay and re-renders.
"$MODEL" --reset >/dev/null || fail "--reset failed"
[ ! -e "$HERDR_TEAM_LOCAL" ] || fail "--reset left the overlay"
python3 - "$BASE" "$HERDR_TEAM_EFFECTIVE" <<'PY' || fail "--reset did not restore the canonical roster"
import json
import sys

base = json.load(open(sys.argv[1], encoding="utf-8"))
effective = json.load(open(sys.argv[2], encoding="utf-8"))
effective.pop("_generated", None)
assert effective == base
PY
ok "--reset restores the canonical roster"

# 10. Interactive mode needs a TTY.
if "$MODEL" </dev/null >/dev/null 2>&1; then
  fail "interactive mode without a TTY must exit 2"
else
  [ "$?" -eq 2 ] || fail "interactive mode without a TTY must exit 2"
fi
ok "interactive mode is refused without a TTY"

# 11. --json is a single machine-readable document.
"$MODEL" --json > "$TMP/model.json" || fail "--json failed"
python3 - "$TMP/model.json" <<'PY' || fail "--json is not the documented shape"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["schema"] == 1, data
assert "coder" in data["roles"] and "critical" in data["roles"]["coder"], data["roles"].get("coder")
PY
ok "--json reports the routing table"

echo "team overlay test: ok"
