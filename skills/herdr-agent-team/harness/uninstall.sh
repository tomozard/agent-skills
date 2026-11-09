#!/usr/bin/env bash

set -euo pipefail

MODE="remove"
FOUND=0

usage() {
  cat <<'EOF'
Usage: uninstall.sh [--dry-run|--check]

Remove the project-scaffold runtime and legacy full-sync artifacts.

  --dry-run  Print what would be removed without changing files.
  --check    Report installed artifacts and exit 1 when any are found.
EOF
}

case "${1:-}" in
  "") ;;
  --dry-run) MODE="dry-run" ;;
  --check) MODE="check" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

remove_path() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    FOUND=$((FOUND + 1))
    printf '  remove: %s\n' "$path"
    if [ "$MODE" = "remove" ]; then
      rm -rf "$path"
    fi
  fi
}

remove_manifest_entries() {
  local manifest="$1"
  local target_dir="$2"
  local entry

  if [ -f "$manifest" ]; then
    while IFS= read -r entry; do
      [ -n "$entry" ] && remove_path "$target_dir/$entry"
    done < "$manifest"
  fi
  remove_path "$manifest"
}

LEGACY_SKILLS=(
  agent-shared ap-requirement ap-slide ap-slide-review ap-user-manual
  ap-vault-audit ap-vault-sync ap-workflows-skills-mcps-install
  chrome-devtools-mcp cli-tool-spawn detect-cli-tools docs-gen
  find-idle-pane get-available-tools grill-me har-analyzer herdr
  herdr-commands herdr-communication herdr-office
  herdr-pane-best-practices herdr-pane-operations
  herdr-workspace-management orchestrator overview-normalizer pi-cli
  playwright-mcp-skill prd-normalizer research-team verify-pane-agent
  write-testcases-from-template
)

LEGACY_WORKFLOWS=(
  ap-broadcast ap-close-all-agents ap-close-workspace ap-context-finder
  ap-distill ap-docs-baseline ap-docs-full-cycle ap-docs-service
  ap-docs-sync-central ap-harness ap-overview ap-prd ap-qa-e2e ap-qa-plan
  ap-qa-scenario ap-qa-spec ap-qa-testcase ap-qa-workbook ap-recap
  ap-retrospec ap-shutdown ap-snapshot ap-townhall ap-user-manual
  ap-vault-audit ap-vault-sync
)

SKILL_TARGETS=(
  "$HOME/.gemini/antigravity/skills"
  "$HOME/.codex/skills"
  "$HOME/.codeium/windsurf/skills"
  "$HOME/.claude/skills"
  "$HOME/.config/opencode/skills"
  "$HOME/.agent/skills"
  "$HOME/.agents/skills"
  "$HOME/.qwen/skills"
  "$HOME/.kiro/skills"
)

WORKFLOW_TARGETS=(
  "$HOME/.gemini/antigravity/global_workflows"
  "$HOME/.codeium/windsurf/global_workflows"
  "$HOME/.claude/commands"
  "$HOME/.qwen/commands"
  "$HOME/.config/opencode/commands"
  "$HOME/.kiro/steering"
  "$HOME/.agents/workflows"
)

MCP_CONFIG_TARGETS=(
  "$HOME/.gemini/antigravity/mcp_config.json:mcpServers"
  "$HOME/.codeium/windsurf/mcp_config.json:mcpServers"
  "$HOME/.cursor/mcp.json:mcpServers"
  "$HOME/.claude.json:mcpServers"
  "$HOME/.gemini/settings.json:mcpServers"
  "$HOME/.config/opencode/opencode.json:mcp"
  "$HOME/.kiro/settings/mcp.json:mcpServers"
)

echo "Removing project-scaffold installation"

# Task Board history is workspace-owned durable state, not an installed runtime
# file. Never delete {workspaces_root}/.agents/task-board during uninstall.

# Current and previous minimal installers record every copied skill, binary,
# and Claude agent. Remove exactly those manifest-owned paths first.
remove_manifest_entries \
  "$HOME/.agents/project-scaffold-skills.txt" "$HOME/.agents/skills"
remove_manifest_entries \
  "$HOME/.agents/project-scaffold-minimal-skills.txt" "$HOME/.agents/skills"
remove_manifest_entries \
  "$HOME/.agents/project-scaffold-claude-skills.txt" "$HOME/.claude/skills"
remove_manifest_entries \
  "$HOME/.agents/project-scaffold-bin-files.txt" "$HOME/bin"
remove_manifest_entries \
  "$HOME/.agents/project-scaffold-claude-agents.txt" "$HOME/.claude/agents"
remove_manifest_entries \
  "$HOME/.agents/project-scaffold-pi-extensions.txt" "$HOME/.agents/extensions"
# Installed separately into Pi's global discovery path so `/hteam` exists in any
# Pi session; never the whole directory, which holds user extensions too.
remove_path "$HOME/.pi/agent/extensions/hteam.ts"
remove_manifest_entries \
  "$HOME/.agents/project-scaffold-voice-files.txt" "$HOME/.config/herdr"

# These paths have always been fully owned by the project-scaffold harness.
remove_path "$HOME/.agents/agents"
remove_path "$HOME/.agents/agents.md"
remove_path "$HOME/.agents/team.json"
remove_path "$HOME/.agents/protocols"
remove_path "$HOME/.agents/workflows"
remove_path "$HOME/.agents/guard-bin"

# Retired full-sync releases copied the catalog to several IDE-specific roots.
# The explicit historical inventory lets cleanup continue after the catalog was
# deleted from this minimal branch. Unrelated names in those roots are kept.
for target in "${SKILL_TARGETS[@]}"; do
  for skill in "${LEGACY_SKILLS[@]}"; do
    remove_path "$target/$skill"
  done
done

for target in "${WORKFLOW_TARGETS[@]}"; do
  for workflow in "${LEGACY_WORKFLOWS[@]}"; do
    remove_path "$target/$workflow.md"
    remove_path "$target/$workflow"
  done
done

for convention in backlog-location.md open-knowledge-format.md vault-location.md; do
  remove_path "$HOME/.agents/conventions/$convention"
done

# Full-sync MCP injection recorded the server keys it added. Remove only those
# keys from shared IDE configs; keep all other MCP configuration untouched.
MCP_STATE="$HOME/.agents/project-scaffold-mcp-servers.json"
if [ -f "$MCP_STATE" ]; then
  for entry in "${MCP_CONFIG_TARGETS[@]}"; do
    target="${entry%%:*}"
    key="${entry##*:}"
    [ -f "$target" ] || continue
    matches="$(python3 - "$target" "$key" "$MCP_STATE" <<'PY'
import json
import sys

target, key, state = sys.argv[1:]
try:
    data = json.load(open(target))
    names = json.load(open(state))
except (OSError, json.JSONDecodeError):
    raise SystemExit(0)
bucket = data.get(key)
if isinstance(bucket, dict) and isinstance(names, list):
    print("\n".join(name for name in names if name in bucket))
PY
)"
    if [ -n "$matches" ]; then
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        FOUND=$((FOUND + 1))
        printf '  remove MCP key: %s:%s.%s\n' "$target" "$key" "$name"
      done <<< "$matches"
      if [ "$MODE" = "remove" ]; then
        python3 - "$target" "$key" "$MCP_STATE" <<'PY'
import json
import sys

target, key, state = sys.argv[1:]
with open(target) as handle:
    data = json.load(handle)
with open(state) as handle:
    names = json.load(handle)
bucket = data.get(key)
if isinstance(bucket, dict) and isinstance(names, list):
    for name in names:
        bucket.pop(name, None)
    if not bucket:
        data.pop(key, None)
with open(target, "w") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
      fi
    fi
  done
fi

remove_path "$HOME/.agents/mcp.json"
remove_path "$MCP_STATE"

if [ "$MODE" = "check" ]; then
  if [ "$FOUND" -gt 0 ]; then
    echo "check: found $FOUND installed artifact(s)" >&2
    exit 1
  fi
  echo "check: no project-scaffold artifacts found"
elif [ "$MODE" = "dry-run" ]; then
  echo "Dry run complete: $FOUND artifact(s) would be removed"
else
  echo "Uninstall complete: $FOUND artifact(s) removed"
fi
