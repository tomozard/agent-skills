#!/usr/bin/env bash
# Offline tests for bin/hteam-agent: cloning a role contract into a machine-local
# role, its guardrails, and its removal. Everything runs in a throwaway HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The installer validates a copy of this payload at a temporary root, where
# ROOT/.. is not the skill. Prefer the skill that owns this payload, then the
# installed one, and skip only when no skill exists at all.
resolve_skill() {
  for candidate in "${HERDR_AGENT_TEAM_SKILL_DIR:-}" "$ROOT/.." \
                   "$HOME/.agents/skills/herdr-agent-team"; do
    [ -n "$candidate" ] && [ -x "$candidate/scripts/team-config" ] \
      && (cd "$candidate" && pwd) && return 0
  done
  return 1
}
SKILL="$(resolve_skill)" || {
  echo "  skip  the skill scripts are not installed; this suite needs them"
  exit 0
}
# The tools resolve team-config through this variable; a payload copy at a temp
# root has no scripts/ of its own, so point them at the skill explicitly.
export HERDR_AGENT_TEAM_SCRIPTS="$SKILL/scripts"
AGENT="$ROOT/bin/hteam-agent"
TEAM_CONFIG="$SKILL/scripts/team-config"
RESOLVER="$SKILL/scripts/workflow-shape"
BASE="$SKILL/config/team.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "hteam agent test: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

[ -x "$AGENT" ] || fail "hteam-agent is not executable"
python3 - "$AGENT" <<'PY' || fail "hteam-agent Python syntax failed"
import ast
import sys
ast.parse(open(sys.argv[1], encoding="utf-8").read())
PY

export HOME="$TMP/home"
mkdir -p "$HOME/.agents"
export HERDR_TEAM_BASE="$BASE"
TEAM="$HOME/.agents/team.json"
OVERLAY="$HOME/.config/herdr-team/team.local.json"
ROLE_TEXT="$HOME/.config/herdr-team/roles/security_reviewer.md"
CLAUDE_TEXT="$HOME/.claude/agents/herdr-security_reviewer.md"

"$TEAM_CONFIG" render >/dev/null || fail "render failed"

# 1. No local roles at first.
"$AGENT" --json > "$TMP/empty.json" || fail "--json failed"
python3 - "$TMP/empty.json" <<'PY' || fail "the empty view is wrong"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["local_roles"] == {}, data
PY
ok "--json starts empty"

# 2. Add a verifier clone.
"$AGENT" --add security_reviewer --from reviewer --shapes W3-fix > "$TMP/add.txt" 2>&1 \
  || fail "add failed: $(cat "$TMP/add.txt")"
[ -f "$TEAM" ] || fail "the effective roster was not rendered"
[ -f "$OVERLAY" ] || fail "the overlay was not written"
[ -f "$ROLE_TEXT" ] || fail "the local role text was not written"
[ -f "$CLAUDE_TEXT" ] || fail "the Claude agent file was not written"
grep -q 'local role: security_reviewer' "$ROLE_TEXT" || fail "the role text is not marked"
python3 - "$TEAM" "$OVERLAY" <<'PY' || fail "the overlay or roster entry is wrong"
import json
import sys

overlay = json.load(open(sys.argv[1], encoding="utf-8"))
team = json.load(open(sys.argv[2], encoding="utf-8"))
local = overlay["local_roles"]["security_reviewer"]
assert local["base"] == "reviewer" and local["kind"] == "verifier", local
assert local["shapes"] == ["W3-fix"], local
assert team["roles"]["security_reviewer"]["repo_mode"] == "read_only", team["roles"]["security_reviewer"]
assert team["roles"]["security_reviewer"]["model_selection"] == "fixed"
PY
ok "add writes role text, Claude file, overlay, and roster"

# 3. The resolver staffs it in a declared shape only.
printf '%s\n' '{"task_class":"bug-fix","known_cause":true,"touches_behavior":true,"runnable_acceptance":false}' > "$TMP/intake.json"
"$RESOLVER" --team "$TEAM" --intake "$TMP/intake.json" --format json > "$TMP/w3.json" \
  || fail "resolver failed on W3-fix"
python3 - "$TMP/w3.json" <<'PY' || fail "W3-fix did not staff the local verifier"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["shape"] == "W3-fix", data["shape"]
assert "security_reviewer" in data["verifiers"], data["verifiers"]
assert "reviewer" in data["verifiers"], data["verifiers"]
PY

printf '%s\n' '{"task_class":"feature","new_behavior":true,"touches_behavior":true,"runnable_acceptance":true}' > "$TMP/intake2.json"
"$RESOLVER" --team "$TEAM" --intake "$TMP/intake2.json" --format json > "$TMP/w7.json" \
  || fail "resolver failed on W7-feature"
python3 - "$TMP/w7.json" <<'PY' || fail "an undeclared shape staffed the local role"
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["shape"] == "W7-feature", data["shape"]
assert "security_reviewer" not in data["verifiers"], data["verifiers"]
PY
ok "the resolver staffs it only in the declared shapes"

# 4. Guardrails.
if "$AGENT" --add coder --from reviewer --shapes W3-fix >/dev/null 2>&1; then
  fail "a built-in name must be refused"
fi
if "$AGENT" --add x --from ghost --shapes W3-fix >/dev/null 2>&1; then
  fail "an unknown base role must be refused"
fi
if "$AGENT" --add x --from pm --shapes W3-fix >/dev/null 2>&1; then
  fail "a controller must not be cloneable"
fi
if "$AGENT" --add x --from reviewer --kind worker --shapes W3-fix >/dev/null 2>&1; then
  fail "a kind that contradicts the base must be refused"
fi
if "$AGENT" --add x --from reviewer --shapes W99 >/dev/null 2>&1; then
  fail "an unknown shape must be refused"
fi
if "$AGENT" --add x --from reviewer --shapes "" >/dev/null 2>&1; then
  fail "an empty shape list must be refused"
fi
if "$AGENT" --add x --from coder --shapes W3-fix >/dev/null 2>&1; then
  fail "a name shorter than two characters must be refused"
fi
ok "guardrails refuse unsafe or contradictory clones"

# 5. A worker clone keeps write authority only when the base had it.
"$AGENT" --add hotfix_coder --from coder --shapes W3-fix >/dev/null || fail "worker clone failed"
python3 - "$TEAM" <<'PY' || fail "the worker clone lost or gained authority"
import json
import sys

team = json.load(open(sys.argv[1], encoding="utf-8"))
entry = team["roles"]["hotfix_coder"]
assert entry["repo_mode"] == "write", entry
assert entry["may_local_commit"] is True, entry
PY
ok "a worker clone keeps the base's write authority"

# 6. Remove deletes every trace and restores the roster.
"$AGENT" --remove security_reviewer >/dev/null || fail "remove failed"
[ ! -e "$ROLE_TEXT" ] || fail "the role text survived removal"
[ ! -e "$CLAUDE_TEXT" ] || fail "the Claude file survived removal"
python3 - "$TEAM" "$OVERLAY" <<'PY' || fail "removal left state behind"
import json
import sys

team = json.load(open(sys.argv[1], encoding="utf-8"))
overlay = json.load(open(sys.argv[2], encoding="utf-8"))
assert "security_reviewer" not in team["roles"], team["roles"].keys()
assert "security_reviewer" not in overlay.get("local_roles", {}), overlay
PY
"$RESOLVER" --team "$TEAM" --intake "$TMP/intake.json" --format json > "$TMP/w3-after.json" \
  || fail "resolver failed after removal"
python3 - "$TMP/w3-after.json" <<'PY' || fail "removal did not take effect in the resolver"
import json
import sys

assert "security_reviewer" not in json.load(open(sys.argv[1], encoding="utf-8"))["verifiers"]
PY
ok "remove deletes the files, the overlay entry, and the roster entry"

# 7. Interactive mode needs a TTY.
if "$AGENT" </dev/null >/dev/null 2>&1; then
  fail "interactive mode without a TTY must exit 2"
else
  [ "$?" -eq 2 ] || fail "interactive mode without a TTY must exit 2"
fi
ok "interactive mode is refused without a TTY"

echo "hteam agent test: ok"
