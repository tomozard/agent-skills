#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$ROOT/.agents"

usage() {
  cat <<'EOF'
Usage: setup_harness.sh [--check]

Without arguments, validate and install the minimal Herdr agent-team runtime.
--check validates the repository without writing global runtime paths.
EOF
}

case "${1:-}" in
  "") ;;
  --check) exec "$ROOT/tests/validate.sh" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

# workflow-shape and task-board are shims over the agent-skills skill, which is
# the single source for that tooling. Fail early with the install command rather
# than half-installing a harness whose tests cannot run.
SKILL_SCRIPTS="${HERDR_AGENT_TEAM_SCRIPTS:-$HOME/.agents/skills/herdr-agent-team/scripts}"
if [ ! -x "$SKILL_SCRIPTS/workflow-shape" ] || [ ! -x "$SKILL_SCRIPTS/task-board" ]; then
  cat >&2 <<'MSG'
setup_harness: the agent-skills tooling is missing
  bin/workflow-shape and bin/task-board are thin shims over
  ~/.agents/skills/herdr-agent-team/scripts — one source, no second copy.
  Install it first, then re-run:

    npx skills add tomozard/agent-skills/skills/herdr-agent-team

MSG
  exit 1
fi

# PyYAML lives in the user site-packages, which is per-HOME: a fresh macOS user
# account has none, and tests/clickup-watch.test.sh then fails with a message
# that does not name the cause. Check it here, before validate.sh runs.
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  cat >&2 <<'MSG'
setup_harness: PyYAML is missing (clickup-watch and its tests need it)
  Install it for the current user, then re-run:

    python3 -m pip install --user pyyaml

MSG
  exit 1
fi

# validate.sh assumes $ROOT is the root of its own git repository: one of its
# checks starts a role with --cwd "$ROOT", and agent-runtime refuses a writer
# inside a repository it cannot see the root of. When the payload ships inside
# another repository (the agent-skills skill), validate a pristine copy instead.
run_validate() {
  local top tmp rc
  top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ "$top" = "$ROOT" ]; then
    "$ROOT/tests/validate.sh"
    return
  fi
  tmp="$(mktemp -d)"
  cp -R "$ROOT/." "$tmp/"
  (
    cd "$tmp" || exit 1
    git init -q .
    git add -A
    git -c user.email=validate@local -c user.name=validate commit -qm "harness payload"
    # agent-runtime refuses a writer on main/master, and `git init` now defaults
    # to main, so validate on a non-protected branch.
    git checkout -q -b feat/harness-payload
    ./tests/validate.sh
  )
  rc=$?
  rm -rf "$tmp"
  return $rc
}

run_validate

copy_file() {
  local source="$1" destination="$2"
  mkdir -p "$(dirname "$destination")"
  rm -f "$destination"
  cp -fL "$source" "$destination"
}

copy_dir() {
  local source="$1" destination="$2"
  rm -rf "$destination"
  mkdir -p "$(dirname "$destination")"
  cp -RL "$source" "$destination"
}

echo "Installing minimal Herdr agent-team runtime"

mkdir -p "$HOME/.agents/skills"
SKILL_MANIFEST="$HOME/.agents/project-scaffold-skills.txt"
for old_manifest in \
  "$HOME/.agents/project-scaffold-minimal-skills.txt" \
  "$SKILL_MANIFEST"; do
  if [ -f "$old_manifest" ]; then
    while IFS= read -r skill; do
      [ -n "$skill" ] && rm -rf "$HOME/.agents/skills/$skill"
    done < "$old_manifest"
    [ "$old_manifest" = "$SKILL_MANIFEST" ] || rm -f "$old_manifest"
  fi
done
: > "$SKILL_MANIFEST"

for skill in herdr agent-team agent-shared; do
  copy_dir "$SOURCE/skills/$skill" "$HOME/.agents/skills/$skill"
  echo "$skill" >> "$SKILL_MANIFEST"
  echo "  skill: $skill"
done

CLAUDE_SKILL_DIR="$HOME/.claude/skills"
CLAUDE_SKILL_MANIFEST="$HOME/.agents/project-scaffold-claude-skills.txt"
mkdir -p "$CLAUDE_SKILL_DIR"
if [ -f "$CLAUDE_SKILL_MANIFEST" ]; then
  while IFS= read -r skill; do
    [ -n "$skill" ] && rm -rf "$CLAUDE_SKILL_DIR/$skill"
  done < "$CLAUDE_SKILL_MANIFEST"
fi
: > "$CLAUDE_SKILL_MANIFEST"
for skill in herdr agent-team agent-shared; do
  copy_dir "$SOURCE/skills/$skill" "$CLAUDE_SKILL_DIR/$skill"
  echo "$skill" >> "$CLAUDE_SKILL_MANIFEST"
  echo "  Claude skill: $skill"
done

rm -rf "$HOME/.agents/agents"
mkdir -p "$HOME/.agents/agents"
for role_file in "$SOURCE/agents"/*.md; do
  copy_file "$role_file" "$HOME/.agents/agents/$(basename "$role_file")"
done
# Canonical team.json lives with the skill. Prefer a working clone of agent-skills
# (edits land in the repo); fall back to the installed skill, which is all a
# machine without the clone has.
CANON_TEAM="${HERDR_TEAM_CANONICAL:-}"
if [ -z "$CANON_TEAM" ]; then
  for candidate in \
    "$HOME/Workspaces/agent-skills/skills/herdr-agent-team/config/team.json" \
    "$HOME/.agents/skills/herdr-agent-team/config/team.json"; do
    [ -f "$candidate" ] && { CANON_TEAM="$candidate"; break; }
  done
fi
if [ -n "$CANON_TEAM" ] && [ -f "$CANON_TEAM" ]; then
  ln -sfn "$CANON_TEAM" "$HOME/.agents/team.json"
else
  copy_file "$SOURCE/team.json" "$HOME/.agents/team.json"
fi
copy_file "$ROOT/AGENTS.md" "$HOME/.agents/agents.md"
copy_dir "$ROOT/bin/guard-bin" "$HOME/.agents/guard-bin"
chmod +x "$HOME/.agents/guard-bin/git" "$HOME/.agents/guard-bin/gh" \
  "$HOME/.agents/guard-bin/glab"

VOICE_CONFIG_DIR="$HOME/.config/herdr"
VOICE_MANIFEST="$HOME/.agents/project-scaffold-voice-files.txt"
mkdir -p "$VOICE_CONFIG_DIR"
if [ -f "$VOICE_MANIFEST" ]; then
  while IFS= read -r voice_file; do
    [ -n "$voice_file" ] && rm -f "$VOICE_CONFIG_DIR/$voice_file"
  done < "$VOICE_MANIFEST"
fi
: > "$VOICE_MANIFEST"
copy_file "$ROOT/bin/tts-thai.sh" "$VOICE_CONFIG_DIR/tts-thai.sh"
chmod +x "$VOICE_CONFIG_DIR/tts-thai.sh"
echo "  voice: $VOICE_CONFIG_DIR/tts-thai.sh"
echo "tts-thai.sh" >> "$VOICE_MANIFEST"
if [ -x "$VOICE_CONFIG_DIR/tts-venv/bin/gtts-cli" ] \
  || [ -x "$HOME/.codex/tts-venv/bin/gtts-cli" ] \
  || [ -x "$HOME/.config/opencode/tts-venv/bin/gtts-cli" ] \
  || command -v gtts-cli >/dev/null 2>&1; then
  echo "  voice: gTTS available"
else
  echo "  warning: gTTS is not installed; voice output stays silent (needs network plus gtts-cli)" >&2
fi

PI_EXTENSION_DIR="$HOME/.agents/extensions"
PI_EXTENSION_MANIFEST="$HOME/.agents/project-scaffold-pi-extensions.txt"
mkdir -p "$PI_EXTENSION_DIR"
if [ -f "$PI_EXTENSION_MANIFEST" ]; then
  while IFS= read -r extension; do
    [ -z "$extension" ] && continue
    rm -f "$PI_EXTENSION_DIR/$extension"
    # /hteam is also installed into Pi's global auto-discovery directory.
    [ "$extension" = "hteam.ts" ] && rm -f "$HOME/.pi/agent/extensions/hteam.ts"
  done < "$PI_EXTENSION_MANIFEST"
fi
: > "$PI_EXTENSION_MANIFEST"
for extension_file in "$SOURCE/extensions"/*.ts; do
  [ -e "$extension_file" ] || continue
  extension="$(basename "$extension_file")"
  copy_file "$extension_file" "$PI_EXTENSION_DIR/$extension"
  echo "$extension" >> "$PI_EXTENSION_MANIFEST"
done

# agent-runtime loads the role extensions per pane with --extension. The `/hteam`
# command must exist in a plain Pi session as well, so it also goes to Pi's global
# auto-discovery directory (~/.pi/agent/extensions/*.ts).
if [ -f "$PI_EXTENSION_DIR/hteam.ts" ]; then
  mkdir -p "$HOME/.pi/agent/extensions"
  copy_file "$PI_EXTENSION_DIR/hteam.ts" "$HOME/.pi/agent/extensions/hteam.ts"
  echo "  pi command: /hteam -> $HOME/.pi/agent/extensions/hteam.ts"
fi

rm -rf "$HOME/.agents/protocols"
mkdir -p "$HOME/.agents/protocols"
copy_file "$SOURCE/protocols/communication.md" "$HOME/.agents/protocols/communication.md"

# This runtime has no legacy slash-workflow catalog. Pi extensions are managed
# separately above because they are part of the runtime adapter.
rm -rf "$HOME/.agents/workflows"

CLAUDE_AGENT_DIR="$HOME/.claude/agents"
CLAUDE_MANIFEST="$HOME/.agents/project-scaffold-claude-agents.txt"
mkdir -p "$CLAUDE_AGENT_DIR"
if [ -f "$CLAUDE_MANIFEST" ]; then
  while IFS= read -r agent_file; do
    [ -n "$agent_file" ] && rm -f "$CLAUDE_AGENT_DIR/$agent_file"
  done < "$CLAUDE_MANIFEST"
fi
: > "$CLAUDE_MANIFEST"
for role_file in "$SOURCE/agents"/*.md; do
  role="$(basename "$role_file" .md)"
  target="herdr-$role.md"
  copy_file "$role_file" "$CLAUDE_AGENT_DIR/$target"
  echo "$target" >> "$CLAUDE_MANIFEST"
done

mkdir -p "$HOME/bin"
BIN_MANIFEST="$HOME/.agents/project-scaffold-bin-files.txt"
if [ -f "$BIN_MANIFEST" ]; then
  while IFS= read -r binary; do
    [ -n "$binary" ] && rm -f "$HOME/bin/$binary"
  done < "$BIN_MANIFEST"
fi
: > "$BIN_MANIFEST"
for binary in herdr-team agent-runtime spawn-agent verify-pane-agent agent-team-shutdown validate-okf voice-notify task-board workflow-shape herdr-app-team herdr-app-spawn-role hteam-dispatch hteam-config tts-speak-omni clickup-watch; do
  copy_file "$ROOT/bin/$binary" "$HOME/bin/$binary"
  chmod +x "$HOME/bin/$binary"
  echo "$binary" >> "$BIN_MANIFEST"
  echo "  binary: $binary"
done
ln -sfn herdr-app-team "$HOME/bin/hteam"
echo "  alias: hteam -> herdr-app-team"
if command -v herdr >/dev/null 2>&1; then
  echo "  runtime: $(herdr --version 2>/dev/null || echo 'herdr detected')"
else
  echo "  warning: herdr is not installed" >&2
fi

if [ -x "$HOME/.local/bin/herdr-app" ] && [ -x "$HOME/.local/bin/herdr-core" ]; then
  echo "  app runtime: herdr-app + herdr-core present (hteam)"
else
  echo "  warning: Herdr desktop app runtime missing — 'hteam' needs Herdr.app + herdr-core" >&2
fi

if command -v pi >/dev/null 2>&1 && pi --version >/dev/null 2>&1; then
  echo "  runtime: Pi healthy"
else
  echo "  warning: Pi missing or unhealthy; runtime=auto will try Claude" >&2
fi

if command -v claude >/dev/null 2>&1 && claude --version >/dev/null 2>&1; then
  echo "  runtime: Claude healthy"
else
  echo "  warning: Claude missing or unhealthy" >&2
fi

echo "Installation complete"
