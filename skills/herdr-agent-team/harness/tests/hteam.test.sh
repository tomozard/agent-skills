#!/usr/bin/env bash
# Offline tests for bin/herdr-app-team (the `hteam` launcher) and the `/hteam`
# Pi extension it is exposed through. Both app binaries are stubbed, so this
# touches no live Herdr space and starts no model.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HTEAM="$ROOT/bin/herdr-app-team"
EXT="$ROOT/.agents/extensions/hteam.ts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "hteam test: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; }

bash -n "$HTEAM" || fail "bash syntax failed"
[ -x "$HTEAM" ] || fail "herdr-app-team is not executable"
[ -r "$EXT" ] || fail "the /hteam Pi extension is missing"
# `node --check` rejects `import type` on some node builds (v26.11.1 fails, v26.3.0
# passes), so the install would depend on which node is first in PATH. Fall back
# to importing the module, which parses the whole file through the type stripper.
if command -v node >/dev/null 2>&1; then
  node --check "$EXT" >/dev/null 2>&1 \
    || node --experimental-strip-types -e "import('file://$EXT')" >/dev/null 2>&1 \
    || fail "hteam.ts does not parse"
fi
grep -q 'registerCommand("hteam"' "$EXT" || fail "hteam.ts does not register the hteam command"
ok "extension parses and registers /hteam"

# --- fixtures -------------------------------------------------------------
mkdir -p "$TMP/work" "$TMP/vault"
cat > "$TMP/registry.yaml" <<'YAML'
projects:
  demo-app:
    name: demo-app
    path: /tmp/demo-app
YAML
: > "$TMP/vault/log.md"

cat > "$TMP/app" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1" in
  status) printf '{"ok":true}' ;;
  ls) printf '{"spaces":[]}' ;;
  do)
    case "$2" in
      space.new) printf '{"space":"sp1","tab":"tb1","terminal":"t10"}' ;;
      tab.new)   printf '{"tab":"tb1","terminal":"t11"}' ;;
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
  ls) printf '{"terminals":[]}' ;;
  *) printf '{}' ;;
esac
STUB
chmod +x "$TMP/app" "$TMP/hc"

steam() {
  STUB_LOG="$TMP/calls.log" \
    PATH="$ROOT/bin:$PATH" \
    HERDR_APP_BIN="$TMP/app" HC_BIN="$TMP/hc" \
    HERDR_TEAM_REPO="$ROOT" HERDR_TEAM_REGISTRY="$TMP/registry.yaml" \
    HERDR_TEAM_VAULT="$TMP/vault" HERDR_TEAM_ACTIVITY_LOG="$TMP/vault/log.md" \
    HERDR_TEAM_CWD="$TMP/work" \
    HERDR_TEAM_CONFIG="${HERDR_TEAM_CONFIG:-$TMP/no-config.yaml}" \
    bash "$HTEAM" "$@"
}

# --- 1. --voice only accepts on|off ---------------------------------------
if steam --voice maybe >"$TMP/out" 2>"$TMP/err"; then
  fail "--voice maybe was accepted"
fi
grep -q "voice must be on or off" "$TMP/err" || fail "bad --voice value was not explained"
ok "--voice rejects anything but on|off"

# --- 2. voice=on reaches the Orchestrator terminal env --------------------
: > "$TMP/calls.log"
steam --voice on --watch off >"$TMP/out" 2>"$TMP/err" || fail "start with --voice on failed: $(cat "$TMP/err")"
grep -q "HERDR_VOICE_MODE=on" "$TMP/calls.log" \
  || fail "the Orchestrator argv does not carry HERDR_VOICE_MODE=on: $(head -2 "$TMP/calls.log")"
grep -q "role.*orchestrator\|--role orchestrator" "$TMP/calls.log" || fail "the Orchestrator role was not launched"
ok "voice=on is passed into the Orchestrator argv"

# --- 3. default stays off --------------------------------------------------
: > "$TMP/calls.log"
steam >"$TMP/out" 2>"$TMP/err" || fail "default start failed: $(cat "$TMP/err")"
grep -q "HERDR_VOICE_MODE=off" "$TMP/calls.log" || fail "default is not voice=off"
grep -q "ClickUp intake watcher off" "$TMP/out" || fail "the watcher is not off by default: $(cat "$TMP/out")"
ok "voice defaults to off"

# --- 4. check reports the effective voice mode -----------------------------
OUT="$(steam check --voice on 2>&1)" || fail "check --voice on failed: $OUT"
printf '%s' "$OUT" | grep -q "voice: on" || fail "check did not report voice: on: $OUT"
ok "check reports voice: on"

# --- 5. the per-machine config file drives the launcher -------------------
CONFIG="$TMP/hteam.yaml"
if ! HERDR_TEAM_CONFIG="$CONFIG" "$ROOT/bin/hteam-config" set space "Config Space" folder "$TMP/work" voice on watch off >/dev/null; then
  fail "hteam-config set failed"
fi
grep -q '^space: Config Space$' "$CONFIG" || fail "hteam-config did not write the space key"

OUT="$(HERDR_TEAM_CONFIG="$CONFIG" steam check 2>&1)" || fail "check with a config file failed: $OUT"
printf '%s' "$OUT" | grep -q "space target: Config Space" || fail "the launcher ignored the config space: $OUT"
printf '%s' "$OUT" | grep -q "voice: on" || fail "the launcher ignored the config voice: $OUT"
ok "config file drives space and voice"

# --- 6. env beats the file, the flag beats both ---------------------------
OUT="$(HERDR_TEAM_CONFIG="$CONFIG" HERDR_TEAM_SPACE="Env Space" steam check 2>&1)" \
  || fail "check with an env override failed: $OUT"
printf '%s' "$OUT" | grep -q "space target: Env Space" || fail "env did not win over the config file: $OUT"
OUT="$(HERDR_TEAM_CONFIG="$CONFIG" HERDR_TEAM_SPACE="Env Space" steam check --space "Flag Space" 2>&1)" \
  || fail "check with a flag override failed: $OUT"
printf '%s' "$OUT" | grep -q "space target: Flag Space" || fail "the flag did not win over env and file: $OUT"
ok "precedence is flag > env > file > default"

# --- 7. an invalid config value is refused --------------------------------
printf 'voice: loud\n' > "$CONFIG"
if HERDR_TEAM_CONFIG="$CONFIG" steam check >"$TMP/out" 2>"$TMP/err"; then
  fail "an invalid config value was accepted"
fi
grep -q "invalid launcher config" "$TMP/err" || fail "invalid config was refused without the reason: $(cat "$TMP/err")"
ok "invalid config value is refused"

# --- 8. --watch mirrors --voice: on|off only, default off ------------------
if steam --watch maybe >"$TMP/out" 2>"$TMP/err"; then
  fail "--watch maybe was accepted"
fi
grep -q "watch must be on or off" "$TMP/err" || fail "bad --watch value was not explained: $(cat "$TMP/err")"
OUT="$(steam check 2>&1)" || fail "check failed: $OUT"
printf '%s' "$OUT" | grep -q "watch: off" || fail "check does not report watch: off by default: $OUT"
OUT="$(steam check --watch on 2>&1)" || fail "check --watch on failed: $OUT"
printf '%s' "$OUT" | grep -q "watch: on" || fail "check does not report watch: on: $OUT"
OUT="$(steam check --no-watch 2>&1)" || fail "the legacy --no-watch alias was refused: $OUT"
printf '%s' "$OUT" | grep -q "watch: off" || fail "--no-watch is not an alias for --watch off: $OUT"
ok "--watch accepts on|off, defaults off, --no-watch still works"

echo "hteam test: ok"