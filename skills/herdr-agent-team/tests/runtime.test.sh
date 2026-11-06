#!/usr/bin/env bash

# Tests for scripts/roster and scripts/runtime-probe.
#
# Both scripts read configuration and the local machine only, so the whole suite
# runs offline with fake runtime binaries: no CLI is invoked, nothing is spoken,
# and no network call is made.

set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROSTER="$SKILL_DIR/scripts/roster"
PROBE="$SKILL_DIR/scripts/runtime-probe"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf '  ok  %s\n' "$*"; }

for exe in pi claude; do
  printf '#!/bin/sh\necho 9.9.9\n' > "$TMP/$exe"
  chmod +x "$TMP/$exe"
done
mkdir -p "$TMP/only-pi" "$TMP/only-claude" "$TMP/empty"
cp "$TMP/pi" "$TMP/only-pi/pi"
cp "$TMP/claude" "$TMP/only-claude/claude"

python3 - "$TMP/team.json" <<'PY'
import json, sys

team = {
    "version": 4,
    "runtime_order": ["pi", "claude"],
    "disabled_model_providers": [],
    "roles": {
        "coder": {
            "model_selection": "controller",
            "models": {"pi": ["p/one", "p/two"], "claude": ["opus"]},
            "routing": {
                "standard": {"primary": {"runtime": "pi", "model": "p/one"},
                             "alternates": [{"runtime": "claude", "model": "opus"},
                                            {"runtime": "pi", "model": "p/two"}]},
                "critical": {"primary": {"runtime": "claude", "model": "opus"},
                             "alternates": [{"runtime": "pi", "model": "p/one"}]},
            },
        },
        "solo": {
            "model_selection": "fixed",
            "models": {"claude": ["opus"]},
            "default_model": "opus",
        },
        "ghost": {
            "model_selection": "controller",
            "models": {"claude": ["opus"]},
            "routing": {
                "critical": {"primary": {"runtime": "claude", "model": "sonnet"},
                             "alternates": []},
            },
        },
    },
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(team, handle, indent=2)

disabled = json.loads(json.dumps(team))
disabled["disabled_model_providers"] = ["p"]
with open(sys.argv[1].replace("team.json", "team-disabled.json"), "w", encoding="utf-8") as handle:
    json.dump(disabled, handle, indent=2)
PY

json_field() { # json_field <key> <json on stdin>
  python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

# --- probe ----------------------------------------------------------------
"$PROBE" --json | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["version"] == 1, data
assert set(data["transport"]) == {"herdr", "hc", "herdr-app"}, data["transport"]
assert set(data["runtimes"]) == {"pi", "hermes", "codex", "claude", "opencode", "kiro-cli"}, data
assert all(set(v["verbs"]) == {"ask", "model", "system", "resume", "permissions"}
           for v in data["runtimes"].values()), data
' || fail "runtime-probe --json is not the documented shape"
ok "probe reports a stable JSON shape for every runtime"

PATH=/usr/bin:/bin "$PROBE" --json | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert not any(v["available"] for v in data["runtimes"].values()), data
' || fail "probe claims a runtime exists on an empty PATH"
ok "probe marks missing runtimes unavailable"

if "$PROBE" --bogus >/dev/null 2>&1; then fail "probe accepted an unknown flag"; fi
ok "probe rejects unknown flags"

# --- roster: normal resolution -------------------------------------------
out="$("$ROSTER" --team "$TMP/team.json" --path "$TMP" coder critical)" || fail "critical resolution failed: $out"
printf '%s' "$out" | grep -q '^runtime    claude$' || fail "critical did not pick the primary runtime: $out"
printf '%s' "$out" | grep -q '^selection  primary$' || fail "critical was not marked primary: $out"
ok "critical tier resolves the configured primary"

"$ROSTER" --team "$TMP/team.json" --path "$TMP/only-pi" coder critical | grep -q '^selection  alternate$' \
  || fail "an unavailable primary did not fall through to an alternate"
ok "an unavailable primary falls through to the alternate"

"$ROSTER" --team "$TMP/team.json" --path "$TMP/only-claude" coder critical \
  | grep -q '^runtime    claude$' || fail "installed primary was not chosen"
ok "an installed primary is preferred even when only it is present"

out="$("$ROSTER" --team "$TMP/team.json" --path "$TMP/only-claude" coder standard)" \
  || fail "standard resolution with one runtime failed: $out"
printf '%s' "$out" | grep -q '^selection  alternate$' || fail "standard did not use the listed alternate: $out"
printf '%s' "$out" | grep -q '^model      opus$' || fail "the alternate model is wrong: $out"
ok "standard tier uses the allowlisted alternate on a one-runtime machine"

"$ROSTER" --team "$TMP/team.json" --path "$TMP/only-claude" solo standard \
  | grep -q '^selection  fixed$' || fail "a fixed role did not resolve as fixed"
ok "fixed roles resolve without a tier route"

# --- roster: refusals -----------------------------------------------------
if "$ROSTER" --team "$TMP/team.json" --path "$TMP" coder easy >"$TMP/out" 2>&1; then
  fail "a retired tier was accepted"
fi
grep -q "retired" "$TMP/out" || fail "the retired-tier message is missing: $(cat "$TMP/out")"
ok "retired tiers are refused with the replacement named"

if "$ROSTER" --team "$TMP/team.json" --path "$TMP" nobody critical >"$TMP/out" 2>&1; then
  fail "an unknown role was accepted"
fi
grep -q "is not in" "$TMP/out" || fail "the unknown-role message is missing: $(cat "$TMP/out")"
ok "unknown roles are refused"

if "$ROSTER" --team "$TMP/team.json" --path "$TMP" ghost critical >"$TMP/out" 2>&1; then
  fail "a model outside the allowlist was launched"
fi
grep -q "allowlist" "$TMP/out" || fail "the allowlist refusal is missing: $(cat "$TMP/out")"
ok "a model outside the runtime allowlist is refused"

out="$("$ROSTER" --team "$TMP/team.json" --path "$TMP/empty" coder critical 2>&1)"
status=$?
[ "$status" = "3" ] || fail "an empty machine should exit 3, got $status: $out"
printf '%s' "$out" | grep -q '\[STUCK\]' || fail "STUCK is not reported: $out"
ok "nothing launchable is STUCK (exit 3), not a substitute"

# --- roster: disabled providers ------------------------------------------
out="$("$ROSTER" --team "$TMP/team-disabled.json" --path "$TMP" coder standard)" \
  || fail "standard resolution with a disabled provider failed: $out"
printf '%s' "$out" | grep -q '^runtime    claude$' || fail "the disabled provider was still used: $out"
printf '%s' "$out" | grep -q 'disabled' || fail "the disabled provider was not reported: $out"
ok "a disabled provider is skipped and named"

# --- roster: json output --------------------------------------------------
"$ROSTER" --team "$TMP/team.json" --path "$TMP" --json coder critical \
  | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["role"] == "coder" and data["tier"] == "critical", data
assert data["runtime"] == "claude" and data["model"] == "opus", data
assert data["selection"] == "primary", data
' || fail "roster --json is not the documented shape"
ok "roster --json exposes role, tier, runtime, model, and selection"

printf 'runtime test: ok\n'