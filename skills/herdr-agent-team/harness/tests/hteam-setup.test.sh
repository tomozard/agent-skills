#!/usr/bin/env bash
# Offline tests for bin/hteam-setup (the guided setup wizard) and its entry
# points. Every run is sandboxed in a throwaway HOME and config, with fake git
# repositories, so the real registry and config are never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$ROOT/bin/hteam-setup"
LAUNCHER="$ROOT/bin/herdr-app-team"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "hteam setup test: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

[ -x "$SETUP" ] || fail "hteam-setup is not executable"
python3 - "$SETUP" <<'PY' || fail "hteam-setup Python syntax failed"
import ast
import sys
ast.parse(open(sys.argv[1], encoding="utf-8").read())
PY

HOME_DIR="$TMP/home"
CONFIG="$TMP/hteam.yaml"
PROJECTS="$TMP/projects"
VAULT="$TMP/vault"
mkdir -p "$HOME_DIR" "$PROJECTS/app-a/.git" "$PROJECTS/app-b/.git"

setup() {
  HOME="$HOME_DIR" HERDR_TEAM_CONFIG="$CONFIG" "$SETUP" "$@"
}

# 1. A wizard needs a TTY unless --defaults is given.
if HOME="$HOME_DIR" HERDR_TEAM_CONFIG="$CONFIG" "$SETUP" </dev/null >/dev/null 2>&1; then
  fail "a non-TTY run without --defaults must exit 2"
else
  [ "$?" -eq 2 ] || fail "a non-TTY run must exit 2"
fi
ok "non-TTY without --defaults is refused"

# 2. --dry-run writes nothing.
setup --defaults --dry-run --folder "$PROJECTS" --vault "$VAULT" --projects all >"$TMP/dry.txt" 2>&1 \
  || fail "--dry-run failed"
[ ! -e "$CONFIG" ] || fail "--dry-run wrote the config"
[ ! -e "$PROJECTS/.agents/workspace-registry.yaml" ] || fail "--dry-run wrote the registry"
[ ! -d "$VAULT" ] || fail "--dry-run created the vault"
grep -q 'would run:' "$TMP/dry.txt" || fail "--dry-run did not print the planned config writes"
ok "--dry-run writes nothing and prints the plan"

# 3. A real run writes the config and a registry that follows --folder.
setup --defaults --folder "$PROJECTS" --vault "$VAULT" --projects all >"$TMP/run.txt" 2>&1 \
  || fail "the wizard run failed"
[ -f "$CONFIG" ] || fail "the config was not written"
grep -q "folder: $PROJECTS" "$CONFIG" || fail "the config did not record the folder"
grep -q "vault: $VAULT" "$CONFIG" || fail "the config did not record the vault"
REGISTRY="$PROJECTS/.agents/workspace-registry.yaml"
[ -f "$REGISTRY" ] || fail "the registry was not written under the chosen folder"
python3 - "$REGISTRY" <<'PY' || fail "the registry is not the documented shape"
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
projects = data["projects"]
assert set(projects) == {"app_a", "app_b"}, projects
for entry in projects.values():
    assert entry["status"] == "active", entry
    assert entry["path"], entry
PY
ok "a real run writes config and registry under the chosen folder"

# 4. Re-running is idempotent and never duplicates or rewrites entries.
setup --defaults --folder "$PROJECTS" --vault "$VAULT" --projects all >"$TMP/run2.txt" 2>&1 \
  || fail "the second run failed"
grep -q 'registry unchanged' "$TMP/run2.txt" || fail "the second run rewrote the registry"
python3 - "$REGISTRY" <<'PY' || fail "the second run duplicated registry entries"
import sys
import yaml

assert len(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["projects"]) == 2
PY
ok "re-running is idempotent"

# 5. --json prints only JSON.
setup --defaults --json --folder "$PROJECTS" --vault "$VAULT" --projects none >"$TMP/json.txt" 2>&1 \
  || fail "--json failed"
python3 - "$TMP/json.txt" <<'PY' || fail "--json is not a single JSON document"
import json
import sys

text = open(sys.argv[1], encoding="utf-8").read().strip()
assert text.startswith("{"), text[:40]
data = json.loads(text)
assert data["schema"] == 1, data
assert data["status"] == "ok", data
assert data["config"]["folder"].endswith("projects"), data["config"]
PY
ok "--json is machine readable on its own"

# 6. --only limits the steps it touches.
setup --defaults --only voice --voice on >"$TMP/only.txt" 2>&1 || fail "--only voice failed"
python3 - "$CONFIG" <<'PY' || fail "--only voice did not set voice"
import sys

import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data.get("voice") == "on", data
PY
ok "--only limits the steps"

# 7. The launcher hands `setup` to the wizard.
HOME="$HOME_DIR" HERDR_TEAM_CONFIG="$CONFIG" "$LAUNCHER" setup --defaults --json --only folder --folder "$PROJECTS" \
  >"$TMP/via-launcher.txt" 2>&1 || fail "hteam setup failed through the launcher"
python3 - "$TMP/via-launcher.txt" <<'PY' || fail "the launcher did not reach the wizard"
import json
import sys

data = json.loads(open(sys.argv[1], encoding="utf-8").read().strip())
assert data["steps"] == ["folder"], data["steps"]
PY
ok "hteam setup reaches the same wizard"

# 8. A host without Herdr cannot be configured.
if HOME="$HOME_DIR" HERDR_APP_BIN=/nonexistent/herdr-app HC_BIN=/nonexistent/herdr-core \
   HERDR_TEAM_CONFIG="$CONFIG" "$SETUP" --defaults --json >/dev/null 2>&1; then
  fail "a host without Herdr must exit 3"
else
  [ "$?" -eq 3 ] || fail "a host without Herdr must exit 3"
fi
ok "a host without Herdr exits 3"

echo "hteam setup test: ok"
