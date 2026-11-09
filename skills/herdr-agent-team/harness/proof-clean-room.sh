#!/usr/bin/env bash
# Clean-room proof for the Herdr agent-team install.
#
# Both modes start from a HOME with nothing installed. They differ in whether the
# real HOME is touched:
#
#   (default)      isolated: throwaway HOME under scratch — nothing to lose
#   --real         destructive: uninstall from the real HOME first, then reinstall
#
# --source picks the install channel under test:
#
#   harness (default)  skills.sh for the policy layer + setup_harness.sh for the runtime
#   skills             skills.sh only — expected to FAIL, proving the runtime needs the harness
#
# Usage:
#   ./proof-clean-room.sh                      # isolated, full channel
#   ./proof-clean-room.sh --source skills      # isolated, proves skills.sh alone is not enough
#   ./proof-clean-room.sh --real               # wipe and reinstall on this machine
#   ./proof-clean-room.sh --real --keep        # wipe for real and stop (machine left bare)
#
# Log: /tmp/proof-clean-room-<ts>.log

set -uo pipefail

MODE="isolated"
SOURCE="harness"
KEEP_BARE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --real) MODE="real" ;;
    --isolated) MODE="isolated" ;;
    --source) SOURCE="${2:-}"; shift ;;
    --keep) KEEP_BARE=1 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$SOURCE" in harness|skills) ;; *) echo "--source must be harness or skills" >&2; exit 2 ;; esac

TS="$(date +%Y%m%d-%H%M%S)"
LOG="/tmp/proof-clean-room-$TS.log"
SCRATCH="${HOME}/.hermes/cache/scratch/proof-$TS"
HARNESS_SRC="${HOME}/Workspaces/project-scaffold"
SKILLS_SRC="${HOME}/Workspaces/agent-skills"
FAIL=0

step() { printf '\n=== %s ===\n' "$*"; }
ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }
want_fail() { if "$@" >>"$LOG" 2>&1; then bad "expected failure but succeeded: $*"; else ok "expected failure: $*"; fi; }
want_ok()   { if "$@" >>"$LOG" 2>&1; then ok "$*"; else bad "expected success but failed: $*"; fi; }
exec > >(tee -a "$LOG") 2>&1
printf 'mode=%s source=%s\n' "$MODE" "$SOURCE"

# ------------------------------------------------------------- target HOME
if [ "$MODE" = "real" ]; then
  TARGET_HOME="$HOME"
else
  TARGET_HOME="$SCRATCH/home"
  mkdir -p "$TARGET_HOME"
  printf 'isolated HOME: %s\n' "$TARGET_HOME"
fi
in_target() {
  if [ "$MODE" = "real" ]; then
    "$@"
  elif [ -n "${PY_SHIM:-}" ]; then
    env HOME="$TARGET_HOME" PYTHONPATH="$PY_SHIM" "$@"
  else
    env HOME="$TARGET_HOME" "$@"
  fi
}

# PyYAML is pip --user, i.e. per-HOME. A fresh macOS account has none, and
# validate.sh then dies at "clickup-watch tests failed" without naming the cause.
# The isolated HOME inherits this machine's user site-packages so the rehearsal
# tests the install logic; the prerequisite is reported, not hidden.
PY_SHIM=""
if [ "$MODE" = "isolated" ] && ! env HOME="$TARGET_HOME" python3 -c 'import yaml' >/dev/null 2>&1; then
  PY_SHIM="$(python3 -m site --user-site)"
  printf 'note: PyYAML is per-HOME and absent in the isolated HOME\n'
  printf '      shimming PYTHONPATH=%s\n' "$PY_SHIM"
  printf '      a real new macOS user must run: python3 -m pip install --user pyyaml\n'
fi

step "prerequisites in the target HOME"
for probe in "python3:command -v python3" "pyyaml:python3 -c 'import yaml'" \
             "herdr:command -v herdr" "pi:command -v pi" "claude:command -v claude"; do
  name="${probe%%:*}"; cmd="${probe#*:}"
  if in_target sh -c "$cmd" >/dev/null 2>&1; then ok "present: $name"; else bad "missing: $name"; fi
done

# ------------------------------------------- 1. bare the target (real only)
if [ "$MODE" = "real" ]; then
  step "1. backup + uninstall from the real machine"
  BK="$HOME/.agents-backup-$TS"
  mkdir -p "$BK"
  for p in "$HOME/.agents/agents" "$HOME/.agents/agents.md" "$HOME/.agents/protocols" \
           "$HOME/.agents/guard-bin" "$HOME/.agents/extensions" "$HOME/.agents/team.json" \
           "$HOME/.claude/agents" "$HOME/.claude/skills" "$HOME/bin" \
           "$HOME/.config/herdr/tts-thai.sh"; do
    [ -e "$p" ] && cp -RL "$p" "$BK/$(echo "$p" | sed "s|$HOME/||; s|/|_|g")"
  done
  printf 'backup: %s\n' "$BK"

  # uninstall.sh does not manage the skill layer — remove it explicitly.
  want_ok npx --yes skills remove herdr-agent-team hteam -g -y
  rm -f "$HOME/.hermes/skills/herdr-agent-team" "$HOME/.hermes/skills/hteam"

  # The installer must refuse before the harness goes, otherwise the gate is untested.
  want_fail "$HARNESS_SRC/setup_harness.sh"
  grep -q "agent-skills tooling is missing" "$LOG" \
    && ok "installer refused with its gate message" \
    || bad "installer did not print the gate message"

  want_ok "$HARNESS_SRC/uninstall.sh"
  want_ok "$HARNESS_SRC/uninstall.sh" --check

  step "2. verify the machine is bare"
  for cmd in hteam herdr-app-team agent-runtime spawn-agent task-board workflow-shape clickup-watch; do
    command -v "$cmd" >/dev/null && bad "$cmd still on PATH ($(command -v "$cmd"))" || ok "$cmd gone"
  done
  for p in "$HOME/.agents/team.json" "$HOME/.agents/agents" "$HOME/.agents/agents.md" \
           "$HOME/.agents/guard-bin" "$HOME/.agents/protocols" "$HOME/.agents/extensions/role-guard.ts" \
           "$HOME/.pi/agent/extensions/hteam.ts" "$HOME/.claude/agents/herdr-pm.md" \
           "$HOME/.config/herdr/tts-thai.sh"; do
    [ -e "$p" ] && bad "still present: $p" || ok "gone: $p"
  done

  if [ "$KEEP_BARE" = 1 ]; then
    step "stopped (--keep): machine left bare, backup at $BK"
    exit "$FAIL"
  fi
fi

# ----------------------------------------------- 3. skill layer via skills.sh
step "3. install the skill layer with skills.sh"
want_ok in_target npx --yes skills add tomozard/agent-skills/skills/herdr-agent-team -g -a '*'
want_ok in_target npx --yes skills add tomozard/agent-skills/skills/hteam -g -a '*'
[ -f "$TARGET_HOME/.agents/skills/herdr-agent-team/SKILL.md" ] \
  && ok "skill installed: ${TARGET_HOME#$HOME/}/.agents/skills/herdr-agent-team" \
  || bad "skill not installed"
for s in workflow-shape task-board roster runtime-probe; do
  [ -x "$TARGET_HOME/.agents/skills/herdr-agent-team/scripts/$s" ] \
    && ok "script executable: $s" \
    || bad "script missing or not executable: $s"
done

step "4. what skills.sh does NOT deliver"
if [ "$MODE" = "real" ]; then
  # ~/bin and ~/.agents/extensions exist as directories in a real HOME even after
  # a clean uninstall (only manifest files are removed), so presence proves nothing.
  printf 'skipped in --real: empty ~/bin and ~/.agents/extensions still exist as directories\n'
else
  [ -d "$TARGET_HOME/bin" ] && bad "unexpected ~/bin from skills.sh" || ok "no ~/bin (no launcher)"
  [ -e "$TARGET_HOME/.agents/extensions" ] && bad "unexpected extensions" || ok "no guard/voice extensions"
fi
[ -d "$TARGET_HOME/.agents/agents" ] && bad "unexpected role prompts" || ok "no ~/.agents/agents (role prompts not installed)"
[ -e "$TARGET_HOME/.agents/agents.md" ] && bad "unexpected AGENTS.md" || ok "no ~/.agents/agents.md"

if [ "$SOURCE" = "skills" ]; then
  step "verdict"
  if [ -x "$TARGET_HOME/bin/hteam" ]; then
    bad "hteam exists anyway — skills.sh IS sufficient"
  else
    ok "hteam does not exist: skills.sh alone cannot install the team"
  fi
  printf '\nskills.sh ships policy + scripts: SKILL.md, references/, scripts/, config/, examples/.\n'
  printf 'The launcher, role prompts, guards and voice live in the harness repo bin/ and .agents/.\n'
  printf 'FAILURES: %s\nlog: %s\n' "$FAIL" "$LOG"
  exit "$FAIL"
fi

# ---------------------------------------------------- 5. runtime via harness
step "5. install the runtime with setup_harness.sh"
want_ok in_target "$HARNESS_SRC/setup_harness.sh"

step "6. verify the install is complete"
in_target "$HARNESS_SRC/uninstall.sh" --check >/dev/null 2>&1 \
  && bad "uninstall --check found nothing (install did not land)" \
  || ok "uninstall --check sees the installed artifacts"
for p in "$TARGET_HOME/bin/hteam" "$TARGET_HOME/bin/agent-runtime" "$TARGET_HOME/bin/workflow-shape" \
         "$TARGET_HOME/.agents/agents/pm.md" "$TARGET_HOME/.agents/agents.md" \
         "$TARGET_HOME/.agents/extensions/role-guard.ts" "$TARGET_HOME/.config/herdr/tts-thai.sh"; do
  [ -e "$p" ] && ok "present: ${p#$TARGET_HOME/}" || bad "missing: ${p#$TARGET_HOME/}"
done
if [ -L "$TARGET_HOME/.agents/team.json" ]; then
  ok "team.json symlink -> $(readlink "$TARGET_HOME/.agents/team.json")"
elif [ -f "$TARGET_HOME/.agents/team.json" ]; then
  ok "team.json copied (canonical repo absent under this HOME — expected in isolated mode)"
else
  bad "team.json missing"
fi

step "7. suites (repo tests, offline)"
want_ok bash "$HARNESS_SRC/tests/hteam.test.sh"
want_ok bash "$HARNESS_SRC/tests/workflow-shape.test.sh"
want_ok bash "$HARNESS_SRC/tests/task-board.test.sh"

step "8. resolver + roster on a real intake"
"$TARGET_HOME/bin/workflow-shape" \
  --intake "$SKILLS_SRC/skills/herdr-agent-team/examples/intake.json" \
  --team "$SKILLS_SRC/skills/herdr-agent-team/config/team.json" --format text \
  || bad "workflow-shape failed"
"$SKILLS_SRC/skills/herdr-agent-team/scripts/roster" coder critical || bad "roster failed"
"$SKILLS_SRC/skills/herdr-agent-team/scripts/runtime-probe" || bad "runtime-probe failed"

step "9. app reachability (needs Herdr.app open)"
if [ "$MODE" = "real" ]; then
  want_ok "$TARGET_HOME/bin/hteam" check
else
  printf 'skipped: isolated HOME has no Herdr app session\n'
fi

step "done"
printf 'FAILURES: %s\nlog: %s\n' "$FAIL" "$LOG"
printf 'next: run one real task through the team (hteam -> PM intake -> coder -> verifier -> commit gate)\n'
exit "$FAIL"
