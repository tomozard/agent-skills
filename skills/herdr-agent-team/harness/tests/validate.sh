#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Ensure test harness runs in clean environment
unset HERDR_TEAM_RUNTIME HERDR_TEAM_MODEL HERDR_TEAM_CWD HERDR_TEAM_REGISTRY \
  HERDR_TEAM_VAULT_PATH HERDR_TEAM_ACTIVITY_LOG HERDR_TEAM_SESSION HERDR_TEAM_VOICE \
  HERDR_ROLE HERDR_ENV HERDR_PANE_ID HERDR_VOICE

REAL_GIT="$(command -v git)"
[ -x /usr/bin/git ] && REAL_GIT=/usr/bin/git

fail() {
  echo "validate: $*" >&2
  exit 1
}

# Reviewer and Tester carry shipped alternates for the writer/verifier
# independence rule. Routing-exception and disabled-primary failover behavior is
# exercised with these additional test-only alternates.
add_test_alternates() {
  python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
team = json.loads(path.read_text())
for role, tier, runtime, model in (
    ("coder", "standard", "pi", "opencode-go/step-5-preview"),
    ("supervisor", "standard", "claude", "sonnet"),
):
    config = team["roles"][role]
    allowlist = config["models"].setdefault(runtime, [])
    if model not in allowlist:
        allowlist.append(model)
    alternates = config["routing"][tier]["alternates"]
    if {"runtime": runtime, "model": model} not in alternates:
        alternates.append({"runtime": runtime, "model": model})
path.write_text(json.dumps(team, indent=2) + "\n")
PY
}

for script in setup_harness.sh uninstall.sh bin/herdr-team bin/agent-runtime \
  bin/spawn-agent bin/verify-pane-agent bin/agent-team-shutdown bin/validate-okf \
  bin/voice-notify bin/tts-thai.sh bin/guard-bin/git bin/guard-bin/gh \
  bin/guard-bin/glab \
  .agents/skills/agent-shared/lib/agent-helpers.sh; do
  [ -f "$script" ] || fail "missing $script"
  bash -n "$script" || fail "shell syntax failed: $script"
done

# task-board and workflow-shape are thin shims: the implementation is the
# agent-skills skill, so the behaviour assertions below run against it.
TASK_BOARD_SRC="${HERDR_AGENT_TEAM_SCRIPTS:-$HOME/.agents/skills/herdr-agent-team/scripts}/task-board"
WORKFLOW_SHAPE_SRC="${HERDR_AGENT_TEAM_SCRIPTS:-$HOME/.agents/skills/herdr-agent-team/scripts}/workflow-shape"

[ -x bin/task-board ] || fail "task-board CLI is not executable"
[ -x bin/workflow-shape ] || fail "workflow-shape resolver is not executable"
bash -n bin/workflow-shape || fail "workflow-shape shim syntax failed"
[ -x "$WORKFLOW_SHAPE_SRC" ] || fail "workflow-shape: install agent-skills (npx skills add tomozard/agent-skills/skills/herdr-agent-team)"
python3 -m py_compile "$WORKFLOW_SHAPE_SRC" || fail "workflow-shape Python syntax failed"
[ -x tests/task-board.test.sh ] || fail "task-board tests are not executable"
[ -x tests/micro-verification.test.sh ] || fail "micro verification tests are not executable"
[ -x tests/workflow-shape.test.sh ] || fail "workflow shape tests are not executable"
[ -x tests/clickup-watch.test.sh ] || fail "ClickUp watcher tests are not executable"
[ -x tests/herdr-app-spawn-role.test.sh ] || fail "herdr-app-spawn-role tests are not executable"
[ -x tests/hteam.test.sh ] || fail "hteam tests are not executable"
[ -x bin/hteam-dispatch ] || fail "hteam-dispatch is not executable"
python3 -m py_compile bin/hteam-dispatch || fail "hteam-dispatch Python syntax failed"
grep -q 'does not staff' bin/hteam-dispatch || fail "hteam-dispatch does not gate unstaffed roles"
[ -x tests/hteam-dispatch.test.sh ] || fail "hteam-dispatch tests are not executable"
[ -x bin/hteam-config ] || fail "hteam-config CLI is not executable"
python3 -m py_compile bin/hteam-config || fail "hteam-config Python syntax failed"
[ -x bin/clickup-watch ] || fail "clickup-watch CLI is not executable"
python3 -m py_compile bin/clickup-watch || fail "clickup-watch Python syntax failed"
grep -q 'pre-authorizes nothing' bin/clickup-watch \
  || fail "the intake brief must withhold all authority"
grep -q 'pm-{runtime_slug' bin/clickup-watch \
  || fail "clickup-watch must map projects to the runtime PM tab label"
bash -n bin/task-board || fail "task-board shim syntax failed"
[ -x "$TASK_BOARD_SRC" ] || fail "task-board: install agent-skills (npx skills add tomozard/agent-skills/skills/herdr-agent-team)"
python3 -m py_compile "$TASK_BOARD_SRC" || fail "task-board Python syntax failed"
grep -q 'git.*rev-parse.*show-toplevel' "$TASK_BOARD_SRC" \
  || fail "task-board does not guard the full Git worktree"
grep -q 'HERDR_PROJECT=' bin/spawn-agent \
  || fail "spawn-agent does not propagate project context"
grep -q '_agent_task_board_event.*DONE' .agents/skills/agent-shared/lib/agent-helpers.sh \
  || fail "helper does not append Task Board events"
grep -q 'revision limit exceeded' "$TASK_BOARD_SRC" \
  || fail "task-board does not enforce the revision ceiling"
grep -q 'in_progress.*complete' "$TASK_BOARD_SRC" \
  || fail "task-board does not support direct no-verifier completion"
grep -q 'verification_required' "$TASK_BOARD_SRC" \
  || fail "task-board does not persist verification requirement"
grep -q 'commit_required' "$TASK_BOARD_SRC" \
  || fail "task-board does not enforce the Human commit gate"
grep -q 'Human commit gate diff does not match the verified diff' "$TASK_BOARD_SRC" \
  || fail "task-board does not bind verification to the Human gate"
grep -q 'candidate_diff_sha256' "$TASK_BOARD_SRC" \
  || fail "task-board does not persist the frozen candidate hash"
grep -q 'complete requires --commit' "$TASK_BOARD_SRC" \
  || fail "task-board does not require commit evidence before completion"
grep -q 'only pm may transition tasks to complete' "$TASK_BOARD_SRC" \
  || fail "task-board does not enforce PM-only completion"
grep -q 'target_repo' "$TASK_BOARD_SRC" \
  || fail "task-board does not inspect target-root repository ownership"
grep -q '2>/dev/null)" || true' .agents/skills/agent-shared/lib/agent-helpers.sh \
  || fail "helper hook errors are not swallowed"

python3 - <<'PY'
import json
from pathlib import Path

root = Path.cwd()
team = json.loads((root / ".agents/team.json").read_text())
expected = {
    "orchestrator", "pm", "supervisor", "sa", "investigator",
    "researcher", "designer", "documenter", "coder", "refactor", "reviewer", "tester",
}
actual = set(team.get("roles", {}))
if actual != expected:
    raise SystemExit(f"role mismatch: expected={sorted(expected)} actual={sorted(actual)}")
files = {path.stem for path in (root / ".agents/agents").glob("*.md")}
if files != expected:
    raise SystemExit(f"role file mismatch: expected={sorted(expected)} actual={sorted(files)}")
for role in expected:
    text = (root / ".agents/agents" / f"{role}.md").read_text()
    if f"name: herdr-{role}" not in text.split("---", 2)[1]:
        raise SystemExit(f"Claude agent name mismatch for {role}")
if team.get("runtime_order") != ["pi", "claude"]:
    raise SystemExit("runtime_order must be pi then claude")
if team.get("version") != 4:
    raise SystemExit("team schema version must be 4")
if team.get("disabled_model_providers") != []:
    raise SystemExit("disabled_model_providers must be empty when no provider is disabled")
disabled_providers = set(team["disabled_model_providers"])

def model_provider(model):
    return model.split("/", 1)[0] if "/" in model else None

models = {
    "orchestrator": {
        "pi": [
            "antigravity/gemini-3.8-flash",
        ],
    },
    "pm": {
        "pi": [
            "antigravity/gemini-3.8-flash",
        ],
    },
    "supervisor": {
        "pi": [
            "opencode-go/deepseek-v4.1-flash",
        ],
    },
    "documenter": {
        "pi": [
            "antigravity/gemini-3.8-flash",
        ],
    },
    "sa": {
        "pi": [
            "alibaba-token-intl/qwen3.8-max",
            "antigravity/gemini-3.8-flash",
        ],
        "claude": [
            "opus",
        ],
    },
    "investigator": {
        "pi": [
            "opencode-go/deepseek-v4.1-flash",
            "antigravity/gemini-3.8-flash",
        ],
        "claude": [
            "opus",
        ],
    },
    "researcher": {
        "pi": [
            "antigravity/gemini-3.8-flash",
        ],
    },
    "designer": {
        "claude": [
            "opus",
        ],
    },
    "coder": {
        "pi": [
            "opencode-go/deepseek-v4.1-flash",
            "antigravity/gemini-3.8-flash",
        ],
        "claude": [
            "opus",
        ],
    },
    "refactor": {
        "pi": [
            "opencode-go/deepseek-v4.1-flash",
            "antigravity/gemini-3.8-flash",
        ],
        "claude": [
            "opus",
        ],
    },
    "reviewer": {
        "pi": [
            "antigravity/gemini-3.8-flash",
            "alibaba-token-intl/qwen3.8-max",
        ],
        "claude": [
            "opus",
        ],
    },
    "tester": {
        "pi": [
            "kiro/claude-haiku-5-5",
            "opencode-go/deepseek-v4.1-flash",
            "antigravity/gemini-3.8-flash",
            "alibaba-token-intl/qwen3.8-max",
        ],
        "claude": [
            "sonnet",
        ],
    },
}
primary_routes = {
    "supervisor": {
        "standard": ("pi", "opencode-go/deepseek-v4.1-flash"),
        "critical": ("pi", "opencode-go/deepseek-v4.1-flash"),
    },
    "documenter": {
        "standard": ("pi", "antigravity/gemini-3.8-flash"),
        "critical": ("pi", "antigravity/gemini-3.8-flash"),
    },
    "sa": {
        "standard": ("pi", "antigravity/gemini-3.8-flash"),
        "critical": ("claude", "opus"),
    },
    "investigator": {
        "standard": ("pi", "opencode-go/deepseek-v4.1-flash"),
        "critical": ("claude", "opus"),
    },
    "researcher": {
        "standard": ("pi", "antigravity/gemini-3.8-flash"),
        "critical": ("pi", "antigravity/gemini-3.8-flash"),
    },
    "coder": {
        "standard": ("pi", "opencode-go/deepseek-v4.1-flash"),
        "critical": ("claude", "opus"),
    },
    "refactor": {
        "standard": ("pi", "antigravity/gemini-3.8-flash"),
        "critical": ("claude", "opus"),
    },
    "reviewer": {
        "standard": ("pi", "alibaba-token-intl/qwen3.8-max"),
        "critical": ("claude", "opus"),
    },
    "tester": {
        "standard": ("pi", "kiro/claude-haiku-5-5"),
        "critical": ("claude", "sonnet"),
    },
}
alternate_routes = {
    "supervisor": {
        "standard": [],
        "critical": [],
    },
    "documenter": {
        "standard": [],
        "critical": [],
    },
    "sa": {
        "standard": [("pi", "alibaba-token-intl/qwen3.8-max")],
        "critical": [("pi", "alibaba-token-intl/qwen3.8-max")],
    },
    "investigator": {
        "standard": [("pi", "antigravity/gemini-3.8-flash")],
        "critical": [("pi", "antigravity/gemini-3.8-flash")],
    },
    "researcher": {
        "standard": [],
        "critical": [],
    },
    "coder": {
        "standard": [("pi", "antigravity/gemini-3.8-flash")],
        "critical": [("pi", "opencode-go/deepseek-v4.1-flash")],
    },
    "refactor": {
        "standard": [("pi", "opencode-go/deepseek-v4.1-flash")],
        "critical": [("pi", "opencode-go/deepseek-v4.1-flash")],
    },
    "reviewer": {
        "standard": [("pi", "antigravity/gemini-3.8-flash")],
        "critical": [("pi", "alibaba-token-intl/qwen3.8-max")],
    },
    "tester": {
        "standard": [("pi", "alibaba-token-intl/qwen3.8-max"), ("pi", "antigravity/gemini-3.8-flash")],
        "critical": [("pi", "antigravity/gemini-3.8-flash")],
    },
}
fixed_roles = {
    "orchestrator": "antigravity/gemini-3.8-flash",
    "pm": "antigravity/gemini-3.8-flash",
    "designer": "opus",
}
for name, config in team["roles"].items():
    if config.get("may_read_direct_reports") != bool(config.get("controls")):
        raise SystemExit(f"invalid read capability for {name}")
    expected_mode = "write" if name in {"coder", "refactor"} else "read_only"
    if config.get("repo_mode") != expected_mode:
        raise SystemExit(f"invalid repo_mode for {name}")
    if config.get("may_local_commit") != (name in {"supervisor", "coder", "refactor"}):
        raise SystemExit(f"invalid local commit capability for {name}")
    if config.get("may_authorized_push") != (name in {"supervisor", "coder", "refactor"}):
        raise SystemExit(f"invalid authorized push capability for {name}")
    if config.get("may_authorized_pr_create") != (name in {"supervisor", "coder", "refactor"}):
        raise SystemExit(f"invalid authorized PR capability for {name}")
    if config.get("may_remote_deliver") is not False:
        raise SystemExit(f"team role must not deliver remotely: {name}")
    if config.get("may_document_write", False) != (name == "documenter"):
        raise SystemExit(f"invalid document-writing capability for {name}")
    if config.get("may_vault_read", False) != (name == "investigator"):
        raise SystemExit(f"invalid vault-read capability for {name}")
    expected_selection = "fixed" if name in fixed_roles else "controller"
    if config.get("model_selection") != expected_selection:
        raise SystemExit(f"invalid model selection mode for {name}")
    if name in fixed_roles and config.get("default_model") != fixed_roles[name]:
        raise SystemExit(f"invalid fixed-role default model for {name}")
    if name in fixed_roles and model_provider(config["default_model"]) in disabled_providers:
        raise SystemExit(f"fixed-role default uses a disabled provider: {name}")
    if config.get("models") != models[name]:
        raise SystemExit(f"invalid ordered model allowlist for {name}")
    routing = config.get("routing")
    if name in fixed_roles:
        if routing is not None:
            raise SystemExit(f"fixed role must not define tier routing: {name}")
    else:
        if not isinstance(routing, dict) or set(routing) != {"standard", "critical"}:
            raise SystemExit(f"invalid routing tiers for {name}")
        for tier, route in routing.items():
            if not isinstance(route, dict) or set(route) != {"primary", "alternates"}:
                raise SystemExit(f"invalid routing policy for {name}/{tier}")
            primary = route.get("primary")
            alternates = route.get("alternates")
            if not isinstance(primary, dict) or set(primary) != {"runtime", "model"}:
                raise SystemExit(f"invalid primary route for {name}/{tier}")
            primary_pair = (primary["runtime"], primary["model"])
            if primary_pair != primary_routes[name][tier]:
                raise SystemExit(f"unexpected primary route for {name}/{tier}")
            if primary["model"] not in models[name].get(primary["runtime"], []):
                raise SystemExit(f"primary route is outside allowlist for {name}/{tier}")
            if not isinstance(alternates, list):
                raise SystemExit(f"invalid alternate routes for {name}/{tier}")
            alternate_pairs = []
            for alternate in alternates:
                if not isinstance(alternate, dict) or set(alternate) != {"runtime", "model"}:
                    raise SystemExit(f"invalid alternate route for {name}/{tier}")
                pair = (alternate["runtime"], alternate["model"])
                if alternate["model"] not in models[name].get(alternate["runtime"], []):
                    raise SystemExit(f"alternate route is outside allowlist for {name}/{tier}")
                alternate_pairs.append(pair)
            if primary_pair in alternate_pairs or len(alternate_pairs) != len(set(alternate_pairs)):
                raise SystemExit(f"duplicate route for {name}/{tier}")
            if alternate_pairs != alternate_routes[name][tier]:
                raise SystemExit(f"unexpected alternate routes for {name}/{tier}")
            if model_provider(primary["model"]) in disabled_providers:
                enabled_alternates = [
                    pair for pair in alternate_pairs
                    if model_provider(pair[1]) not in disabled_providers
                ]
                if not enabled_alternates:
                    raise SystemExit(f"disabled primary has no enabled alternate for {name}/{tier}")
    parents = config.get("reports_to")
    if isinstance(parents, str):
        parents = [parents]
    for parent in parents:
        if parent != "human" and name not in team["roles"][parent].get("controls", []):
            raise SystemExit(f"invalid ownership for {parent}->{name}")

    if expected_mode == "read_only" and name not in {"pm", "documenter"}:
        frontmatter = (root / ".agents/agents" / f"{name}.md").read_text().split("---", 2)[1]
        for tool in ("Edit", "Write", "NotebookEdit"):
            if f"  - {tool}" not in frontmatter:
                raise SystemExit(f"{name} does not disallow {tool}")

configured_providers = {
    model_provider(model)
    for runtime_models in models.values()
    for values in runtime_models.values()
    for model in values
    if model_provider(model)
}
if not disabled_providers <= configured_providers:
    raise SystemExit("disabled_model_providers contains an unknown provider")

for skill_file in (root / ".agents/skills").glob("*/SKILL.md"):
    parts = skill_file.read_text().split("---", 2)
    if len(parts) < 3:
        raise SystemExit(f"missing frontmatter: {skill_file}")
    description = next(
        (line.split(":", 1)[1].strip() for line in parts[1].splitlines()
         if line.startswith("description:")),
        None,
    )
    try:
        parsed = json.loads(description) if description is not None else None
    except json.JSONDecodeError:
        raise SystemExit(f"skill description must be a quoted string: {skill_file}")
    if not isinstance(parsed, str) or not parsed:
        raise SystemExit(f"invalid skill description: {skill_file}")
PY

for forbidden in .agents/workflows .agents/mcp.json .agents/conventions .ap-dev docs; do
  [ ! -e "$forbidden" ] || fail "legacy catalog remains: $forbidden"
done

if grep -R -n -E 'herdr[[:space:]]+wait([[:space:]]|$)' bin setup_harness.sh \
  .agents/skills/agent-shared .agents/agents >/dev/null 2>&1; then
  fail "executable or role content contains a Herdr blocking wait command"
fi

if grep -R -n -E 'herdr[[:space:]]+pane[[:space:]]+read' \
  .agents/agents/{sa,investigator,researcher,designer,coder,refactor,reviewer,tester}.md \
  bin >/dev/null 2>&1; then
  fail "non-controller role or binary contains pane transcript access"
fi

grep -q -- '--dangerously-skip-permissions' bin/agent-runtime \
  || fail "Claude permission flag is missing"
grep -q -- '--agent' bin/agent-runtime || fail "Claude role selection is missing"
grep -q 'pi --version' bin/agent-runtime || fail "Pi health check is missing"
grep -q 'claude --version' bin/agent-runtime || fail "Claude health check is missing"
grep -q 'project-scaffold-claude-skills.txt' setup_harness.sh \
  || fail "setup does not track installed Claude skills"
grep -q 'Claude skill missing' bin/herdr-team \
  || fail "launcher does not check native Claude skills"
grep -q 'orchestrator-shutdown.ts' bin/agent-runtime \
  || fail "Pi Orchestrator shutdown extension is not wired into the runtime"
grep -q 'voice-notify.ts' bin/agent-runtime \
  || fail "Pi voice notification extension is not wired into the runtime"
grep -q 'PermissionRequest' bin/agent-runtime \
  || fail "Claude voice notification hooks are not wired into the runtime"
grep -q -- '--voice on|off' bin/herdr-team \
  || fail "herdr-team voice option is missing"
grep -q 'VOICE_MODE=.*off' bin/herdr-team \
  || fail "herdr-team voice mode does not default to off"
grep -Fq 'ตรวจสอบ Workspace Registry เรียบร้อยแล้วค่ะ พบ {N} โปรเจกต์ กรุณาเลือกโปรเจกต์ที่ต้องการเปิดค่ะ' \
  bin/herdr-team || fail "startup voice outcome contract is missing from launcher prompt"
grep -Fq 'ตรวจสอบ Workspace Registry เรียบร้อยแล้วค่ะ พบ {N} โปรเจกต์ กรุณาเลือกโปรเจกต์ที่ต้องการเปิดค่ะ' \
  .agents/agents/orchestrator.md || fail "startup voice outcome contract is missing from Orchestrator prompt"
grep -Fq 'If the Human must act' bin/herdr-team \
  || fail "launcher prompt does not require the Human next action in voice output"
grep -Fq 'If the Human must act' .agents/agents/orchestrator.md \
  || fail "Orchestrator prompt does not require the Human next action in voice output"
grep -Fq 'plain speech without Markdown' bin/herdr-team \
  || fail "launcher prompt does not require plain speech for voice output"
grep -Fq 'plain speech without Markdown' .agents/agents/orchestrator.md \
  || fail "Orchestrator prompt does not require plain speech for voice output"
grep -q 'role === "orchestrator" || role === "pm"' .agents/extensions/voice-notify.ts \
  || fail "Pi voice summary is not limited to Human-facing controllers"
grep -q 'pi.on("input"' .agents/extensions/voice-notify.ts \
  || fail "Pi voice ownership does not follow direct Human input"
grep -q 'pi.on("before_agent_start"' .agents/extensions/voice-notify.ts \
  && grep -q 'isInterAgentPrompt(event.prompt)' .agents/extensions/voice-notify.ts \
  || fail "Pi PM voice summary is not bound to the Human-triggered run"
grep -q 'agent_end' .agents/extensions/voice-notify.ts \
  || fail "Pi voice summary does not capture the completed assistant response"
grep -q 'agent_settled' .agents/extensions/voice-notify.ts \
  || fail "Pi voice notification extension does not wait for settled sessions"
grep -q 'summary' bin/voice-notify \
  || fail "voice helper does not support summaries"
grep -q 'HERDR_VOICE_CONFIG_DIR:-\$HOME/.config/herdr' bin/voice-notify \
  || fail "voice helper does not prefer the project-installed TTS adapter"
grep -q 'HERDR_VOICE_NOTIFY=0' bin/voice-notify \
  || fail "voice notification opt-out is not documented"
grep -q 'HERDR_VOICE_OWNER_FILE' bin/herdr-team bin/spawn-agent bin/voice-notify \
  || fail "session-scoped voice ownership is not propagated"
grep -q 'is_inter_agent_prompt' bin/voice-notify \
  || fail "voice ownership does not suppress inter-agent protocol input"
grep -q 'UserPromptSubmit' bin/agent-runtime \
  || fail "Claude voice ownership does not follow direct Human input"
grep -q 'registerCommand("shutdown"' .agents/extensions/orchestrator-shutdown.ts \
  || fail "Pi shutdown extension does not register /shutdown"
grep -q 'sendUserMessage("shutdown")' .agents/extensions/orchestrator-shutdown.ts \
  || fail "Pi shutdown extension does not preserve the existing shutdown flow"
if grep -q 'registerCommand("quit"' .agents/extensions/orchestrator-shutdown.ts; then
  fail "Pi shutdown extension overrides /quit"
fi
grep -q 'pi.on("agent_settled"' .agents/extensions/auto-compact.ts \
  || fail "Pi auto-compact extension does not wait for a settled agent run"
if grep -q 'pi.on("turn_end"' .agents/extensions/auto-compact.ts; then
  fail "Pi auto-compact extension may interrupt a multi-turn agent run"
fi
grep -q 'ctx.isIdle()' .agents/extensions/auto-compact.ts \
  && grep -q 'ctx.hasPendingMessages()' .agents/extensions/auto-compact.ts \
  || fail "Pi auto-compact extension does not guard idle and queued work"
grep -q 'ctx.getContextUsage()' .agents/extensions/auto-compact.ts \
  || fail "Pi auto-compact extension does not inspect context usage"
grep -q 'ctx.compact({' .agents/extensions/auto-compact.ts \
  || fail "Pi auto-compact extension does not trigger compaction"
grep -q 'COMPACT_THRESHOLD_PERCENT = 50' .agents/extensions/auto-compact.ts \
  || fail "Pi auto-compact threshold is not 50 percent"
grep -q 'auto-compact.log' .agents/extensions/auto-compact.ts \
  || fail "Pi auto-compact extension logs nothing, so a silent failure cannot be seen"
grep -q 'role-guard.ts' bin/agent-runtime \
  || fail "runtime does not attach the role guard"
grep -q 'Bash(hc wait:\*)' bin/agent-runtime \
  || fail "Claude runtime does not deny blocking waits"
grep -q 'for binary in herdr-team agent-runtime spawn-agent verify-pane-agent agent-team-shutdown validate-okf voice-notify task-board' \
  setup_harness.sh || fail "installer does not manage task-board"
grep -q 'project-scaffold-pi-extensions.txt' setup_harness.sh \
  || fail "installer does not manage Pi extensions"
grep -q 'project-scaffold-voice-files.txt' setup_harness.sh \
  || fail "installer does not manage the project TTS adapter"
grep -q 'bin/tts-thai.sh' setup_harness.sh \
  || fail "installer does not install the project TTS adapter"
grep -q 'guard-bin' setup_harness.sh || fail "installer does not manage command guards"
grep -q 'Project Bootstrap and Direct Handoff' .agents/agents/orchestrator.md \
  || fail "Orchestrator lacks the direct-PM bootstrap gate"
grep -q 'PM is never permission to implement' .agents/agents/orchestrator.md \
  || fail "Orchestrator may still take over PM work"
grep -q 'Human project selection is the bootstrap gate' .agents/agents/orchestrator.md \
  || fail "Orchestrator lacks a hard project-selection bootstrap transition"
grep -q 'PM owns project discovery' .agents/agents/orchestrator.md \
  || fail "Orchestrator may still self-investigate instead of handing off"
grep -q 'agent-team-shutdown' .agents/agents/orchestrator.md \
  || fail "Orchestrator lacks the executable shutdown protocol"
grep -q 'Do not remain in `working` state' .agents/agents/orchestrator.md \
  || fail "Orchestrator may still stay working while waiting for PM"
grep -q 'drain, optimize, edit, reorder' .agents/agents/orchestrator.md \
  || fail "Orchestrator may still process queued prompts while task is running"
grep -q 'Do not monitor PM' .agents/agents/orchestrator.md \
  || fail "Orchestrator may still monitor routine PM work after handoff"
grep -q 'primary Human-facing controller' .agents/agents/pm.md \
  && grep -q 'do not send routine plans' .agents/agents/pm.md \
  || fail "PM is not the direct Human-facing project controller"
grep -q 'optional voice summary' .agents/agents/pm.md \
  && grep -q 'never more than 160 characters' .agents/agents/pm.md \
  || fail "PM prompt lacks the bounded Human-facing voice contract"
grep -q '^## Direct PM Gateway$' .agents/protocols/communication.md \
  || fail "communication protocol lacks the direct PM gateway"
grep -q 'delayed shell loop' .agents/agents/pm.md \
  || fail "PM may still poll with sleep-delayed Herdr checks"
grep -q 'herdr pane process-info' .agents/agents/pm.md \
  || fail "PM polling prohibition does not name pane metadata checks"
grep -q 'Do not run repository verification' .agents/agents/pm.md \
  || fail "PM may still self-verify after Supervisor DONE"
grep -q '^## Completion Gate$' .agents/agents/pm.md \
  && grep -q 'Journal delegated' .agents/agents/pm.md \
  && grep -q 'Journal confirmed' .agents/agents/pm.md \
  || fail "PM completion gate no longer requires the OKF journal round"
grep -q 'feminine Thai' .agents/agents/pm.md \
  && grep -q 'never ผม or ครับ' .agents/agents/pm.md \
  || fail "PM prompt no longer keeps the feminine Thai speaking style for the voice line"
grep -q 'feminine Thai' .agents/agents/orchestrator.md \
  || fail "Orchestrator prompt no longer keeps the feminine Thai speaking style"
grep -q 'Actions & Results' .agents/agents/documenter.md \
  || fail "Documenter entry shape lost its Actions & Results field"
grep -q 'send one clarification request to Supervisor' .agents/agents/pm.md \
  || fail "PM lacks required alternative for missing Supervisor evidence"
grep -q '^## Dispatch Accounting and Unexpected Replies$' .agents/agents/pm.md \
  || fail "PM lacks dispatch accounting safeguards"
grep -q 'Never infer that' .agents/agents/pm.md \
  || fail "PM may infer dispatch state from incomplete context"
grep -q '^### Dispatch Records$' .agents/protocols/communication.md \
  || fail "communication protocol lacks dispatch records"
grep -q 'UNEXPECTED_REPLY' .agents/protocols/communication.md \
  || fail "communication protocol lacks unexpected-reply handling"
grep -q '^## Prose Quality$' .agents/protocols/communication.md \
  || fail "communication protocol lacks scoped prose-quality guidance"
grep -q 'Human-facing explanations,' .agents/protocols/communication.md \
  && grep -q 'OKF journal entries, PR bodies' .agents/protocols/communication.md \
  || fail "prose-quality guidance does not cover approved narrative surfaces"
grep -q 'Do not apply an English word blacklist' \
  .agents/protocols/communication.md \
  && grep -q 'or punctuation ban to Thai or technical writing' \
    .agents/protocols/communication.md \
  || fail "prose-quality guidance applies unsafe language heuristics"
grep -q 'Do not rewrite, reorder, translate, normalize, or' \
  .agents/protocols/communication.md \
  && grep -q 'protocol envelopes, state tags, task fields, candidate' \
    .agents/protocols/communication.md \
  && grep -q 'metadata, or authorization tokens' \
    .agents/protocols/communication.md \
  || fail "prose-quality guidance does not preserve exact protocol content"
grep -q 'not another agent,' .agents/protocols/communication.md \
  && grep -q 'verification stage, or retry loop' \
    .agents/protocols/communication.md \
  || fail "prose self-audit can expand the approved team or workflow"
grep -q 'delayed shell loop' .agents/agents/supervisor.md \
  || fail "Supervisor may still poll with sleep-delayed Herdr checks"
grep -q 'herdr pane process-info' .agents/agents/supervisor.md \
  || fail "Supervisor polling prohibition does not name pane metadata checks"
grep -q 'Do not self-verify Worker output' .agents/agents/supervisor.md \
  || fail "Supervisor may still self-verify Worker output"
grep -q 'ask the responsible direct report' .agents/agents/supervisor.md \
  || fail "Supervisor lacks required alternative for missing evidence"
grep -q 'sleep 30 && herdr pane list' .agents/skills/herdr/SKILL.md \
  || fail "Herdr skill lacks explicit sleep polling prohibition"
grep -q 'Human-controlled external harness operator' AGENTS.md \
  || fail "AGENTS policy lacks external read-only audit authority"
grep -q '^## Minimal Change and Scope Lock$' AGENTS.md \
  || fail "AGENTS policy lacks the minimal-change scope lock"
grep -q '^## Minimal Change Gate$' .agents/skills/agent-team/SKILL.md \
  || fail "agent-team skill lacks the minimal-change gate"
grep -q 'Allowed files' .agents/agents/pm.md \
  || fail "PM does not require an explicit file allowlist"
grep -q 'Prefer the smallest direct change' .agents/agents/coder.md \
  || fail "Coder does not enforce the smallest direct change"
grep -q 'Rank plausible causes by supporting evidence and' \
  .agents/agents/investigator.md \
  && grep -q 'the cheapest safe falsification' .agents/agents/investigator.md \
  && grep -q 'Stop when the evidence is sufficient to name one credible mechanism' \
    .agents/agents/investigator.md \
  || fail "Investigator lacks evidence-ranked hypotheses and a stop condition"
grep -q 'reproduce the failure first when doing' .agents/agents/coder.md \
  && grep -q 'narrowest layer that owns the incorrect' .agents/agents/coder.md \
  && grep -q 'Run focused proof and' .agents/agents/coder.md \
  && grep -q 'the nearest affected approved gate' .agents/agents/coder.md \
  || fail "Coder lacks reproduce-first surgical-patch guidance"
grep -q 'Before structural edits, establish the approved' \
  .agents/agents/refactor.md \
  && grep -q 'public interfaces,' .agents/agents/refactor.md \
  && grep -q 'failure behavior, ordering, and compatibility' \
    .agents/agents/refactor.md \
  && grep -q 'Rerun the same baseline proof after the change' \
    .agents/agents/refactor.md \
  || fail "Refactor lacks a behavior-preservation baseline and repeat proof"
grep -q 'smallest sufficient proof set' .agents/agents/tester.md \
  && grep -q 'Reuse recorded' .agents/agents/tester.md \
  && grep -q 'Candidate Diff SHA-256 and repository state still match' \
    .agents/agents/tester.md \
  && grep -q 'Stop when the approved acceptance proof is complete' \
    .agents/agents/tester.md \
  || fail "Tester lacks verify-and-stop candidate-state guidance"
grep -q 'frozen staged diff' .agents/agents/reviewer.md \
  || fail "Reviewer does not verify the frozen staged candidate"
grep -q '^## Scope Lock$' .agents/protocols/communication.md \
  || fail "communication protocol lacks the scope lock"
grep -q 'Work branch: {approved non-protected implementation branch}' \
  AGENTS.md .agents/protocols/communication.md \
  || fail "scope lock lacks an approved work branch"
grep -q 'Do not ask the Human to create or switch branches' AGENTS.md \
  || fail "team policy still delegates routine branch setup to the Human"
grep -q '\[AWAITING_HUMAN_COMMIT\]' AGENTS.md .agents/protocols/communication.md \
  || fail "commit review waiting state is not documented"
grep -q 'agent_prepare_commit_review' .agents/agents/{coder,refactor}.md \
  || fail "Worker prompts do not require the commit review helper"
grep -q 'agent_prepare_verification_candidate' .agents/agents/{coder,refactor}.md \
  || fail "Worker prompts do not freeze a candidate before verification"
grep -q 'agent_verify_staged_diff' .agents/agents/{reviewer,tester}.md \
  || fail "Verifier prompts do not bind verdicts to the candidate hash"
grep -q 'not run after commit' \
  .agents/protocols/communication.md \
  || fail "protocol still permits post-commit independent verification"
grep -q 'agent_authorized_commit' .agents/skills/agent-shared/SKILL.md \
  || fail "shared skill does not document authorized commits"
grep -q 'APPROVE_COMMIT' .agents/agents/{pm,supervisor}.md \
  && grep -q 'AUTO_COMMIT' .agents/agents/pm.md \
  || fail "direct PM chain does not route commit approvals and auto mode"
grep -q -- '--base-branch and --work-branch are required' bin/spawn-agent \
  || fail "spawn-agent does not require approved Worker branch inputs"
grep -q 'launcher creates a missing branch from the' .agents/agents/supervisor.md \
  || fail "Supervisor does not delegate safe branch preparation"
grep -q 'role list is a catalog, not a startup roster' AGENTS.md \
  || fail "AGENTS policy still treats every role as startup staffing"
grep -q 'Team Proposal' .agents/agents/pm.md \
  || fail "PM does not propose task-specific staffing"
grep -q '`Staffing`' .agents/agents/pm.md \
  || fail "PM does not own a staffing mode"
grep -q 'You own the staffing decision' .agents/agents/pm.md \
  || fail "PM staffing decision is not autonomous"
grep -q 'direct execution' .agents/agents/pm.md \
  || fail "PM cannot choose direct execution"
grep -q 'Execution path' .agents/protocols/communication.md \
  || fail "communication protocol lacks the execution path"
grep -q 'Execution path: direct' .agents/agents/pm.md \
  || fail "PM does not document direct execution"
grep -q 'spawn only the approved independent Reviewer, Tester, or both' \
  .agents/agents/supervisor.md \
  || fail "Supervisor does not honor verifier selection"
grep -q 'never copy PM.*upstream.*sender_pane' .agents/agents/supervisor.md \
  || fail "Supervisor may reuse PM pane for Verifier replies"
grep -q 'Final verdict target' .agents/agents/supervisor.md \
  || fail "Supervisor does not set an explicit Verifier verdict target"
grep -q 'do not reuse an upstream PM.*sender_pane' .agents/agents/tester.md \
  || fail "Tester does not preserve the assigned controller pane"
grep -q 'must not call `agent_done` after the verdict' \
  .agents/protocols/communication.md \
  || fail "Communication protocol permits duplicate Verifier completion"
grep -q 'reuse that tab and its' .agents/agents/supervisor.md \
  || fail "Supervisor does not reuse verifier panes"
grep -q 'close only retired tabs' .agents/agents/supervisor.md \
  || fail "Supervisor does not clean up retired verifier tabs"
grep -q 'do not create suffixed verifier tabs' .agents/skills/agent-team/SKILL.md \
  || fail "Supervisor still creates suffixed verifier tabs"
grep -q 'reuse that same agent and pane' .agents/skills/agent-team/SKILL.md \
  || fail "agent-team skill does not reuse Verifier instances for revisions"
grep -q 'Keep one pane per selected Verifier role' .agents/agents/supervisor.md \
  && grep -q '`spawn-agent`, split a pane' .agents/agents/supervisor.md \
  || fail "Supervisor may spawn duplicate Verifiers during a revision loop"
grep -q 'revision assignment to the already selected Verifier pane' \
  .agents/agents/supervisor.md \
  || fail "Supervisor does not route revisions to the existing Verifier"
grep -q 'does not require a fresh Tester process or pane' \
  .agents/agents/tester.md \
  || fail "Tester prompt still implies a fresh process for revisions"
grep -q 'does not require a fresh Reviewer process or pane' \
  .agents/agents/reviewer.md \
  || fail "Reviewer prompt still implies a fresh process for revisions"
grep -q 'never keep duplicate same-role Verifier' \
  .agents/protocols/communication.md \
  || fail "communication protocol permits duplicate Verifier panes"
grep -q 'Honor PM.*Staffing' .agents/agents/supervisor.md \
  || fail "Supervisor does not honor PM staffing mode"
grep -q 'Low-risk work may use' .agents/agents/supervisor.md \
  || fail "Supervisor does not support single-verifier low-risk work"
grep -q 'high-risk work uses both Reviewer and Tester' \
  .agents/agents/supervisor.md \
  || fail "Supervisor does not require both verifiers for high-risk work"
grep -q 'Revision budget: 2' .agents/skills/agent-team/SKILL.md \
  && grep -q 'Revision: 2/2' .agents/agents/supervisor.md \
  || fail "revision ceiling is not defined for Supervisor execution"
grep -q 'Only a `BLOCKER`' .agents/protocols/communication.md \
  && grep -q 'ADVISORY' .agents/agents/reviewer.md \
  || fail "Verifier severity gate is missing"
grep -q 'Tester is not valid for a document without runnable acceptance' \
  .agents/agents/supervisor.md \
  || fail "Supervisor can still use Tester for an un-runnable document"
grep -q -- '--runnable-acceptance' bin/spawn-agent \
  || fail "spawn-agent lacks the explicit runnable-acceptance gate"
grep -q 'Model budget: {economical|balanced|premium}' \
  .agents/protocols/communication.md \
  || fail "task proposal lacks a model budget"
grep -q 'do not request another revision' .agents/agents/pm.md \
  || fail "PM lacks the hard revision stop"
grep -q 'agent_revision_gate' .agents/skills/agent-shared/lib/agent-helpers.sh \
  || fail "shared helpers lack the executable revision gate"
grep -q 'Task class: {advisory|document|operational|delivery|investigation|bug-fix|feature|refactor}' \
  .agents/skills/agent-team/SKILL.md .agents/protocols/communication.md \
  || fail "task classes do not include delivery, document, and operational work"
grep -q '## Delivery Fast Path' .agents/protocols/communication.md \
  && grep -q 'no broad repository discovery' .agents/agents/pm.md \
  || fail "delivery fast path is not bounded"
grep -q 'superseded' .agents/agents/orchestrator.md \
  || fail "Orchestrator does not supersede stale active tasks"
grep -q 'document-only change' AGENTS.md \
  && grep -q 'not an implementation requiring a Verifier' AGENTS.md \
  || fail "document-only work still requires an implementation verifier"
grep -q 'For a `document` task' .agents/agents/pm.md \
  && grep -q 'Documenter' .agents/agents/pm.md \
  && grep -q 'do not launch Coder' .agents/agents/pm.md \
  || fail "PM does not delegate document writing"
grep -q '"documenter"' .agents/team.json \
  && grep -q '"may_document_write": true' .agents/team.json \
  || fail "team metadata does not grant Documenter document-writing capability"
grep -q 'Open Knowledge Format' .agents/agents/documenter.md \
  && grep -q 'frontmatter-free' .agents/agents/documenter.md \
  && grep -q 'non-empty `type`' .agents/agents/documenter.md \
  || fail "Documenter lacks the OKF output contract"
grep -q 'Knowledge source: vault' .agents/agents/investigator.md \
  && grep -q 'Maximum results' .agents/agents/investigator.md \
  && grep -q '"may_vault_read": true' .agents/team.json \
  && grep -q '^## Scoped Vault Retrieval$' README.md \
  || fail "scoped vault retrieval feature is incomplete"
grep -q -- '--knowledge-source vault' .agents/agents/pm.md \
  && grep -q -- '--vault-read-scope' bin/agent-runtime bin/spawn-agent \
  || fail "PM or runtime does not route scoped vault retrieval"
grep -q '`Task class: document`' .agents/agents/pm.md \
  && grep -q -- '--task-class document' .agents/agents/pm.md \
  || fail "PM does not route the document task class to Documenter"
grep -q 'A `document` or routine `operational` brief may select' \
  .agents/agents/supervisor.md \
  || fail "Supervisor does not permit unverified document tasks"
grep -q '^## Team Proposal$' .agents/protocols/communication.md \
  || fail "communication protocol lacks the team proposal contract"
grep -q 'For an approved advisory or investigation task with no Worker or Verifier' \
  .agents/skills/agent-team/SKILL.md \
  || fail "agent-team skill lacks the no-Supervisor completion path"
grep -q 'Routine plans, status, authorization gates, and completion stay between Human and PM' bin/herdr-team \
  || fail "launcher prompt does not enforce direct PM handoff"
grep -q '`minimal`, `focused`, or' .agents/agents/pm.md \
  || fail "PM prompt does not expose staffing modes"
grep -q 'Execution path' .agents/agents/pm.md .agents/protocols/communication.md \
  || fail "PM contract does not expose execution paths"
grep -q '^## Model Selection$' .agents/protocols/communication.md \
  || fail "communication protocol lacks the model selection contract"
grep -q '^Task Tier Assessment:$' .agents/protocols/communication.md \
  && grep -q 'totals 0-7 are `standard` and 8-10 are' \
    .agents/protocols/communication.md \
  || fail "communication protocol lacks the task-tier assessment rubric"
grep -q -- '--task-tier TIER' bin/spawn-agent bin/agent-runtime \
  && grep -q -- '--routing-exception' bin/spawn-agent bin/agent-runtime \
  || fail "runtime does not expose hard-enforced tier routing"
for controller_prompt in .agents/agents/{pm,supervisor}.md; do
  grep -q 'Task Tier Assessment' "$controller_prompt" \
    || fail "controller prompt lacks task-tier assessment recording: $controller_prompt"
  grep -q 'Model Selection' "$controller_prompt" \
    || fail "controller prompt lacks model selection recording: $controller_prompt"
  grep -q -- '--task-tier' "$controller_prompt" \
    || fail "controller prompt does not pass the task tier: $controller_prompt"
  grep -q -- '--runtime' "$controller_prompt" \
    && grep -q -- '--model' "$controller_prompt" \
    || fail "controller prompt does not pass the runtime/model pair: $controller_prompt"
done
grep -q 'Routing: fixed' .agents/agents/orchestrator.md \
  && grep -q 'without tier routing' .agents/agents/orchestrator.md \
  || fail "Orchestrator prompt does not record the fixed PM launch contract"
grep -q -- '--model MODEL' bin/herdr-team \
  || fail "herdr-team does not document its Orchestrator model override"
grep -q 'HERDR_TEAM_MODEL' bin/herdr-team \
  || fail "herdr-team does not forward its Orchestrator model override"
if grep -q 'spawn independent Reviewer and Tester agents' \
  .agents/agents/supervisor.md; then
  fail "Supervisor still requires both verifier roles for every task"
fi
grep -q 'must not set `HERDR_ENV=1` to impersonate' .agents/skills/herdr/SKILL.md \
  || fail "Herdr skill does not prevent external audit impersonation"
grep -q 'one-shot read-only audit' .agents/skills/herdr/SKILL.md \
  || fail "Herdr skill lacks the external read-only audit scope"
grep -q '^### External Orchestrator relay$' .agents/skills/herdr/SKILL.md \
  || fail "Herdr skill lacks the Human-authorized external relay"
grep -q 'exactly one pane is labelled `orchestrator`' \
  .agents/skills/herdr/SKILL.md \
  || fail "Herdr skill does not restrict the external relay target"
grep -q 'must not contain an `APPROVE_COMMIT`' \
  .agents/skills/herdr/SKILL.md \
  || fail "Herdr skill allows external relay of commit authorization"
grep -q 'relay one Human-authored, non-authorizing text' AGENTS.md \
  || fail "AGENTS policy lacks the scoped external Orchestrator relay"
grep -q 'installed `herdr-team` launcher remains the only startup exception' \
  .agents/skills/herdr/SKILL.md \
  || fail "Herdr skill lacks the scoped launcher startup exception"
grep -q 'Do not emulate polling with' .agents/skills/agent-team/SKILL.md \
  || fail "Agent-team skill lacks explicit delayed polling prohibition"
if grep -R -n '/exit' bin .agents AGENTS.md README.md >/dev/null 2>&1; then
  fail "removed Pi /exit command remains in the harness"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Exercise the TTS adapter without network access or audible output: VoiceStudio
# is disabled (TTS_OMNI_DISABLE=1) so the gTTS fallback is what runs.
python3 - "$TMP" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]) / "tts-test"
root.mkdir()
adapter = Path("bin/tts-thai.sh").resolve()
source = adapter.read_text()
low = source.lower()
assert "/usr/bin/say" not in low, "the macOS say fallback is still in the adapter"
assert "gtts" in low, "the adapter no longer keeps its gTTS fallback"
assert "tts-speak-omni" in low and "voicestudio" in low, \
    "the adapter does not prefer VoiceStudio when it is running"

stub = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["TTS_TEST_LOG"], "a") as log:
    log.write(json.dumps([name, args]) + "\\n")
if name == "gtts-cli":
    if os.environ.get("TTS_TEST_MODE") == "fail":
        sys.exit(1)
    pathlib.Path(args[args.index("--output") + 1]).write_bytes(b"gtts audio")
if name == "ffmpeg":
    pathlib.Path(args[-1]).write_bytes(b"converted audio")
'''
for name in ("gtts-cli", "afplay", "ffmpeg"):
    path = root / name
    path.write_text(stub)
    path.chmod(0o755)
log = root / "calls.jsonl"
env = {k: v for k, v in os.environ.items()
       if not k.startswith(("HERDR_VOICE_", "HERDR_GTTS_", "TTS_THAI_"))}
accent_stub = root / "thai-accent"
accent_stub.write_text("#!/usr/bin/env bash\nprintf '%s-ACCENTED' \"$(cat)\"\n")
accent_stub.chmod(0o755)
env.update(PATH=str(root) + os.pathsep + os.environ["PATH"],
           HERDR_VOICE_CACHE_DIR=str(root / "cache"),
           HERDR_GTTS_CLI=str(root / "gtts-cli"),
           TTS_THAI_AFPLAY=str(root / "afplay"),
           TTS_TEST_LOG=str(log),
           TTS_THAI_ACCENT="0",
           TTS_OMNI_DISABLE="1")

def run(text, check=True, **overrides):
    log.write_text("")
    proc = subprocess.run(["bash", str(adapter), text], env={**env, **overrides},
                          capture_output=True, text=True)
    if check:
        assert proc.returncode == 0, proc.stderr
    return [json.loads(line) for line in log.read_text().splitlines()], proc

text = 'สรุป "งาน" เสร็จแล้วค่ะ\nNext step: review'
calls, proc = run(text)
assert [c[0] for c in calls] == ["gtts-cli", "afplay"], calls
assert "provider=gtts cache=miss" in proc.stdout, proc.stdout
assert calls[0][1][:2] == ["--lang", "th"], calls[0]
assert calls[0][1][-1] == text, "the spoken text was rewritten"
assert len(list((root / "cache").glob("gtts-*.mp3"))) == 1, "miss did not cache"

calls, proc = run(text)
assert [c[0] for c in calls] == ["afplay"], "cache hit reached gTTS"
assert "cache=hit" in proc.stdout, proc.stdout

calls, _ = run(text, HERDR_VOICE_CACHE_DIR=str(root / "speed"), HERDR_VOICE_SPEED="1.25")
assert [c[0] for c in calls] == ["gtts-cli", "ffmpeg", "afplay"], calls
assert "atempo=1.25" in calls[1][1], calls[1]

calls, _ = run("deploy now", TTS_THAI_ACCENT="1", TTS_THAI_ACCENT_BIN=str(accent_stub),
               HERDR_VOICE_CACHE_DIR=str(root / "accent"))
assert calls[0][1][-1] == "deploy now-ACCENTED", calls

calls, _ = run("deploy now", TTS_THAI_ACCENT="0", TTS_THAI_ACCENT_BIN=str(accent_stub),
               HERDR_VOICE_CACHE_DIR=str(root / "accent-off"))
assert calls[0][1][-1] == "deploy now", calls

calls, proc = run(text, check=False, TTS_TEST_MODE="fail",
                  HERDR_VOICE_CACHE_DIR=str(root / "fail"))
assert proc.returncode == 1, "a gTTS failure must not exit 0"
assert "gtts failed" in proc.stderr, proc.stderr
assert not [c for c in calls if c[0] == "afplay"], "a failed synthesis still played"
assert not list((root / "fail").glob("gtts-*.mp3")), "failed response cached"

calls, proc = run("hi", check=False, HERDR_GTTS_CLI="", HOME=str(root / "home"),
                  PATH="/usr/bin:/bin", HERDR_VOICE_CACHE_DIR=str(root / "nocl"))
assert proc.returncode == 1 and "gtts-cli not found" in proc.stderr, proc.stderr

calls, proc = run("")
assert calls == [] and proc.returncode == 0, "empty text should not speak"

print("validate: gTTS-only TTS request, cache, and failure checks passed")
PY
mkdir -p "$TMP/bin"
mkdir -p "$TMP/okf"
printf '%s\n' '---' 'type: Agent Activity' 'title: Test' '---' '# Test' > "$TMP/okf/activity.md"
printf '%s\n' '# Update Log' '## 2026-07-25' '* **Test**: valid.' > "$TMP/okf/log.md"
bash bin/validate-okf "$TMP/okf" >/dev/null \
  || fail "validate-okf rejected a valid bundle"
printf '%s\n' '# Missing type' > "$TMP/okf/invalid.md"
if bash bin/validate-okf "$TMP/okf" >/dev/null 2>&1; then
  fail "validate-okf accepted a concept without type"
fi
mkdir -p "$TMP/okf-bad-log"
printf '%s\n' '---' 'type: Not a log' '---' '# Bad log' > "$TMP/okf-bad-log/log.md"
if bash bin/validate-okf "$TMP/okf-bad-log" >/dev/null 2>&1; then
  fail "validate-okf accepted frontmatter in reserved log.md"
fi
cat > "$TMP/bin/herdr" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_STUB_LOG"
case "${HERDR_STUB_FAIL_ON:-}" in
  run)
    [ "$1" = pane ] && [ "$2" = run ] && exit 19
    ;;
  send-keys)
    [ "$1" = pane ] && [ "$2" = send-keys ] && exit 23
    ;;
esac
STUB
cat > "$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ -n "${HERDR_HELPER_REAL_GIT:-}" ]; then
  exec "$HERDR_HELPER_REAL_GIT" "$@"
fi
if [ "$*" = "remote get-url origin" ]; then
  printf '%s\n' 'https://github.com/group/project.git'
  exit 0
fi
if [ -n "${AUTHORIZED_COMMIT_STUB_LOG:-}" ]; then
  case "$*" in
    "branch --show-current") printf '%s\n' feature; exit 0 ;;
    "diff --cached --binary --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/")
      printf '%s' 'helper staged diff'; exit 0 ;;
    "rev-parse HEAD")
      if [ -e "$AUTHORIZED_COMMIT_STUB_STATE" ]; then
        printf '%s\n' 2222222222222222222222222222222222222222
      else
        printf '%s\n' 1111111111111111111111111111111111111111
      fi
      exit 0
      ;;
    "commit --cleanup=verbatim -F "*)
      printf '%s|%s\n' "${HERDR_COMMIT_AUTHORIZATION:-}" "$*" >> "$AUTHORIZED_COMMIT_STUB_LOG"
      : > "$AUTHORIZED_COMMIT_STUB_STATE"
      exit 0
      ;;
    "diff --binary --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222")
      printf '%s' 'helper staged diff'; exit 0 ;;
  esac
  exit 1
fi
printf '%s|%s\n' "${HERDR_PUSH_AUTHORIZATION:-}" "$*" >> "$AUTHORIZED_PUSH_STUB_LOG"
STUB
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "${HERDR_PR_CREATE_AUTHORIZATION:-}" "$*" >> "$AUTHORIZED_PR_STUB_LOG"
STUB
chmod +x "$TMP/bin/herdr" "$TMP/bin/git" "$TMP/bin/gh"
HERDR_STUB_LOG="$TMP/herdr.log" HERDR_ENV=1 HERDR_ROLE=coder HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_DELIVERY_SETTLE_SECONDS=0 HERDR_DELIVERY_LOCK_DIR="$TMP/delivery-locks" \
  PATH="$TMP/bin:$PATH" bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  send_and_submit w1:p2 pm supervisor "[ACK] task=test"
  agent_pass w1:p2 tester supervisor task-test /tmp/task-test-results.md
  agent_changes_required w1:p2 reviewer supervisor task-test /tmp/task-test-review.md
'
printf '%s\n' 'task payload' > "$TMP/task.md"
HERDR_STUB_LOG="$TMP/herdr.log" HERDR_ENV=1 HERDR_ROLE=coder HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_SUBMIT_RETRY_DELAY_SECONDS=0 HERDR_DELIVERY_SETTLE_SECONDS=0 \
  HERDR_DELIVERY_LOCK_DIR="$TMP/delivery-locks" PATH="$TMP/bin:$PATH" \
  bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  HERDR_TASK_SUBMIT_RETRIES=1 send_file_and_submit \
    w1:p2 supervisor coder "$1" task-test
' bash "$TMP/task.md"
grep -q '^pane run w1:p2 \[ACK\] task=test$' "$TMP/herdr.log" \
  || fail "shared helper did not submit through pane run"
grep -q '^pane send-keys w1:p2 enter$' "$TMP/herdr.log" \
  || fail "shared helper did not send the explicit Enter safeguard"
test "$(grep -c '^pane send-keys w1:p2 enter$' "$TMP/herdr.log")" -eq 5 \
  || fail "task-file delivery did not use one bounded startup retry"
grep -q '^pane run w1:p2 \[PASS\] from: tester -> to: supervisor task=task-test evidence=/tmp/task-test-results.md$' \
  "$TMP/herdr.log" || fail "shared helper did not send one PASS verdict"
grep -q '^pane run w1:p2 \[CHANGES_REQUIRED\] from: reviewer -> to: supervisor task=task-test findings=/tmp/task-test-review.md$' \
  "$TMP/herdr.log" || fail "shared helper did not send one CHANGES_REQUIRED verdict"

if HERDR_ENV=1 HERDR_PANE_ID=w1:p2 HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_DELIVERY_SETTLE_SECONDS=0 HERDR_DELIVERY_LOCK_DIR="$TMP/self-delivery-locks" \
  PATH="$TMP/bin:$PATH" bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  send_and_submit w1:p2 pm supervisor "self-targeted message"
'; then
  fail "shared helper allowed an accidental self-target"
fi

if HERDR_ENV=1 HERDR_ROLE=coder HERDR_STUB_LOG="$TMP/herdr-run-failure.log" HERDR_STUB_FAIL_ON=run HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_DELIVERY_SETTLE_SECONDS=0 HERDR_DELIVERY_LOCK_DIR="$TMP/run-failure-locks" \
  PATH="$TMP/bin:$PATH" bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  send_and_submit w1:p2 pm supervisor "run failure"
'; then
  fail "shared helper masked pane run failure"
fi

if HERDR_ENV=1 HERDR_ROLE=coder HERDR_STUB_LOG="$TMP/herdr-submit-failure.log" HERDR_STUB_FAIL_ON=send-keys HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_DELIVERY_SETTLE_SECONDS=0 HERDR_DELIVERY_LOCK_DIR="$TMP/submit-failure-locks" \
  PATH="$TMP/bin:$PATH" bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  send_and_submit w1:p2 pm supervisor "submit failure"
'; then
  fail "shared helper masked send-keys failure"
fi

printf '%s\n' 'Revision: 1/2' 'Severity: BLOCKER' > "$TMP/revision-blocker.md"
printf '%s\n' 'Revision: 1/2' 'Severity: ADVISORY' > "$TMP/revision-advisory.md"
source .agents/skills/agent-shared/lib/agent-helpers.sh
agent_revision_gate 1 "$TMP/revision-blocker.md" \
  || fail "revision gate rejected a valid blocker-backed revision"
if agent_revision_gate 2 "$TMP/revision-blocker.md" >/dev/null 2>&1; then
  fail "revision gate accepted a mismatched revision marker"
fi
if agent_revision_gate 1 "$TMP/revision-advisory.md" >/dev/null 2>&1; then
  fail "revision gate allowed an advisory-only revision"
fi
if agent_revision_gate 3 "$TMP/revision-blocker.md" >/dev/null 2>&1; then
  fail "revision gate allowed Revision 3"
fi

TEST_PUSH_COMMIT=0123456789abcdef0123456789abcdef01234567
TEST_PUSH_TOKEN="APPROVE_PUSH"
AUTHORIZED_PUSH_STUB_LOG="$TMP/authorized-push.log" HERDR_ENV=1 \
  TEST_PUSH_COMMIT="$TEST_PUSH_COMMIT" TEST_PUSH_TOKEN="$TEST_PUSH_TOKEN" \
  PATH="$TMP/bin:$PATH" bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  agent_authorized_push feature "$TEST_PUSH_COMMIT" "$TEST_PUSH_TOKEN"
'
grep -Fqx "$TEST_PUSH_TOKEN|push origin feature" "$TMP/authorized-push.log" \
  || fail "agent_authorized_push did not bind the approval to one origin push"

printf '%s\n' 'Reviewed helper commit' > "$TMP/helper-commit-message.txt"
HELPER_DIFF_SHA="$(printf '%s' 'helper staged diff' | shasum -a 256 | awk '{print $1}')"
HELPER_MESSAGE_SHA="$(shasum -a 256 "$TMP/helper-commit-message.txt" | awk '{print $1}')"
HELPER_COMMIT_TOKEN="APPROVE_COMMIT"
AUTHORIZED_COMMIT_STUB_LOG="$TMP/authorized-commit.log" HERDR_ENV=1 \
  AUTHORIZED_COMMIT_STUB_STATE="$TMP/authorized-commit.state" \
  HELPER_DIFF_SHA="$HELPER_DIFF_SHA" HELPER_COMMIT_TOKEN="$HELPER_COMMIT_TOKEN" \
  HELPER_COMMIT_MESSAGE="$TMP/helper-commit-message.txt" PATH="$TMP/bin:$PATH" \
  bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  agent_authorized_commit feature "$HELPER_DIFF_SHA" \
    "$HELPER_COMMIT_MESSAGE" "$HELPER_COMMIT_TOKEN"
'
grep -Fq "$HELPER_COMMIT_TOKEN|commit --cleanup=verbatim -F $TMP/helper-commit-message.txt" \
  "$TMP/authorized-commit.log" \
  || fail "agent_authorized_commit did not bind the approval and message file"

printf '%s\n' 'PR body' > "$TMP/pr-body.md"
TEST_PR_TOKEN="APPROVE_PR_DEV"
AUTHORIZED_PR_STUB_LOG="$TMP/authorized-pr.log" HERDR_ENV=1 \
  TEST_PUSH_COMMIT="$TEST_PUSH_COMMIT" TEST_PR_TOKEN="$TEST_PR_TOKEN" \
  TEST_PR_BODY="$TMP/pr-body.md" PATH="$TMP/bin:$PATH" bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  agent_authorized_pr_create dev feature "$TEST_PUSH_COMMIT" "Test PR" "$TEST_PR_BODY" "$TEST_PR_TOKEN"
'
grep -Fqx "$TEST_PR_TOKEN|pr create --base dev --head feature --title Test PR --body-file $TMP/pr-body.md" \
  "$TMP/authorized-pr.log" \
  || fail "agent_authorized_pr_create did not bind the approval to one PR create"

"$REAL_GIT" init -q -b feature "$TMP/commit-review-repo"
printf '%s\n' initial > "$TMP/commit-review-repo/allowed.txt"
printf '%s\n' initial > "$TMP/commit-review-repo/disallowed.txt"
"$REAL_GIT" -C "$TMP/commit-review-repo" add allowed.txt disallowed.txt
"$REAL_GIT" -C "$TMP/commit-review-repo" -c user.name=Test -c user.email=test@example.com \
  commit -q -m initial
printf '%s\n' reviewed > "$TMP/commit-review-repo/allowed.txt"
printf '%s\n' not-reviewed > "$TMP/commit-review-repo/disallowed.txt"
printf '%s\n' 'Gate reviewed commit' > "$TMP/commit-message.txt"
HERDR_STUB_LOG="$TMP/commit-review-herdr.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_HELPER_REAL_GIT=/usr/bin/git HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_DELIVERY_SETTLE_SECONDS=0 \
  HERDR_DELIVERY_LOCK_DIR="$TMP/commit-review-locks" PATH="$TMP/bin:$PATH" \
  bash -c '
  cd "$1"
  source "$2/.agents/skills/agent-shared/lib/agent-helpers.sh"
  agent_prepare_verification_candidate w1:p2 coder supervisor task-commit \
    "$3" allowed.txt
' bash "$TMP/commit-review-repo" "$ROOT" "$TMP/verification-candidate.txt"
test "$("$REAL_GIT" -C "$TMP/commit-review-repo" diff --cached --name-only)" = allowed.txt \
  || fail "verification candidate staged a path outside Allowed files"
COMMIT_REVIEW_DIFF_SHA="$("$REAL_GIT" -C "$TMP/commit-review-repo" diff --cached \
  --binary --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ \
  | shasum -a 256 | awk '{print $1}')"
COMMIT_REVIEW_MESSAGE_SHA="$(shasum -a 256 "$TMP/commit-message.txt" | awk '{print $1}')"
grep -Fq "Candidate Diff SHA-256: $COMMIT_REVIEW_DIFF_SHA" \
  "$TMP/verification-candidate.txt" \
  || fail "verification artifact does not bind the staged diff"
grep -Fq '[READY_FOR_VERIFICATION]' "$TMP/commit-review-herdr.log" \
  || fail "candidate helper did not send the verification marker"
HERDR_ENV=1 HERDR_HELPER_REAL_GIT=/usr/bin/git PATH="$TMP/bin:$PATH" bash -c '
  cd "$1"
  source "$2/.agents/skills/agent-shared/lib/agent-helpers.sh"
  agent_verify_staged_diff "$3"
' bash "$TMP/commit-review-repo" "$ROOT" "$COMMIT_REVIEW_DIFF_SHA" \
  || fail "Verifier hash helper rejected the frozen candidate"
if HERDR_ENV=1 HERDR_HELPER_REAL_GIT=/usr/bin/git PATH="$TMP/bin:$PATH" bash -c '
  cd "$1"
  source "$2/.agents/skills/agent-shared/lib/agent-helpers.sh"
  agent_verify_staged_diff "$3"
' bash "$TMP/commit-review-repo" "$ROOT" \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  >/dev/null 2>&1; then
  fail "Verifier hash helper accepted a different candidate hash"
fi
HERDR_STUB_LOG="$TMP/commit-review-herdr.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_HELPER_REAL_GIT=/usr/bin/git HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_DELIVERY_SETTLE_SECONDS=0 \
  HERDR_DELIVERY_LOCK_DIR="$TMP/commit-review-locks" PATH="$TMP/bin:$PATH" \
  bash -c '
  cd "$1"
  source "$2/.agents/skills/agent-shared/lib/agent-helpers.sh"
  agent_prepare_commit_review w1:p2 coder supervisor task-commit \
    "$3" "$4" "$5" allowed.txt
' bash "$TMP/commit-review-repo" "$ROOT" "$COMMIT_REVIEW_DIFF_SHA" \
  "$TMP/commit-message.txt" "$TMP/commit-review.txt"
grep -Fq "Diff SHA-256: $COMMIT_REVIEW_DIFF_SHA" "$TMP/commit-review.txt" \
  || fail "commit review artifact does not bind the staged diff"
grep -Fq "Verified Diff SHA-256: $COMMIT_REVIEW_DIFF_SHA" "$TMP/commit-review.txt" \
  || fail "commit review artifact does not bind the verified diff"
grep -Fq "Message SHA-256: $COMMIT_REVIEW_MESSAGE_SHA" "$TMP/commit-review.txt" \
  || fail "commit review artifact does not bind the message"
grep -Fq '[AWAITING_HUMAN_COMMIT]' "$TMP/commit-review-herdr.log" \
  || fail "commit review helper did not send the Human wait marker"
printf '%s\n' drifted > "$TMP/commit-review-repo/allowed.txt"
if HERDR_STUB_LOG="$TMP/commit-review-drift.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_HELPER_REAL_GIT=/usr/bin/git HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_DELIVERY_SETTLE_SECONDS=0 \
  HERDR_DELIVERY_LOCK_DIR="$TMP/commit-review-drift-locks" \
  PATH="$TMP/bin:$PATH" bash -c '
  cd "$1"
  source "$2/.agents/skills/agent-shared/lib/agent-helpers.sh"
  agent_prepare_commit_review w1:p2 coder supervisor task-commit \
    "$3" "$4" "$5" allowed.txt
' bash "$TMP/commit-review-repo" "$ROOT" "$COMMIT_REVIEW_DIFF_SHA" \
  "$TMP/commit-message.txt" "$TMP/commit-review-drift.txt" >/dev/null 2>&1; then
  fail "commit review helper accepted Allowed-files drift after verification"
fi
"$REAL_GIT" -C "$TMP/commit-review-repo" restore --worktree -- allowed.txt
"$REAL_GIT" -C "$TMP/commit-review-repo" add disallowed.txt
if HERDR_STUB_LOG="$TMP/commit-review-reject.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_HELPER_REAL_GIT=/usr/bin/git HERDR_SUBMIT_DELAY_SECONDS=0 \
  HERDR_DELIVERY_SETTLE_SECONDS=0 \
  HERDR_DELIVERY_LOCK_DIR="$TMP/commit-review-reject-locks" \
  PATH="$TMP/bin:$PATH" bash -c '
  cd "$1"
  source "$2/.agents/skills/agent-shared/lib/agent-helpers.sh"
  agent_prepare_commit_review w1:p2 coder supervisor task-commit \
    "$3" "$4" "$5" allowed.txt
' bash "$TMP/commit-review-repo" "$ROOT" "$COMMIT_REVIEW_DIFF_SHA" \
  "$TMP/commit-message.txt" "$TMP/commit-review-rejected.txt" >/dev/null 2>&1; then
  fail "commit review helper accepted a staged path outside Allowed files"
fi
"$REAL_GIT" -C "$TMP/commit-review-repo" restore --staged -- disallowed.txt
"$REAL_GIT" -C "$TMP/commit-review-repo" config user.name Test
"$REAL_GIT" -C "$TMP/commit-review-repo" config user.email test@example.com
COMMIT_REVIEW_TOKEN="APPROVE_COMMIT"
HERDR_ENV=1 HERDR_ROLE=coder HERDR_HELPER_REAL_GIT=/usr/bin/git PATH="$TMP/bin:$PATH" bash -c '
  cd "$1"
  source "$2/.agents/skills/agent-shared/lib/agent-helpers.sh"
  agent_authorized_commit feature "$3" "$4" "$5"
' bash "$TMP/commit-review-repo" "$ROOT" "$COMMIT_REVIEW_DIFF_SHA" \
  "$TMP/commit-message.txt" "$COMMIT_REVIEW_TOKEN" \
  > "$TMP/commit-review-commit.log" \
  || fail "authorized commit failed its real staged-to-commit integrity check"
COMMIT_REVIEW_COMMIT="$("$REAL_GIT" -C "$TMP/commit-review-repo" rev-parse HEAD)"
test "$(tail -n 1 "$TMP/commit-review-commit.log")" = "$COMMIT_REVIEW_COMMIT" \
  || fail "authorized commit did not report the created commit SHA"

: > "$TMP/herdr-concurrent.log"
HERDR_STUB_LOG="$TMP/herdr-concurrent.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_SUBMIT_DELAY_SECONDS=0.2 HERDR_DELIVERY_SETTLE_SECONDS=0 \
  HERDR_DELIVERY_LOCK_INTERVAL_SECONDS=0.01 \
  HERDR_DELIVERY_LOCK_DIR="$TMP/concurrent-delivery-locks" \
  PATH="$TMP/bin:$PATH" bash -c '
  source .agents/skills/agent-shared/lib/agent-helpers.sh
  send_and_submit w1:p2 reviewer supervisor "review-result" &
  send_and_submit w1:p2 tester supervisor "test-result" &
  wait
'
python3 - "$TMP/herdr-concurrent.log" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected_pairs = {
    ("pane run w1:p2 review-result", "pane send-keys w1:p2 enter"),
    ("pane run w1:p2 test-result", "pane send-keys w1:p2 enter"),
}
if len(lines) != 4 or (lines[0], lines[1]) not in expected_pairs or (lines[2], lines[3]) not in expected_pairs:
    raise SystemExit(f"concurrent delivery interleaved: {lines}")
PY

mkdir -p "$TMP/home/.claude/agents" "$TMP/runtime-bin"
cp .agents/agents/orchestrator.md "$TMP/home/.claude/agents/herdr-orchestrator.md"
cat > "$TMP/runtime-bin/pi" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
cat > "$TMP/runtime-bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$RUNTIME_STUB_LOG"
STUB
chmod +x "$TMP/runtime-bin/pi" "$TMP/runtime-bin/claude"
if RUNTIME_STUB_LOG="$TMP/runtime.log" HERDR_ENV=1 HOME="$TMP/home" \
  PATH="$TMP/runtime-bin:$PATH" \
  bin/agent-runtime --role orchestrator --runtime auto --cwd "$ROOT" \
  --initial-prompt "no-fallback" >/dev/null 2>&1; then
  fail "fixed Pi Orchestrator silently fell back to Claude"
fi
[ ! -e "$TMP/runtime.log" ] \
  || fail "fixed Pi Orchestrator launched Claude as a fallback"

mkdir -p \
  "$TMP/team-home/.agents/agents" \
  "$TMP/team-home/.agents/guard-bin" \
  "$TMP/team-home/.agents/extensions" \
  "$TMP/team-home/.agents/protocols" \
  "$TMP/team-home/.claude/agents" \
  "$TMP/team-home/.claude/skills" \
  "$TMP/team-home/Workspaces/vault/daily" \
  "$TMP/team-home/Workspaces/vault/projects/smart_ai" \
  "$TMP/team-bin"
cp .agents/team.json "$TMP/team-home/.agents/team.json"
cp .agents/extensions/orchestrator-shutdown.ts \
  "$TMP/team-home/.agents/extensions/orchestrator-shutdown.ts"
cp .agents/extensions/auto-compact.ts \
  "$TMP/team-home/.agents/extensions/auto-compact.ts"
cp .agents/extensions/voice-notify.ts \
  "$TMP/team-home/.agents/extensions/voice-notify.ts"
cp .agents/protocols/communication.md \
  "$TMP/team-home/.agents/protocols/communication.md"
cp bin/guard-bin/git bin/guard-bin/gh bin/guard-bin/glab \
  "$TMP/team-home/.agents/guard-bin/"
chmod +x "$TMP/team-home/.agents/guard-bin/git" \
  "$TMP/team-home/.agents/guard-bin/gh" \
  "$TMP/team-home/.agents/guard-bin/glab"
cat > "$TMP/team-registry.yaml" <<'YAML'
workspace_root: /tmp/workspaces
projects:
  sample:
    name: sample
    path: /tmp/workspaces/sample
    description: Sample project
    status: active
YAML
for skill in herdr agent-team agent-shared; do
  mkdir -p "$TMP/team-home/.agents/skills/$skill"
  cp ".agents/skills/$skill/SKILL.md" \
    "$TMP/team-home/.agents/skills/$skill/SKILL.md"
  mkdir -p "$TMP/team-home/.claude/skills/$skill"
  cp ".agents/skills/$skill/SKILL.md" \
    "$TMP/team-home/.claude/skills/$skill/SKILL.md"
done
for role_file in .agents/agents/*.md; do
  role="$(basename "$role_file" .md)"
  cp "$role_file" "$TMP/team-home/.agents/agents/$role.md"
  cp "$role_file" "$TMP/team-home/.claude/agents/herdr-$role.md"
done
cp bin/herdr-team "$TMP/team-bin/herdr-team"
cp bin/validate-okf "$TMP/team-bin/validate-okf"
cp bin/voice-notify "$TMP/team-bin/voice-notify"
cat > "$TMP/team-bin/herdr" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "herdr test"
  exit 0
fi
printf '%s\n' "$*" >> "$TEAM_HERDR_LOG"
if [ "${1:-}" = "status" ] && [ "${2:-}" = "server" ]; then
  if [ "${TEAM_SERVER_RUNNING:-0}" = "1" ]; then
    echo "status: running"
  else
    echo "status: not running"
  fi
  exit 0
fi
if [ "${1:-}" = "agent" ] && [ "${2:-}" = "get" ]; then
  [ "${TEAM_ORCHESTRATOR_EXISTS:-0}" = "1" ]
  exit
fi
if [ "${1:-}" = "--session" ] && [ "${TEAM_SIMULATE_BOOTSTRAP:-0}" = "1" ]; then
  export HERDR_ENV=1
  export HERDR_PANE_ID=w-bootstrap:p1
  exec "$SHELL" -l
fi
if [ "${1:-}" = "pane" ] && [ "${2:-}" = "current" ]; then
  echo "w-default:p1"
  exit 0
fi
STUB
cat > "$TMP/team-bin/pi" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "pi test"
  exit 0
fi
printf '%s\n' "$*" > "$TEAM_PI_LOG"
STUB
cat > "$TMP/team-bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "claude test"
  exit 0
fi
printf '%s\n' "$*" > "$TEAM_CLAUDE_LOG"
STUB
cat > "$TMP/team-bin/agent-runtime" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEAM_RUNTIME_LOG"
printf 'voice=%s\n' "${HERDR_VOICE_MODE:-off}" >> "$TEAM_RUNTIME_LOG"
if [ "${TEAM_CREATE_SHUTDOWN_MARKER:-}" = "1" ]; then
  printf '%s\n' "${HERDR_PANE_ID:-}" > "$HERDR_SHUTDOWN_MARKER"
  if [ "${TEAM_CREATE_SHUTDOWN_SIGNAL:-}" = "1" ] \
    && [ -p "${HERDR_SHUTDOWN_SIGNAL:-}" ]; then
    printf '%s\n' "${HERDR_PANE_ID:-}" > "$HERDR_SHUTDOWN_SIGNAL"
  fi
fi
STUB
cat > "$TMP/team-bin/spawn-agent" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$TMP/team-bin/verify-pane-agent" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$TMP/team-bin/agent-team-shutdown" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$TMP/team-bin"/*
if [ "$(uname -s)" = "Darwin" ]; then
  mkdir -p "$TMP/team-home/.config/herdr"
  cat > "$TMP/team-home/.config/herdr/tts-thai.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$TMP/team-home/.config/herdr/tts-thai.sh"
  VOICE_TTS_CONFIG="$TMP/team-home/.config/herdr"
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=1 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_TTS_CONFIG" HOME="$TMP/team-home" \
    "$TMP/team-bin/voice-notify" summary 'ทดสอบ gTTS ค่ะ' >/dev/null
  grep -q 'tts:tts-thai\.sh .*\.config/herdr/tts-thai\.sh' "$VOICE_TTS_CONFIG/voice-notify.log" \
    || fail "voice helper did not select the project TTS adapter before say"

  VOICE_TEST_CONFIG="$TMP/voice-test-config"
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_TEST_CONFIG" \
    "$TMP/team-bin/voice-notify" summary \
    $'สวัสดีค่ะ ดิฉันคือ Orchestrator พร้อมช่วยคุณจัดการงานหลายโปรเจกต์ค่ะ\nดำเนินการเสร็จแล้วค่ะ' \
    >/dev/null
  if grep -q 'สวัสดี' "$VOICE_TEST_CONFIG/voice-notify.log"; then
    fail "voice summary repeated the startup greeting"
  fi
  grep -q 'ดำเนินการเสร็จแล้วค่ะ' "$VOICE_TEST_CONFIG/voice-notify.log" \
    || fail "voice summary did not preserve the actual outcome"
  if grep -Fq '*' "$VOICE_TEST_CONFIG/voice-notify.log"; then
    fail "voice summary preserved Markdown asterisks"
  fi
  if grep -q 'รายละเอียดทั้งหมด' "$VOICE_TEST_CONFIG/voice-notify.log"; then
    fail "voice summary read the full UI explanation"
  fi

  MARKDOWN_VOICE_CONFIG="$TMP/voice-test-markdown"
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$MARKDOWN_VOICE_CONFIG" \
    "$TMP/team-bin/voice-notify" summary \
    '**ดำเนินการเสร็จแล้วค่ะ**' >/dev/null
  grep -Fq 'summary: ดำเนินการเสร็จแล้วค่ะ' \
    "$MARKDOWN_VOICE_CONFIG/voice-notify.log" \
    || fail "voice summary did not remove Markdown emphasis"
  if grep -Fq '*' "$MARKDOWN_VOICE_CONFIG/voice-notify.log"; then
    fail "voice summary sent Markdown emphasis to TTS"
  fi

  REGISTRY_VOICE_CONFIG="$TMP/voice-test-registry"
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$REGISTRY_VOICE_CONFIG" \
    "$TMP/team-bin/voice-notify" summary \
    $'สวัสดีค่ะ ดิฉันคือ Orchestrator พร้อมช่วยคุณจัดการงานหลายโปรเจกต์ค่ะ\nดิฉันได้ตรวจสอบรายการโปรเจกต์ที่ลงทะเบียนไว้ใน Workspace Registry เรียบร้อยแล้วค่ะ มีทั้งหมด 10 โปรเจกต์ดังนี้:\n\n1. ap-bootcamp\n\nโปรดเลือกโปรเจกต์ที่ต้องการดำเนินการ พร้อมทั้งระบุประเภทคำร้องขอ' \
    >/dev/null
  grep -Fq 'summary: ตรวจสอบ Workspace Registry เรียบร้อยแล้วค่ะ พบ 10 โปรเจกต์ กรุณาเลือกโปรเจกต์ที่ต้องการเปิดค่ะ' \
    "$REGISTRY_VOICE_CONFIG/voice-notify.log" \
    || fail "voice summary did not normalize the Registry startup response"
  if grep -q 'ap-bootcamp' "$REGISTRY_VOICE_CONFIG/voice-notify.log"; then
    fail "Registry voice summary included the full UI project list"
  fi

  ACTION_VOICE_CONFIG="$TMP/voice-test-action"
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$ACTION_VOICE_CONFIG" \
    "$TMP/team-bin/voice-notify" summary \
    $'ตรวจสอบขอบเขตโปรเจกต์เรียบร้อยแล้วค่ะ\nกรุณายืนยันขอบเขตงานและสาขาที่ต้องการดำเนินการค่ะ\nรายละเอียดเพิ่มเติมยังอยู่ในแชตค่ะ' \
    >/dev/null
  grep -Fq 'summary: ตรวจสอบขอบเขตโปรเจกต์เรียบร้อยแล้วค่ะ กรุณายืนยันขอบเขตงานและสาขาที่ต้องการดำเนินการค่ะ' \
    "$ACTION_VOICE_CONFIG/voice-notify.log" \
    || fail "voice summary did not include the required Human action"

  LONG_VOICE_CONFIG="$TMP/voice-test-long"
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$LONG_VOICE_CONFIG" \
    "$TMP/team-bin/voice-notify" summary \
    'งานนี้เป็นข้อความยาวมากที่ไม่มีเครื่องหมายจบประโยคและไม่ควรถูกตัดกลางเสียงเพราะจะทำให้ผู้ใช้ได้ยินเหมือนระบบอ่านแชตแล้วถูกตัดทิ้งโดยไม่จบความหมายของประโยคและยังมีรายละเอียดต่อเนื่องอีกมากเพื่อจำลองผลลัพธ์ที่ยาวเกินไป' \
    >/dev/null
  grep -q 'สรุปผลการทำงานอยู่ในแชตค่ะ' "$LONG_VOICE_CONFIG/voice-notify.log" \
    || fail "voice summary cut a long unfinished sentence instead of using a complete fallback"

  VOICE_OWNER_CONFIG="$TMP/voice-owner-test"
  VOICE_OWNER_FILE="$VOICE_OWNER_CONFIG/active-owner"
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=orchestrator HERDR_PANE_ID=w1:p1 \
    "$TMP/team-bin/voice-notify" init >/dev/null
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=orchestrator HERDR_PANE_ID=w1:p1 \
    "$TMP/team-bin/voice-notify" summary 'orchestrator-owner-speaks' >/dev/null
  grep -q 'summary: orchestrator-owner-speaks' "$VOICE_OWNER_CONFIG/voice-notify.log" \
    || fail "voice owner did not initialize to Orchestrator"

  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w2:p1 \
    "$TMP/team-bin/voice-notify" claim 'ช่วยตรวจงานโปรเจกต์นี้' >/dev/null
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w2:p1 \
    "$TMP/team-bin/voice-notify" summary 'pm-owner-speaks' >/dev/null
  grep -q 'summary: pm-owner-speaks' "$VOICE_OWNER_CONFIG/voice-notify.log" \
    || fail "direct Human input did not transfer voice ownership to PM"

  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=orchestrator HERDR_PANE_ID=w1:p1 \
    "$TMP/team-bin/voice-notify" summary 'old-orchestrator-must-stay-silent' >/dev/null
  if grep -q 'summary: old-orchestrator-must-stay-silent' "$VOICE_OWNER_CONFIG/voice-notify.log"; then
    fail "previous voice owner still spoke after PM took ownership"
  fi

  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w2:p1 \
    "$TMP/team-bin/voice-notify" summary 'pm-without-human-turn-must-stay-silent' >/dev/null
  if grep -q 'summary: pm-without-human-turn-must-stay-silent' "$VOICE_OWNER_CONFIG/voice-notify.log"; then
    fail "PM repeated speech without a new direct Human turn"
  fi

  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w2:p1 \
    "$TMP/team-bin/voice-notify" claim \
    '[ACK] from: coder -> to: pm task=test' >/dev/null
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w2:p1 \
    "$TMP/team-bin/voice-notify" summary 'agent-protocol-must-stay-silent' >/dev/null
  if grep -q 'summary: agent-protocol-must-stay-silent' "$VOICE_OWNER_CONFIG/voice-notify.log"; then
    fail "agent-to-agent protocol traffic produced PM speech"
  fi

  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w2:p1 \
    "$TMP/team-bin/voice-notify" claim \
    '[DONE] from: coder -> to: pm task=test' >/dev/null
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w2:p1 \
    "$TMP/team-bin/voice-notify" summary 'owner-pm-relays-worker-result' >/dev/null
  grep -q 'summary: owner-pm-relays-worker-result' "$VOICE_OWNER_CONFIG/voice-notify.log" \
    || fail "owner PM stayed silent when relaying a worker result to the Human"
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w9:p1 \
    "$TMP/team-bin/voice-notify" claim \
    '[STUCK] from: coder -> to: pm task=test' >/dev/null
  grep -qx 'pm:w2:p1' "$VOICE_OWNER_FILE" \
    || fail "worker result moved voice ownership to a background PM"

  printf '%s' '{"prompt":"คุยกับ PM โปรเจกต์ที่สอง"}' | \
    HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w3:p1 \
    "$TMP/team-bin/voice-notify" claim >/dev/null
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=pm HERDR_PANE_ID=w3:p1 \
    "$TMP/team-bin/voice-notify" summary 'second-pm-owner-speaks' >/dev/null
  grep -q 'summary: second-pm-owner-speaks' "$VOICE_OWNER_CONFIG/voice-notify.log" \
    || fail "Claude-style hook input did not transfer ownership to the second PM"

  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=orchestrator HERDR_PANE_ID=w1:p1 \
    "$TMP/team-bin/voice-notify" claim 'กลับมาจัดการระบบส่วนกลาง' >/dev/null
  HERDR_VOICE_NOTIFY=1 HERDR_VOICE_SOUND=0 HERDR_VOICE_SPEECH=0 \
    HERDR_VOICE_CONFIG_DIR="$VOICE_OWNER_CONFIG" \
    HERDR_VOICE_OWNER_FILE="$VOICE_OWNER_FILE" \
    HERDR_AGENT_ROLE=orchestrator HERDR_PANE_ID=w1:p1 \
    "$TMP/team-bin/voice-notify" summary 'orchestrator-reclaims-voice' >/dev/null
  grep -q 'summary: orchestrator-reclaims-voice' "$VOICE_OWNER_CONFIG/voice-notify.log" \
    || fail "direct Human input did not return voice ownership to Orchestrator"
fi
HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" check --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --runtime auto \
  > "$TMP/team-check.log"
grep -q 'Pi healthy; auto will select Pi' "$TMP/team-check.log" \
  || fail "herdr-team check did not prefer healthy Pi"
if HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" check --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --model forbidden >/dev/null 2>&1; then
  fail "herdr-team accepted an Orchestrator model override"
fi
HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" check --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --runtime pi \
  --model antigravity/gemini-3.8-flash >/dev/null \
  || fail "herdr-team rejected the allowlisted Orchestrator model override"
if HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" check --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --voice maybe >/dev/null 2>&1; then
  fail "herdr-team accepted an invalid voice mode"
fi
if HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" check --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --runtime claude >/dev/null 2>&1; then
  fail "herdr-team accepted an Orchestrator runtime override"
fi

: > "$TMP/team-herdr-running.log"
TEAM_HERDR_LOG="$TMP/team-herdr-running.log" \
  TEAM_RUNTIME_LOG="$TMP/team-runtime-running.log" \
  TEAM_SERVER_RUNNING=1 TEAM_ORCHESTRATOR_EXISTS=0 \
  HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --session team-test >/dev/null
grep -q '^status server$' "$TMP/team-herdr-running.log" \
  || fail "herdr-team did not inspect its dedicated session"
grep -q '^agent get orchestrator$' "$TMP/team-herdr-running.log" \
  || fail "herdr-team did not check for an existing Orchestrator"
grep -q '^agent start orchestrator --cwd .* --focus -- .*herdr-team start ' \
  "$TMP/team-herdr-running.log" \
  || fail "herdr-team did not start a missing Orchestrator"
grep -q -- '--voice off' "$TMP/team-herdr-running.log" \
  || fail "herdr-team did not propagate the default voice-off mode"
grep -q '^--session team-test$' "$TMP/team-herdr-running.log" \
  || fail "herdr-team did not attach its dedicated session"

: > "$TMP/team-herdr-reuse.log"
TEAM_HERDR_LOG="$TMP/team-herdr-reuse.log" \
  TEAM_RUNTIME_LOG="$TMP/team-runtime-reuse.log" \
  TEAM_SERVER_RUNNING=1 TEAM_ORCHESTRATOR_EXISTS=1 \
  HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --session team-test >/dev/null
grep -q '^agent focus orchestrator$' "$TMP/team-herdr-reuse.log" \
  || fail "herdr-team did not focus the existing Orchestrator"
if grep -q '^agent start orchestrator ' "$TMP/team-herdr-reuse.log"; then
  fail "herdr-team started a duplicate Orchestrator"
fi

: > "$TMP/team-herdr-bootstrap.log"
TEAM_HERDR_LOG="$TMP/team-herdr-bootstrap.log" \
  TEAM_RUNTIME_LOG="$TMP/team-runtime-bootstrap.log" \
  TEAM_SERVER_RUNNING=0 TEAM_SIMULATE_BOOTSTRAP=1 \
  HERDR_TEAM_STATE_DIR="$TMP/team-bootstrap-state" \
  HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --session team-fresh >/dev/null
grep -q '^--session team-fresh$' "$TMP/team-herdr-bootstrap.log" \
  || fail "herdr-team did not open a fresh dedicated session"
grep -q '^pane rename w-bootstrap:p1 orchestrator$' \
  "$TMP/team-herdr-bootstrap.log" \
  || fail "fresh Herdr session did not bootstrap the Orchestrator pane"
grep -q '^--role orchestrator --runtime auto --label orchestrator --cwd ' \
  "$TMP/team-runtime-bootstrap.log" \
  || fail "fresh Herdr session did not launch the global Orchestrator"
grep -q '^voice=off$' "$TMP/team-runtime-bootstrap.log" \
  || fail "fresh Herdr startup did not default voice to off"
if grep -q '^server stop$' "$TMP/team-herdr-bootstrap.log"; then
  fail "fresh Herdr startup executed a server stop embedded in the initial prompt"
fi

TEAM_HERDR_LOG="$TMP/team-herdr.log" TEAM_RUNTIME_LOG="$TMP/team-runtime.log" \
  HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --runtime pi \
  --model antigravity/gemini-3.8-flash --voice on >/dev/null
grep -q '^pane rename w1:p1 orchestrator$' "$TMP/team-herdr.log" \
  || fail "herdr-team did not label the Orchestrator pane"
grep -q '^--role orchestrator --runtime pi --label orchestrator --cwd ' \
  "$TMP/team-runtime.log" \
  || fail "herdr-team did not launch the global Orchestrator"
grep -q -- '--model antigravity/gemini-3.8-flash' \
  "$TMP/team-runtime.log" \
  || fail "herdr-team did not forward the Orchestrator model override"
grep -q '^voice=on$' "$TMP/team-runtime.log" \
  || fail "herdr-team did not forward --voice on to the Orchestrator"
grep -q -- '--initial-prompt' "$TMP/team-runtime.log" \
  || fail "herdr-team did not supply an initial prompt"
grep -q "$TMP/team-registry.yaml" "$TMP/team-runtime.log" \
  || fail "herdr-team did not supply the workspace registry path"
grep -q "$TMP/team-home/Workspaces/vault" "$TMP/team-runtime.log" \
  || fail "herdr-team did not supply the vault path"
grep -q "$TMP/team-home/Workspaces/vault/log.md" "$TMP/team-runtime.log" \
  || fail "herdr-team did not supply the OKF activity-log path"
grep -q 'Human project selection is the bootstrap gate' "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt lacks the project-selection bootstrap gate"
grep -q 'ap-bootcamp becomes ap_bootcamp' "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt lacks runtime slug normalization"
grep -q 'สวัสดีค่ะ ดิฉันคือ Orchestrator' "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt lacks the Thai welcome"
grep -q 'do not use ผม or ครับ' "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt lacks feminine Thai language guidance"
grep -q 'Use English for every message exchanged with PM' \
  "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt lacks the English inter-agent policy"
grep -q 'PM owns project discovery, task classification, and scope confirmation after handoff' \
  "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt may still allow Orchestrator project discovery"
grep -q 'continue in the exact `pm-{project}` pane' "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt lacks the direct PM handoff"
grep -q 'stop the turn' "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt may leave Orchestrator working"
grep -q 'drain, optimize, edit, reorder' "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt may still drain queued Human prompts"
grep -q "Human-facing Pi command '/shutdown'" \
  "$TMP/team-runtime.log" \
  || fail "herdr-team initial prompt lacks the shutdown protocol"
if grep -q '^server stop$' "$TMP/team-herdr.log"; then
  fail "normal Herdr startup executed a server stop embedded in the initial prompt"
fi

: > "$TMP/team-close.log"
TEAM_HERDR_LOG="$TMP/team-close.log" \
  TEAM_RUNTIME_LOG="$TMP/team-close-runtime.log" \
  TEAM_CREATE_SHUTDOWN_MARKER=1 TEAM_SIMULATE_BOOTSTRAP=1 \
  TEAM_CREATE_SHUTDOWN_SIGNAL=1 \
  HERDR_SUBMIT_DELAY_SECONDS=0 \
  TEAM_SERVER_RUNNING=0 HERDR_TEAM_STATE_DIR="$TMP/team-state" \
  HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --session team-shutdown >/dev/null
sleep 1
grep -q '^pane run w-bootstrap:p1 /quit$' "$TMP/team-close.log" \
  || fail "detached finalizer did not queue Orchestrator /quit"
grep -q '^pane send-keys w-bootstrap:p1 enter$' "$TMP/team-close.log" \
  || fail "detached finalizer did not submit the Enter safeguard"
grep -q '^server stop$' "$TMP/team-close.log" \
  || fail "detached finalizer did not stop the Herdr server externally"
test "$(grep -c '^server stop$' "$TMP/team-close.log")" = 1 \
  || fail "shutdown issued more than one Herdr server stop"
test "$(tail -n 1 "$TMP/team-close.log")" = 'server stop' \
  || fail "detached finalizer did not make Herdr server stop the final command"
grep -q 'Shutdown handoff received for pane w-bootstrap:p1' \
  "$TMP/team-state/team-shutdown.shutdown-finalizer.log" \
  || fail "detached shutdown finalizer did not receive the shutdown signal"

mkdir -p "$TMP/team-stale-state/team-stale.shutdown-finalizer"
printf '%s\n' 999999 > \
  "$TMP/team-stale-state/team-stale.shutdown-finalizer/pid"
mkfifo "$TMP/team-stale-state/team-stale.shutdown-signal"
: > "$TMP/team-stale.log"
TEAM_HERDR_LOG="$TMP/team-stale.log" \
  TEAM_RUNTIME_LOG="$TMP/team-stale-runtime.log" \
  TEAM_CREATE_SHUTDOWN_MARKER=1 TEAM_SIMULATE_BOOTSTRAP=1 \
  TEAM_CREATE_SHUTDOWN_SIGNAL=1 HERDR_SUBMIT_DELAY_SECONDS=0 \
  TEAM_SERVER_RUNNING=0 HERDR_TEAM_STATE_DIR="$TMP/team-stale-state" \
  HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --session team-stale >/dev/null
sleep 1
test "$(grep -c '^server stop$' "$TMP/team-stale.log")" = 1 \
  || fail "shutdown did not replace a stale finalizer and stop Herdr once"
grep -q 'Shutdown handoff received for pane w-bootstrap:p1' \
  "$TMP/team-stale-state/team-stale.shutdown-finalizer.log" \
  || fail "replacement shutdown finalizer did not receive the handoff"

: > "$TMP/team-pane-runtime.log"
TEAM_HERDR_LOG="$TMP/team-pane-runtime.log" \
  TEAM_RUNTIME_LOG="$TMP/team-pane-runtime-runtime.log" \
  TEAM_CREATE_SHUTDOWN_MARKER=1 HERDR_TEAM_STATE_DIR="$TMP/team-pane-state" \
  HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  "$TMP/team-bin/herdr-team" --cwd "$ROOT" \
  --registry "$TMP/team-registry.yaml" --runtime auto >/dev/null
if grep -q '^pane close ' "$TMP/team-pane-runtime.log"; then
  fail "Orchestrator pane runtime closed its own pane"
fi
if grep -q '^server stop$' "$TMP/team-pane-runtime.log"; then
  fail "Orchestrator pane runtime stopped the Herdr server itself"
fi

: > "$TMP/shutdown.log"
mkfifo "$TMP/shutdown.signal"
cat "$TMP/shutdown.signal" > "$TMP/shutdown.signal.received" &
shutdown_reader_pid=$!
HERDR_STUB_LOG="$TMP/shutdown.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_SHUTDOWN_MARKER="$TMP/shutdown.marker" \
  HERDR_SHUTDOWN_SIGNAL="$TMP/shutdown.signal" \
  HERDR_AGENT_ROLE=orchestrator HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p1 \
  PATH="$TMP/bin:$PATH" bin/agent-team-shutdown --workspace w2 --workspace w3 \
  >/dev/null
wait "$shutdown_reader_pid"
grep -q '^workspace get w2$' "$TMP/shutdown.log" \
  || fail "shutdown did not validate project workspace w2"
grep -q '^workspace close w2$' "$TMP/shutdown.log" \
  || fail "shutdown did not close project workspace w2"
grep -q '^workspace close w3$' "$TMP/shutdown.log" \
  || fail "shutdown did not close project workspace w3"
if grep -q '^pane run ' "$TMP/shutdown.log"; then
  fail "in-pane shutdown helper queued /quit before completing its handoff"
fi
[ "$(cat "$TMP/shutdown.signal.received")" = "w1:p1" ] \
  || fail "shutdown did not hand the Orchestrator pane to the finalizer"
[ "$(cat "$TMP/shutdown.marker")" = "w1:p1" ] \
  || fail "shutdown did not mark the Orchestrator pane for launcher cleanup"
: > "$TMP/shutdown-empty.log"
mkfifo "$TMP/shutdown-empty.signal"
cat "$TMP/shutdown-empty.signal" > "$TMP/shutdown-empty.signal.received" &
shutdown_empty_reader_pid=$!
HERDR_STUB_LOG="$TMP/shutdown-empty.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_SHUTDOWN_MARKER="$TMP/shutdown-empty.marker" \
  HERDR_SHUTDOWN_SIGNAL="$TMP/shutdown-empty.signal" \
  HERDR_AGENT_ROLE=orchestrator HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p1 \
  PATH="$TMP/bin:$PATH" bin/agent-team-shutdown >/dev/null
wait "$shutdown_empty_reader_pid"
if grep -q '^workspace close ' "$TMP/shutdown-empty.log"; then
  fail "shutdown without project workspaces closed a workspace"
fi
[ "$(cat "$TMP/shutdown-empty.signal.received")" = "w1:p1" ] \
  || fail "shutdown without project workspaces did not hand off the pane"
[ "$(cat "$TMP/shutdown-empty.marker")" = "w1:p1" ] \
  || fail "shutdown without project workspaces did not mark the Orchestrator pane"
if HERDR_STUB_LOG="$TMP/shutdown-no-finalizer.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_SHUTDOWN_MARKER="$TMP/shutdown-no-finalizer.marker" \
  HERDR_AGENT_ROLE=orchestrator HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p1 \
  PATH="$TMP/bin:$PATH" bin/agent-team-shutdown >/dev/null 2>&1; then
  fail "shutdown succeeded without a detached finalizer"
fi
[ ! -e "$TMP/shutdown-no-finalizer.marker" ] \
  || fail "failed shutdown left a stale launcher marker"
mkfifo "$TMP/shutdown-dead-finalizer.signal"
if HERDR_STUB_LOG="$TMP/shutdown-dead-finalizer.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_SHUTDOWN_MARKER="$TMP/shutdown-dead-finalizer.marker" \
  HERDR_SHUTDOWN_SIGNAL="$TMP/shutdown-dead-finalizer.signal" \
  HERDR_AGENT_ROLE=orchestrator HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p1 \
  PATH="$TMP/bin:$PATH" bin/agent-team-shutdown >/dev/null 2>&1; then
  fail "shutdown succeeded with a FIFO that had no live finalizer reader"
fi
[ ! -e "$TMP/shutdown-dead-finalizer.marker" ] \
  || fail "dead-finalizer shutdown left a stale launcher marker"
if HERDR_STUB_LOG="$TMP/shutdown.log" HERDR_ENV=1 HERDR_ROLE=coder \
  HERDR_SHUTDOWN_MARKER="$TMP/shutdown.marker" \
  HERDR_AGENT_ROLE=orchestrator HERDR_WORKSPACE_ID=w1 HERDR_PANE_ID=w1:p1 \
  PATH="$TMP/bin:$PATH" bin/agent-team-shutdown --workspace w1 \
  >/dev/null 2>&1; then
  fail "shutdown allowed the global Orchestrator workspace to close"
fi

TEAM_PI_LOG="$TMP/team-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role orchestrator --runtime pi --cwd "$ROOT" \
  --initial-prompt "startup-test-pi" >/dev/null 2>&1
grep -q 'startup-test-pi' "$TMP/team-pi.log" \
  || fail "Pi did not receive the initial prompt"
grep -q -- '--system-prompt' "$TMP/team-pi.log" \
  || fail "Pi controller did not replace the coding system prompt"
grep -q -- '--exclude-tools edit,write' "$TMP/team-pi.log" \
  || fail "Pi controller lacks denied coding tools"
grep -q -- '--model antigravity/gemini-3.8-flash' \
  "$TMP/team-pi.log" \
  || fail "Pi Orchestrator did not receive its canonical role model"
grep -q -- '--extension .*auto-compact.ts' "$TMP/team-pi.log" \
  || fail "Pi Orchestrator did not load the auto-compact extension"
grep -q -- '--extension .*voice-notify.ts' "$TMP/team-pi.log" \
  || fail "Pi Orchestrator did not load the voice notification extension"
grep -q -- '--extension .*orchestrator-shutdown.ts' "$TMP/team-pi.log" \
  || fail "Pi Orchestrator did not load the shutdown extension"

TEAM_PI_LOG="$TMP/team-documenter-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role documenter --runtime pi \
  --model antigravity/gemini-3.8-flash --controller-role pm \
  --task-class document --task-tier standard --cwd "$ROOT" >/dev/null 2>&1
grep -q -- '--append-system-prompt' "$TMP/team-documenter-pi.log" \
  || fail "Documenter document mode did not receive write-capable tools"
if grep -q -- '--exclude-tools edit,write' "$TMP/team-documenter-pi.log"; then
  fail "Documenter document mode incorrectly lost write-capable tools"
fi
grep -q -- '--extension .*auto-compact.ts' "$TMP/team-documenter-pi.log" \
  || fail "Pi Documenter did not load the auto-compact extension"
if grep -q -- '--extension .*voice-notify.ts' "$TMP/team-documenter-pi.log"; then
  fail "non-Human-facing Pi role loaded the voice notification extension"
fi
if grep -q -- 'orchestrator-shutdown.ts' "$TMP/team-documenter-pi.log"; then
  fail "non-Orchestrator Pi role loaded the shutdown extension"
fi
grep -q -- 'task_class=document' "$TMP/team-documenter-pi.log" \
  || fail "Documenter document mode did not receive the task class policy"
grep -q -- '--model antigravity/gemini-3.8-flash' "$TMP/team-documenter-pi.log" \
  && grep -q -- 'routing_resolution=primary' "$TMP/team-documenter-pi.log" \
  || fail "Documenter standard tier did not use its configured primary"

TEAM_PI_LOG="$TMP/team-investigator-vault-pi.log" HERDR_ENV=1 \
  HOME="$TMP/team-home" \
  HERDR_TEAM_VAULT_PATH="$TMP/team-home/Workspaces/vault" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role investigator --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --controller-role pm \
  --task-class investigation --knowledge-source vault \
  --vault-read-scope projects/smart_ai --task-tier standard \
  --cwd "$ROOT" >/dev/null 2>&1
TEAM_VAULT_SCOPE="$(cd "$TMP/team-home/Workspaces/vault/projects/smart_ai" && pwd -P)"
grep -q -- 'knowledge_source=vault' "$TMP/team-investigator-vault-pi.log" \
  && grep -q -- "vault_read_scope=$TEAM_VAULT_SCOPE" \
    "$TMP/team-investigator-vault-pi.log" \
  && grep -q -- 'may_vault_read=true' "$TMP/team-investigator-vault-pi.log" \
  || fail "Investigator did not receive the resolved scoped vault policy"
if HERDR_ENV=1 HOME="$TMP/team-home" \
  HERDR_TEAM_VAULT_PATH="$TMP/team-home/Workspaces/vault" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role investigator --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --controller-role pm \
  --task-class investigation --knowledge-source vault --vault-read-scope . \
  --task-tier standard --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted the entire vault as a retrieval scope"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" \
  HERDR_TEAM_VAULT_PATH="$TMP/team-home/Workspaces/vault" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role researcher --runtime pi \
  --model antigravity/gemini-3.8-flash --controller-role pm \
  --task-class investigation --knowledge-source vault \
  --vault-read-scope projects/smart_ai --task-tier standard \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime allowed a non-Investigator vault retrieval"
fi

TEAM_PI_LOG="$TMP/team-pm-document-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role pm --runtime pi \
  --controller-role orchestrator \
  --task-class document --cwd "$ROOT" >/dev/null 2>&1
grep -q -- '--exclude-tools edit,write' "$TMP/team-pm-document-pi.log" \
  || fail "PM document task retained write-capable tools"

TEAM_PI_LOG="$TMP/team-pm-readonly-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role pm --runtime pi \
  --controller-role orchestrator \
  --task-class feature --cwd "$ROOT" >/dev/null 2>&1
grep -q -- '--exclude-tools edit,write' "$TMP/team-pm-readonly-pi.log" \
  || fail "PM retained write-capable tools outside document mode"
grep -q -- '--extension .*voice-notify.ts' "$TMP/team-pm-readonly-pi.log" \
  || fail "Pi PM did not load the voice ownership extension"

if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role pm --runtime pi --model opencode-go/deepseek-v4.1-flash \
  --controller-role orchestrator --task-class feature --task-tier standard \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted task-tier routing for fixed PM"
fi
TEAM_PI_LOG="$TMP/team-pm-fixed-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role pm --controller-role orchestrator \
  --task-class feature --cwd "$ROOT" >/dev/null 2>&1
grep -q -- '--model antigravity/gemini-3.8-flash' "$TMP/team-pm-fixed-pi.log" \
  || fail "fixed PM did not resolve its sole configured pair"
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role pm --runtime pi --model alibaba-token-intl/qwen3.8-max \
  --controller-role orchestrator --task-class feature --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted an unlisted model override for fixed PM"
fi

TEAM_PI_LOG="$TMP/team-pm-delivery-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role pm --runtime pi \
  --controller-role orchestrator \
  --task-class delivery --cwd "$ROOT" >/dev/null 2>&1
grep -q -- '--exclude-tools edit,write' "$TMP/team-pm-delivery-pi.log" \
  || fail "PM delivery task retained write-capable tools"
grep -q -- 'task_class=delivery' "$TMP/team-pm-delivery-pi.log" \
  || fail "PM delivery task class was not forwarded"

TEAM_PI_LOG="$TMP/team-supervisor-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role supervisor --controller-role pm --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard --cwd "$ROOT" >/dev/null 2>&1
grep -q -- '--exclude-tools edit,write' "$TMP/team-supervisor-pi.log" \
  && grep -q -- 'may_local_commit=true' "$TMP/team-supervisor-pi.log" \
  && grep -q -- 'may_authorized_push=true' "$TMP/team-supervisor-pi.log" \
  && grep -q -- 'may_authorized_pr_create=true' "$TMP/team-supervisor-pi.log" \
  || fail "Supervisor did not retain read-only tools with token-gated Git capabilities"
TEAM_PI_LOG="$TMP/team-supervisor-auto-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role supervisor --controller-role pm --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard \
  --commit-mode auto --cwd "$ROOT" >/dev/null 2>&1
grep -q -- 'commit_mode=auto' "$TMP/team-supervisor-auto-pi.log" \
  || fail "agent-runtime did not allow Supervisor's approved auto commit mode"
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role pm --controller-role orchestrator \
  --commit-mode auto --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime allowed auto commit for PM"
fi

TEAM_PI_LOG="$TMP/team-coder-pi.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard --cwd "$ROOT" >/dev/null 2>&1
grep -q -- '--append-system-prompt' "$TMP/team-coder-pi.log" \
  || fail "Coder did not retain the coding system prompt"
grep -q -- '--model opencode-go/deepseek-v4.1-flash' "$TMP/team-coder-pi.log" \
  || fail "Pi Coder did not receive its canonical role model"
if grep -q -- '--exclude-tools edit,write' "$TMP/team-coder-pi.log"; then
  fail "Coder incorrectly lost coding tools"
fi

TEAM_CLAUDE_LOG="$TMP/team-refactor-claude.log" HERDR_ENV=1 \
  HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role refactor --runtime claude --model opus --task-tier critical \
  --cwd "$ROOT" >/dev/null 2>&1
grep -q 'Runtime-enforced role policy:' "$TMP/team-refactor-claude.log" \
  || fail "Claude write-mode role did not receive the runtime policy prompt"

TEAM_CLAUDE_LOG="$TMP/team-reviewer-claude.log" HERDR_VOICE_MODE=on HERDR_ENV=1 \
  HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role reviewer --runtime claude --model opus --task-tier critical \
  --cwd "$ROOT" \
  >/dev/null 2>&1
grep -q -- '--model opus' "$TMP/team-reviewer-claude.log" \
  || fail "Claude Reviewer did not receive its controller-selected model"
if [ "$(uname -s)" = "Darwin" ]; then
  if grep -q 'PermissionRequest\|Stop' "$TMP/team-reviewer-claude.log"; then
    fail "Claude Reviewer received Human-facing controller voice hooks"
  fi
fi

TEAM_CLAUDE_LOG="$TMP/team-designer-claude.log" HERDR_ENV=1 \
  HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role designer --controller-role pm --cwd "$ROOT" \
  >/dev/null 2>&1
grep -q -- '--model opus' "$TMP/team-designer-claude.log" \
  || fail "fixed Designer did not resolve Claude Opus"
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role designer --controller-role supervisor --cwd "$ROOT" \
  >/dev/null 2>&1; then
  fail "agent-runtime allowed a non-PM controller to launch fixed Designer"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role designer --controller-role pm --task-tier standard \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted task-tier routing for fixed Designer"
fi

add_test_alternates "$TMP/team-home/.agents/team.json"
python3 - "$TMP/team-home/.agents/team.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
team = json.loads(path.read_text())
# Fixed PM must keep an enabled default while its shipped provider is disabled.
team["roles"]["pm"]["models"] = {"claude": ["sonnet"]}
team["roles"]["pm"]["default_model"] = "sonnet"
# Disable OpenCode Go, and strip the coder's other alternates, so the coder case
# below has no enabled alternate at all; the supervisor keeps its Claude
# alternate and still fails over.
team["disabled_model_providers"] = ["opencode-go"]
team["roles"]["coder"]["routing"]["standard"]["alternates"] = [
    route for route in team["roles"]["coder"]["routing"]["standard"]["alternates"]
    if route["model"] != "antigravity/gemini-3.8-flash"
]
path.write_text(json.dumps(team, indent=2) + "\n")
PY

TEAM_CLAUDE_LOG="$TMP/team-supervisor-failover-claude.log" \
  HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
bin/agent-runtime --role supervisor --controller-role pm --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard \
  --cwd "$ROOT" >/dev/null 2>"$TMP/team-supervisor-failover.err"
grep -q -- '--model sonnet' "$TMP/team-supervisor-failover-claude.log" \
  && grep -q -- 'routing_resolution=disabled-primary-failover' \
    "$TMP/team-supervisor-failover-claude.log" \
  || fail "agent-runtime did not use the first enabled alternate for a disabled primary"
grep -q -- 'routing failover role=supervisor tier=standard' \
  "$TMP/team-supervisor-failover.err" \
  || fail "agent-runtime did not report the disabled-primary failover"
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --controller-role pm --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard --cwd "$ROOT" \
  >/dev/null 2>"$TMP/team-supervisor-no-enabled-alternate.err"; then
  fail "agent-runtime launched a disabled primary without an enabled alternate"
fi
grep -q -- 'no enabled alternate for disabled primary: coder/standard' \
  "$TMP/team-supervisor-no-enabled-alternate.err" \
  || fail "agent-runtime did not explain the unavailable disabled-primary route"

for coder_route in \
  'standard opencode-go/step-5-preview'; do
  coder_tier="${coder_route%% *}"
  coder_model="${coder_route#* }"
  if TEAM_PI_LOG="$TMP/team-coder-pi-${coder_tier}.log" \
    HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
    bin/agent-runtime --role coder --runtime pi --model "$coder_model" \
    --task-tier "$coder_tier" --routing-exception --cwd "$ROOT" \
    >/dev/null 2>"$TMP/team-coder-pi-${coder_tier}.err"; then
    fail "agent-runtime accepted disabled OpenCode Go provider: $coder_tier/$coder_model"
  fi
  grep -q 'model provider is disabled: opencode-go' \
    "$TMP/team-coder-pi-${coder_tier}.err" \
    || fail "agent-runtime did not explain the disabled OpenCode Go provider"
done

python3 - "$TMP/team-home/.agents/team.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
team = json.loads(path.read_text())
team["disabled_model_providers"] = []
path.write_text(json.dumps(team, indent=2) + "\n")
PY
TEAM_PI_LOG="$TMP/team-coder-pi-reenabled.log" \
  HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime pi \
  --model opencode-go/step-5-preview \
  --task-tier standard --routing-exception --cwd "$ROOT" >/dev/null 2>&1 \
  || fail "agent-runtime did not re-enable OpenCode Go after clearing disabled_model_providers"
grep -q -- '--model opencode-go/step-5-preview' "$TMP/team-coder-pi-reenabled.log" \
  || fail "Pi Coder did not receive the re-enabled OpenCode Go model"
cp .agents/team.json "$TMP/team-home/.agents/team.json"
add_test_alternates "$TMP/team-home/.agents/team.json"

if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime auto \
  --model alibaba-token-intl/deepseek-v4.1-flash-1017 --task-tier standard --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted auto for a controller-selected role"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime pi --task-tier standard \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted a missing controller-selected model"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime pi --model opencode-go/deepseek-v4.1-flash \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted a controller-selected role without a task tier"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime pi \
  --model opencode-go/step-5-preview --task-tier standard \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted an alternate without --routing-exception"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role reviewer --runtime pi \
  --model antigravity/gemini-3.8-flash --task-tier critical --routing-exception \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted an allowlisted model that is not a configured alternate"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime pi --model opencode-go/deepseek-v4.1-flash \
  --task-tier standard --routing-exception --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted --routing-exception for a primary model"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime claude --model sonnet \
  --task-tier standard --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted an unlisted Coder Claude model"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role designer --runtime pi --model opus \
  --task-tier standard --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted a model from another runtime allowlist"
fi
TEAM_PI_LOG="$TMP/team-orchestrator-explicit.log" HERDR_ENV=1 HOME="$TMP/team-home" \
  PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role orchestrator --runtime pi \
  --model antigravity/gemini-3.8-flash \
  --cwd "$ROOT" >/dev/null 2>&1 \
  || fail "agent-runtime rejected the allowlisted fixed-role model override"
grep -q -- '--model antigravity/gemini-3.8-flash' \
  "$TMP/team-orchestrator-explicit.log" \
  || fail "Pi Orchestrator did not receive the selected override model"
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role orchestrator --runtime pi --model opus \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted an unlisted fixed-role model override"
fi
if HERDR_ENV=1 HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role orchestrator --runtime claude \
  --cwd "$ROOT" >/dev/null 2>&1; then
  fail "agent-runtime accepted a fixed-role runtime override"
fi

git init -q -b main "$TMP/protected-sync-repo"
printf '%s\n' initial > "$TMP/protected-sync-repo/tracked.txt"
"$REAL_GIT" -C "$TMP/protected-sync-repo" add tracked.txt
"$REAL_GIT" -C "$TMP/protected-sync-repo" -c user.name=Test -c user.email=test@example.com \
  commit -q -m initial
"$REAL_GIT" -C "$TMP/protected-sync-repo" branch uat
"$REAL_GIT" -C "$TMP/protected-sync-repo" switch -q uat
if HERDR_ENV=1 HERDR_AGENT_ROLE=coder HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --operation protected-sync \
  --sync-branch uat --task-tier standard \
  --cwd "$TMP/protected-sync-repo" >/dev/null 2>&1; then
  fail "agent-runtime allowed a Worker to self-authorize protected-sync"
fi
TEAM_PI_LOG="$TMP/team-protected-sync-pi.log" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=supervisor HOME="$TMP/team-home" PATH="$TMP/team-bin:$PATH" \
  bin/agent-runtime --role coder --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --operation protected-sync \
  --sync-branch uat --task-tier standard \
  --cwd "$TMP/protected-sync-repo" >/dev/null 2>&1
grep -q -- '--system-prompt' "$TMP/team-protected-sync-pi.log" \
  || fail "protected-sync Worker retained write-capable Pi tools"
if grep -q -- '--append-system-prompt' "$TMP/team-protected-sync-pi.log"; then
  fail "protected-sync Worker retained the write-capable Pi prompt"
fi

mkdir -p "$TMP/guard-bin"
cat > "$TMP/guard-bin/real-git" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"remote get-url origin")
    printf '%s\n' "$*" >> "$GUARD_STUB_LOG"
    printf '%s\n' "${GUARD_STUB_REMOTE_URL:-https://git-lab.example.com/group/project.git}"
    exit 0
    ;;
  *"branch --show-current") printf '%s\n' "${GUARD_STUB_BRANCH:-feature}"; exit 0 ;;
  *"rev-parse HEAD") printf '%s\n' "${GUARD_STUB_HEAD:-0123456789abcdef0123456789abcdef01234567}"; exit 0 ;;
  *"diff --cached --binary --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/")
    printf '%s' "${GUARD_STUB_DIFF:-reviewed staged diff}"
    exit 0
    ;;
  *"ls-remote --exit-code origin refs/heads/"*)
    printf '%s\trefs/heads/%s\n' "${GUARD_STUB_REMOTE_HEAD:-${GUARD_STUB_HEAD:-0123456789abcdef0123456789abcdef01234567}}" "${GUARD_STUB_BRANCH:-feature}"
    exit 0
    ;;
esac
printf '%s\n' "$*" >> "$GUARD_STUB_LOG"
STUB
cat > "$TMP/guard-bin/real-gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GUARD_STUB_LOG"
STUB
cat > "$TMP/guard-bin/real-glab" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s|%s|%s|%s|%s\n' \
  "${GITLAB_REPO:-unset}" "${GITLAB_HOST:-unset}" \
  "${GITLAB_URI:-unset}" "${GL_HOST:-unset}" \
  "${GITLAB_API_HOST:-unset}" "${GITLAB_HEAD_REPO:-unset}" \
  > "$GUARD_STUB_GITLAB_ENV_LOG"
printf '%s\n' "$*" >> "$GUARD_STUB_LOG"
STUB
chmod +x "$TMP/guard-bin/real-git" "$TMP/guard-bin/real-gh" \
  "$TMP/guard-bin/real-glab"

if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=orchestrator HERDR_REPO_MODE=read_only \
  HERDR_MAY_LOCAL_COMMIT=false HERDR_MAY_REMOTE_DELIVER=false \
  bin/guard-bin/git -C "$ROOT" commit -m blocked >/dev/null 2>&1; then
  fail "read-only role bypassed the local commit guard"
fi
GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=orchestrator HERDR_REPO_MODE=read_only \
  HERDR_MAY_LOCAL_COMMIT=false HERDR_MAY_REMOTE_DELIVER=false \
  bin/guard-bin/git -C "$ROOT" status --short
grep -q -- '-C .* status --short' "$TMP/guard.log" \
  || fail "read-only Git command did not pass through the guard"
GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=orchestrator HERDR_REPO_MODE=read_only \
  HERDR_MAY_LOCAL_COMMIT=false HERDR_MAY_REMOTE_DELIVER=false \
  bin/guard-bin/git -C "$ROOT" remote
for remote_args in "-v" "get-url origin" "show origin"; do
  read -r -a remote_argv <<< "$remote_args"
  GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
    HERDR_AGENT_ROLE=orchestrator HERDR_REPO_MODE=read_only \
    HERDR_MAY_LOCAL_COMMIT=false HERDR_MAY_REMOTE_DELIVER=false \
    bin/guard-bin/git -C "$ROOT" remote "${remote_argv[@]}"
done
for expected_remote in \
  "-C $ROOT remote" \
  "-C $ROOT remote -v" \
  "-C $ROOT remote get-url origin" \
  "-C $ROOT remote show origin"; do
  grep -Fqx -- "$expected_remote" "$TMP/guard.log" \
    || fail "read-only Git remote inspection did not pass through: $expected_remote"
done
for remote_mutation in add remove rm set-url set-head rename prune; do
  if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
    HERDR_AGENT_ROLE=orchestrator HERDR_REPO_MODE=read_only \
    HERDR_MAY_LOCAL_COMMIT=false HERDR_MAY_REMOTE_DELIVER=false \
    bin/guard-bin/git -C "$ROOT" remote "$remote_mutation" sample \
      >/dev/null 2>&1; then
    fail "read-only role bypassed Git remote mutation guard: $remote_mutation"
  fi
done
if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=orchestrator HERDR_REPO_MODE=read_only \
  HERDR_MAY_LOCAL_COMMIT=false HERDR_MAY_REMOTE_DELIVER=false \
  bin/guard-bin/git -C "$ROOT" remote -v add sample example.invalid \
    >/dev/null 2>&1; then
  fail "read-only role bypassed Git remote mutation guard after -v"
fi
if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=orchestrator HERDR_REPO_MODE=read_only \
  HERDR_MAY_LOCAL_COMMIT=false HERDR_MAY_REMOTE_DELIVER=false \
  bin/guard-bin/git -C "$ROOT" pull --ff-only origin uat >/dev/null 2>&1; then
  fail "read-only role bypassed the local pull guard"
fi
GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=coder HERDR_REPO_MODE=read_only \
  HERDR_OPERATION_MODE=protected-sync HERDR_PROTECTED_SYNC_BRANCH=uat \
  bin/guard-bin/git -C "$ROOT" switch uat
grep -q -- '-C .* switch uat' "$TMP/guard.log" \
  || fail "protected-sync did not allow the exact branch switch"
GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=coder HERDR_REPO_MODE=read_only \
  HERDR_OPERATION_MODE=protected-sync HERDR_PROTECTED_SYNC_BRANCH=uat \
  bin/guard-bin/git -C "$ROOT" pull --ff-only origin uat
grep -q -- '-C .* pull --ff-only origin uat' "$TMP/guard.log" \
  || fail "protected-sync did not allow the exact fast-forward pull"
if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=coder HERDR_REPO_MODE=read_only \
  HERDR_OPERATION_MODE=protected-sync HERDR_PROTECTED_SYNC_BRANCH=uat \
  bin/guard-bin/git -C "$ROOT" pull origin uat >/dev/null 2>&1; then
  fail "protected-sync allowed a pull without --ff-only"
fi
if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=coder HERDR_REPO_MODE=read_only \
  HERDR_OPERATION_MODE=protected-sync HERDR_PROTECTED_SYNC_BRANCH=uat \
  bin/guard-bin/git -C "$ROOT" fetch origin uat >/dev/null 2>&1; then
  fail "protected-sync allowed a separate fetch"
fi
if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=coder HERDR_REPO_MODE=write HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_OPERATION_MODE=protected-sync HERDR_PROTECTED_SYNC_BRANCH=uat \
  bin/guard-bin/git -C "$ROOT" commit -m blocked >/dev/null 2>&1; then
  fail "protected-sync allowed a commit after a repo-mode override"
fi
# Exercise the same token checks for a writing Worker and a read-only Supervisor.
for guard_test_role in coder supervisor; do
  guard_test_mode=write
  [ "$guard_test_role" != supervisor ] || guard_test_mode=read_only
  : > "$TMP/guard.log"
if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_REMOTE_DELIVER=false \
  bin/guard-bin/git -C "$ROOT" commit -m blocked >/dev/null 2>&1; then
  fail "$guard_test_role committed without Human diff-review authorization"
fi
printf '%s' 'reviewed staged diff' > "$TMP/guard-reviewed.diff"
printf '%s\n' 'Reviewed commit message' > "$TMP/guard-commit-message.txt"
GUARD_COMMIT_DIFF_SHA="$(shasum -a 256 "$TMP/guard-reviewed.diff" | awk '{print $1}')"
GUARD_COMMIT_MESSAGE_SHA="$(shasum -a 256 "$TMP/guard-commit-message.txt" | awk '{print $1}')"
MISMATCHED_COMMIT_TOKEN="APPROVE_COMMIT"
if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_REMOTE_DELIVER=false HERDR_COMMIT_AUTHORIZATION="$MISMATCHED_COMMIT_TOKEN" \
  HERDR_COMMIT_BRANCH=feature HERDR_COMMIT_DIFF="$(printf '0%.0s' {1..64})" \
  HERDR_COMMIT_MESSAGE_SHA256="$GUARD_COMMIT_MESSAGE_SHA" \
  HERDR_COMMIT_MESSAGE_FILE="$TMP/guard-commit-message.txt" \
  bin/guard-bin/git -C "$ROOT" commit --cleanup=verbatim \
    -F "$TMP/guard-commit-message.txt" >/dev/null 2>&1; then
  fail "$guard_test_role committed with mismatched diff authorization"
fi
VALID_COMMIT_TOKEN="APPROVE_COMMIT"
GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_REMOTE_DELIVER=false HERDR_COMMIT_AUTHORIZATION="$VALID_COMMIT_TOKEN" \
  HERDR_COMMIT_BRANCH=feature HERDR_COMMIT_DIFF="$GUARD_COMMIT_DIFF_SHA" \
  HERDR_COMMIT_MESSAGE_SHA256="$GUARD_COMMIT_MESSAGE_SHA" \
  HERDR_COMMIT_MESSAGE_FILE="$TMP/guard-commit-message.txt" \
  bin/guard-bin/git -C "$ROOT" commit --cleanup=verbatim \
    -F "$TMP/guard-commit-message.txt"
grep -Fq -- "-C $ROOT commit --cleanup=verbatim -F $TMP/guard-commit-message.txt" \
  "$TMP/guard.log" || fail "exact commit authorization did not pass the Git guard"
GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=supervisor HERDR_REPO_MODE=read_only HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_REMOTE_DELIVER=false HERDR_COMMIT_AUTHORIZATION="$VALID_COMMIT_TOKEN" \
  HERDR_COMMIT_BRANCH=feature HERDR_COMMIT_DIFF="$GUARD_COMMIT_DIFF_SHA" \
  HERDR_COMMIT_MESSAGE_SHA256="$GUARD_COMMIT_MESSAGE_SHA" \
  HERDR_COMMIT_MESSAGE_FILE="$TMP/guard-commit-message.txt" \
  bin/guard-bin/git -C "$ROOT" commit --cleanup=verbatim \
    -F "$TMP/guard-commit-message.txt"
grep -Fq -- "-C $ROOT commit --cleanup=verbatim -F $TMP/guard-commit-message.txt" \
  "$TMP/guard.log" || fail "authorized Supervisor commit did not pass the Git guard"
if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_AUTHORIZED_PUSH=true \
  HERDR_MAY_REMOTE_DELIVER=false \
  bin/guard-bin/git push origin feature >/dev/null 2>&1; then
  fail "$guard_test_role pushed without exact Human authorization"
fi
PUSH_COMMIT=0123456789abcdef0123456789abcdef01234567
PUSH_TOKEN="APPROVE_PUSH"
GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD="$PUSH_COMMIT" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_AUTHORIZED_PUSH=true HERDR_MAY_REMOTE_DELIVER=false \
  HERDR_PUSH_AUTHORIZATION="$PUSH_TOKEN" HERDR_PUSH_BRANCH=feature HERDR_PUSH_COMMIT="$PUSH_COMMIT" \
  bin/guard-bin/git push origin feature
grep -q -- '^push origin feature$' "$TMP/guard.log" \
  || fail "exactly authorized $guard_test_role branch push did not pass through the guard"
GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD="$PUSH_COMMIT" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE=supervisor HERDR_REPO_MODE=read_only HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_AUTHORIZED_PUSH=true HERDR_MAY_REMOTE_DELIVER=false \
  HERDR_PUSH_AUTHORIZATION="$PUSH_TOKEN" HERDR_PUSH_BRANCH=feature HERDR_PUSH_COMMIT="$PUSH_COMMIT" \
  bin/guard-bin/git push origin feature
grep -q -- '^push origin feature$' "$TMP/guard.log" \
  || fail "exactly authorized Supervisor branch push did not pass through the guard"
if GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=dev \
  GUARD_STUB_HEAD="$PUSH_COMMIT" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_AUTHORIZED_PUSH=true HERDR_MAY_REMOTE_DELIVER=false \
  HERDR_PUSH_AUTHORIZATION="[AUTHORIZE_PR_PUSH] branch=dev commit=$PUSH_COMMIT" \
  bin/guard-bin/git push origin dev >/dev/null 2>&1; then
  fail "$guard_test_role pushed a protected branch"
fi
for protected_branch in uat main master prod; do
  if GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH="$protected_branch" \
    GUARD_STUB_HEAD="$PUSH_COMMIT" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
    HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
    HERDR_MAY_AUTHORIZED_PUSH=true HERDR_MAY_REMOTE_DELIVER=false \
    HERDR_PUSH_AUTHORIZATION="[AUTHORIZE_PR_PUSH] branch=$protected_branch commit=$PUSH_COMMIT" \
    bin/guard-bin/git push origin "$protected_branch" >/dev/null 2>&1; then
    fail "$guard_test_role pushed protected branch: $protected_branch"
  fi
done
PRODUCTION_PUSH_TOKEN="APPROVE_PUSH"
GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=production \
  GUARD_STUB_HEAD="$PUSH_COMMIT" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_AUTHORIZED_PUSH=true HERDR_MAY_REMOTE_DELIVER=false \
  HERDR_PUSH_AUTHORIZATION="$PRODUCTION_PUSH_TOKEN" HERDR_PUSH_BRANCH=production HERDR_PUSH_COMMIT="$PUSH_COMMIT" \
  bin/guard-bin/git push origin production
grep -q -- '^push origin production$' "$TMP/guard.log" \
  || fail "non-protected production branch was unexpectedly blocked"
if GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD="$PUSH_COMMIT" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_AUTHORIZED_PUSH=true HERDR_MAY_REMOTE_DELIVER=false \
  HERDR_PUSH_AUTHORIZATION="$PUSH_TOKEN" \
  bin/guard-bin/git push --force origin feature >/dev/null 2>&1; then
  fail "$guard_test_role bypassed the authorized push shape with force"
fi
if GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD=ffffffffffffffffffffffffffffffffffffffff \
  HERDR_REAL_GIT="$TMP/guard-bin/real-git" HERDR_AGENT_ROLE="$guard_test_role" \
  HERDR_REPO_MODE="$guard_test_mode" HERDR_MAY_LOCAL_COMMIT=true \
  HERDR_MAY_AUTHORIZED_PUSH=true HERDR_MAY_REMOTE_DELIVER=false \
  HERDR_PUSH_AUTHORIZATION="$PUSH_TOKEN" \
  bin/guard-bin/git push origin feature >/dev/null 2>&1; then
  fail "$guard_test_role pushed when HEAD did not match the authorization"
fi
for guard_role in orchestrator pm supervisor sa investigator researcher designer \
  documenter coder refactor reviewer tester; do
  if [ "$guard_role" = "pm" ]; then
    if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
      HERDR_AGENT_ROLE=pm HERDR_MAY_REMOTE_DELIVER=false \
      bin/guard-bin/gh pr list >/dev/null 2>&1; then
      fail "PM GitHub inspection was not blocked"
    fi
    continue
  fi
  for gh_inspection in "pr list" "pr view 123" "pr checks 123" "pr status" "repo view"; do
    read -r -a gh_argv <<< "$gh_inspection"
    GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
      HERDR_AGENT_ROLE="$guard_role" HERDR_MAY_REMOTE_DELIVER=false \
      bin/guard-bin/gh "${gh_argv[@]}"
    grep -Fqx -- "$gh_inspection" "$TMP/guard.log" \
      || fail "GitHub inspection did not pass through for $guard_role: $gh_inspection"
  done
done
for gh_mutation in \
  "pr create --title blocked" \
  "pr merge 123" \
  "pr close 123" \
  "release delete v1" \
  "repo create blocked" \
  "repo delete blocked"; do
  read -r -a gh_argv <<< "$gh_mutation"
  if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
    HERDR_AGENT_ROLE=orchestrator HERDR_MAY_REMOTE_DELIVER=false \
    bin/guard-bin/gh "${gh_argv[@]}" >/dev/null 2>&1; then
    fail "team role bypassed the GitHub mutation guard: $gh_mutation"
  fi
done
printf '%s\n' 'authorized PR body' > "$TMP/authorized-pr-body.md"
PR_COMMIT=0123456789abcdef0123456789abcdef01234567
PR_TOKEN="APPROVE_PR_DEV"
GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD="$PR_COMMIT" GUARD_STUB_REMOTE_HEAD="$PR_COMMIT" \
  HERDR_REAL_GIT="$TMP/guard-bin/real-git" HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_MAY_AUTHORIZED_PR_CREATE=true \
  HERDR_MAY_REMOTE_DELIVER=false HERDR_PR_CREATE_AUTHORIZATION="$PR_TOKEN" \
  HERDR_PR_CREATE_BASE=dev HERDR_PR_CREATE_HEAD=feature HERDR_PR_CREATE_COMMIT="$PR_COMMIT" \
  bin/guard-bin/gh pr create --base dev --head feature --title "Test PR" \
  --body-file "$TMP/authorized-pr-body.md"
grep -q -- '^pr create --base dev --head feature --title Test PR --body-file ' "$TMP/guard.log" \
  || fail "exactly authorized PR create did not pass through the GitHub guard"
GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD="$PR_COMMIT" GUARD_STUB_REMOTE_HEAD="$PR_COMMIT" \
  HERDR_REAL_GIT="$TMP/guard-bin/real-git" HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
  HERDR_AGENT_ROLE=supervisor HERDR_MAY_AUTHORIZED_PR_CREATE=true \
  HERDR_MAY_REMOTE_DELIVER=false HERDR_PR_CREATE_AUTHORIZATION="$PR_TOKEN" \
  HERDR_PR_CREATE_BASE=dev HERDR_PR_CREATE_HEAD=feature HERDR_PR_CREATE_COMMIT="$PR_COMMIT" \
  bin/guard-bin/gh pr create --base dev --head feature --title "Test Supervisor PR" \
  --body-file "$TMP/authorized-pr-body.md"
grep -q -- '^pr create --base dev --head feature --title Test Supervisor PR --body-file ' "$TMP/guard.log" \
  || fail "exactly authorized Supervisor PR create did not pass through the GitHub guard"
if GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD="$PR_COMMIT" GUARD_STUB_REMOTE_HEAD="$PR_COMMIT" \
  HERDR_REAL_GIT="$TMP/guard-bin/real-git" HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_MAY_AUTHORIZED_PR_CREATE=true \
  HERDR_MAY_REMOTE_DELIVER=false \
  HERDR_PR_CREATE_AUTHORIZATION="$PR_TOKEN" \
  bin/guard-bin/gh pr create --base main --head feature --title "Test PR" \
  --body-file "$TMP/authorized-pr-body.md" >/dev/null 2>&1; then
  fail "$guard_test_role created a PR against a non-dev base"
fi
if GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD="$PR_COMMIT" GUARD_STUB_REMOTE_HEAD=ffffffffffffffffffffffffffffffffffffffff \
  HERDR_REAL_GIT="$TMP/guard-bin/real-git" HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_MAY_AUTHORIZED_PR_CREATE=true \
  HERDR_MAY_REMOTE_DELIVER=false HERDR_PR_CREATE_AUTHORIZATION="$PR_TOKEN" \
  bin/guard-bin/gh pr create --base dev --head feature --title "Test PR" \
  --body-file "$TMP/authorized-pr-body.md" >/dev/null 2>&1; then
  fail "$guard_test_role created a PR when origin did not match the authorized commit"
fi

if GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_BRANCH=feature \
  GUARD_STUB_HEAD="$PR_COMMIT" GUARD_STUB_REMOTE_HEAD="$PR_COMMIT" \
  HERDR_REAL_GIT="$TMP/guard-bin/real-git" HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
  HERDR_AGENT_ROLE="$guard_test_role" HERDR_MAY_AUTHORIZED_PR_CREATE=true \
  HERDR_MAY_REMOTE_DELIVER=false HERDR_PR_CREATE_AUTHORIZATION="" \
  bin/guard-bin/gh pr create --base dev --head feature --title "Test PR" \
  --body-file "$TMP/authorized-pr-body.md" >/dev/null 2>&1; then
  fail "$guard_test_role created a PR without a Human token"
fi
done

glab_guard_test() {
  GUARD_STUB_LOG="$TMP/guard.log" \
  GUARD_STUB_GITLAB_ENV_LOG="$TMP/guard-glab-env.log" \
  GUARD_STUB_REMOTE_URL="${GLAB_TEST_REMOTE_URL:-https://git-lab.example.com/group/project.git}" \
  GUARD_STUB_BRANCH="${GLAB_TEST_BRANCH:-feature}" \
  GUARD_STUB_HEAD="$PR_COMMIT" \
  GUARD_STUB_REMOTE_HEAD="${GLAB_TEST_REMOTE_HEAD:-$PR_COMMIT}" \
  HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_REAL_GLAB="$TMP/guard-bin/real-glab" \
  HERDR_AGENT_ROLE="${GLAB_TEST_ROLE:-supervisor}" \
  HERDR_MAY_AUTHORIZED_PR_CREATE="${GLAB_TEST_CAPABILITY:-true}" \
  HERDR_PR_CREATE_AUTHORIZATION="${GLAB_TEST_TOKEN-APPROVE_PR_DEV}" \
  HERDR_PR_CREATE_BASE=dev HERDR_PR_CREATE_HEAD=feature \
  HERDR_PR_CREATE_COMMIT="$PR_COMMIT" \
  HERDR_PR_CREATE_BODY_FILE="$TMP/authorized-pr-body.md" \
    bin/guard-bin/glab "$@"
}

GLAB_REPO_URL=https://git-lab.example.com/group/project.git
: > "$TMP/guard.log"
GITLAB_REPO=other/project GITLAB_HOST=other.example.com \
  GITLAB_URI=another.example.com GL_HOST=third.example.com \
  GITLAB_API_HOST=api.other.example.com GITLAB_HEAD_REPO=other/fork \
  glab_guard_test mr create --repo "$GLAB_REPO_URL" \
  --source-branch feature --target-branch dev \
  --title "Test MR" --description "authorized PR body" --yes
grep -Fqx -- "mr create --repo $GLAB_REPO_URL --source-branch feature --target-branch dev --title Test MR --description authorized PR body --yes" \
  "$TMP/guard.log" || fail "authorized GitLab MR did not pass the guard"
grep -Fqx -- 'unset|git-lab.example.com|unset|unset|git-lab.example.com|unset' \
  "$TMP/guard-glab-env.log" \
  || fail "GitLab repository, source, or host override reached the real glab CLI"
if GLAB_TEST_TOKEN= glab_guard_test mr create --repo "$GLAB_REPO_URL" --source-branch feature \
  --target-branch dev --title "Test MR" --description "authorized PR body" \
  --yes >/dev/null 2>&1; then
  fail "GitLab MR passed without APPROVE_PR_DEV"
fi
if GLAB_TEST_BRANCH=other glab_guard_test mr create --repo "$GLAB_REPO_URL" --source-branch feature \
  --target-branch dev --title "Test MR" --description "authorized PR body" \
  --yes >/dev/null 2>&1; then
  fail "GitLab MR passed from a different current branch"
fi
if GLAB_TEST_REMOTE_HEAD=ffffffffffffffffffffffffffffffffffffffff \
  glab_guard_test mr create --repo "$GLAB_REPO_URL" --source-branch feature --target-branch dev \
  --title "Test MR" --description "authorized PR body" --yes \
  >/dev/null 2>&1; then
  fail "GitLab MR passed with a different origin commit"
fi
if GLAB_TEST_REMOTE_URL=https://github.com/group/project.git \
  glab_guard_test mr create --repo "$GLAB_REPO_URL" --source-branch feature --target-branch dev \
  --title "Test MR" --description "authorized PR body" --yes \
  >/dev/null 2>&1; then
  fail "GitLab MR passed against a GitHub origin"
fi
if glab_guard_test mr create --repo https://git-lab.example.com/other/project.git \
  --source-branch feature --target-branch dev --title "Test MR" \
  --description "authorized PR body" --yes >/dev/null 2>&1; then
  fail "GitLab MR passed with a repository different from origin"
fi
for glab_bad_args in \
  'mr merge 123' \
  'mr update 123 --title changed' \
  'api projects/1/merge_requests --method POST'; do
  read -r -a glab_bad_argv <<< "$glab_bad_args"
  if glab_guard_test "${glab_bad_argv[@]}" >/dev/null 2>&1; then
    fail "GitLab guard allowed an unauthorized shape: $glab_bad_args"
  fi
done
if glab_guard_test mr create --repo "$GLAB_REPO_URL" \
  --source-branch feature --target-branch main --title "Test MR" \
  --description "authorized PR body" --yes >/dev/null 2>&1; then
  fail "GitLab MR passed with a non-dev target"
fi
if glab_guard_test mr create --repo "$GLAB_REPO_URL" \
  --source-branch feature --target-branch dev --title "Test MR" \
  --description "changed body" --yes >/dev/null 2>&1; then
  fail "GitLab MR passed with a body different from the reviewed file"
fi
if glab_guard_test mr create --repo "$GLAB_REPO_URL" \
  --source-branch feature --target-branch dev --title "Test MR" \
  --description "authorized PR body" --push >/dev/null 2>&1; then
  fail "GitLab MR create was allowed to push"
fi
if GLAB_TEST_ROLE=pm glab_guard_test mr list >/dev/null 2>&1; then
  fail "PM was allowed GitLab inspection"
fi
if GLAB_TEST_CAPABILITY=false glab_guard_test mr create \
  --repo "$GLAB_REPO_URL" --source-branch feature --target-branch dev --title "Test MR" \
  --description "authorized PR body" --yes >/dev/null 2>&1; then
  fail "GitLab MR passed without the executor capability"
fi

mkdir -p "$TMP/helper-guard-bin"
cp bin/guard-bin/git bin/guard-bin/gh bin/guard-bin/glab "$TMP/helper-guard-bin/"
for helper_remote in \
  https://git-lab.example.com/group/project.git \
  https://github.com/group/project.git; do
  : > "$TMP/guard.log"
  GUARD_STUB_LOG="$TMP/guard.log" GUARD_STUB_REMOTE_URL="$helper_remote" \
  GUARD_STUB_BRANCH=feature GUARD_STUB_HEAD="$PR_COMMIT" \
  GUARD_STUB_REMOTE_HEAD="$PR_COMMIT" HERDR_ENV=1 \
  HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
  HERDR_REAL_GH="$TMP/guard-bin/real-gh" \
  HERDR_REAL_GLAB="$TMP/guard-bin/real-glab" \
  GUARD_STUB_GITLAB_ENV_LOG="$TMP/guard-glab-env.log" \
  HERDR_AGENT_ROLE=supervisor HERDR_REPO_MODE=read_only \
  HERDR_MAY_AUTHORIZED_PR_CREATE=true \
  PATH="$TMP/helper-guard-bin:$PATH" \
  bash -c 'source "$1"; agent_authorized_pr_create dev feature "$2" "Test delivery" "$3" APPROVE_PR_DEV' \
    bash "$ROOT/.agents/skills/agent-shared/lib/agent-helpers.sh" \
    "$PR_COMMIT" "$TMP/authorized-pr-body.md"
  case "$helper_remote" in
    *git-lab*) grep -q '^mr create --repo https://git-lab.example.com/group/project.git --source-branch feature --target-branch dev' "$TMP/guard.log" \
      || fail "PR helper did not route GitLab origin through the guarded glab command" ;;
    *) grep -q '^pr create --base dev --head feature' "$TMP/guard.log" \
      || fail "PR helper did not preserve the guarded GitHub path" ;;
  esac
done
for mutation in "add tracked.txt" "reset --hard" "checkout -- tracked.txt"; do
  read -r -a mutation_argv <<< "$mutation"
  if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
    HERDR_AGENT_ROLE=supervisor HERDR_REPO_MODE=read_only \
    HERDR_MAY_LOCAL_COMMIT=true HERDR_MAY_AUTHORIZED_PUSH=true \
    HERDR_MAY_REMOTE_DELIVER=false HERDR_COMMIT_AUTHORIZATION="$VALID_COMMIT_TOKEN" \
    bin/guard-bin/git "${mutation_argv[@]}" >/dev/null 2>&1; then
    fail "Supervisor token capabilities allowed repository mutation: $mutation"
  fi
done
for pm_history_command in "log -1" "show HEAD" "ls-remote origin"; do
  read -r -a pm_history_argv <<< "$pm_history_command"
  if GUARD_STUB_LOG="$TMP/guard.log" HERDR_REAL_GIT="$TMP/guard-bin/real-git" \
    HERDR_AGENT_ROLE=pm HERDR_REPO_MODE=read_only \
    bin/guard-bin/git "${pm_history_argv[@]}" >/dev/null 2>&1; then
    fail "PM history inspection was not blocked: $pm_history_command"
  fi
done

mkdir -p "$TMP/herdr-bin" "$TMP/herdr-state"
cat > "$TMP/herdr-bin/herdr" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$HERDR_STUB_LOG"
case "$1 $2" in
  "pane get")
    if [ -f "$HERDR_STUB_STATE/running" ]; then
      printf '{"result":{"pane":{"label":"%s","agent":"claude","agent_status":"idle"}}}\n' \
        "${HERDR_STUB_LABEL:-coder-smart_ai-api}"
    else
      printf '%s\n' '{"result":{"pane":{"label":"","agent":null,"agent_status":"unknown"}}}'
    fi
    ;;
  "pane process-info")
    if [ -f "$HERDR_STUB_STATE/running" ]; then
      printf '{"result":{"process_info":{"foreground_processes":[{"cmdline":"claude --agent herdr-%s"}]}}}\n' \
        "${HERDR_STUB_ROLE:-coder}"
    else
      printf '%s\n' '{"result":{"process_info":{"foreground_processes":[{"cmdline":"zsh"}]}}}'
    fi
    ;;
  "pane run")
    touch "$HERDR_STUB_STATE/running"
    ;;
esac
STUB
chmod +x "$TMP/herdr-bin/herdr"
mkdir -p "$TMP/herdr-state-protected-sync"
HERDR_STUB_LOG="$TMP/spawn-protected-sync.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-protected-sync" \
  HERDR_ENV=1 HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p5 --role coder --project smart_ai \
  --base-branch uat --work-branch uat --operation protected-sync \
  --sync-branch uat --cwd "$TMP/protected-sync-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard >/dev/null
test "$("$REAL_GIT" -C "$TMP/protected-sync-repo" branch --show-current)" = uat \
  || fail "spawn-agent did not switch to the approved protected sync branch"
grep -q -- '--operation protected-sync --sync-branch uat' \
  "$TMP/spawn-protected-sync.log" \
  || fail "spawn-agent did not forward the protected-sync operation"
git init -q -b main "$TMP/spawn-repo"
printf '%s\n' initial > "$TMP/spawn-repo/tracked.txt"
"$REAL_GIT" -C "$TMP/spawn-repo" add tracked.txt
"$REAL_GIT" -C "$TMP/spawn-repo" -c user.name=Test -c user.email=test@example.com \
  commit -q -m initial
mkdir -p "$TMP/herdr-state-designer"
HERDR_STUB_LOG="$TMP/spawn-designer.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-designer" HERDR_STUB_ROLE=designer \
  HERDR_STUB_LABEL=designer-smart_ai HERDR_ENV=1 \
  HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p8 --role designer --project smart_ai \
  --cwd "$TMP/spawn-repo" >/dev/null
grep -q -- '--runtime claude --model opus' "$TMP/spawn-designer.log" \
  || fail "spawn-agent did not resolve fixed Designer to Claude Opus"
if grep -q -- '--task-tier' "$TMP/spawn-designer.log"; then
  fail "spawn-agent forwarded a task tier to fixed Designer"
fi
mkdir -p "$TMP/herdr-state-supervisor-auto"
HERDR_STUB_LOG="$TMP/spawn-supervisor-auto.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-supervisor-auto" \
  HERDR_STUB_ROLE=supervisor HERDR_STUB_LABEL=supervisor-smart_ai \
  HERDR_ENV=1 HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p12 --role supervisor --project smart_ai \
  --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard \
  --commit-mode auto >/dev/null
grep -q -- '--role supervisor.*--commit-mode auto' \
  "$TMP/spawn-supervisor-auto.log" \
  || fail "spawn-agent did not forward Supervisor's approved auto commit mode"
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=orchestrator SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role pm --project smart_ai \
  --cwd "$TMP/spawn-repo" --commit-mode auto >/dev/null 2>&1; then
  fail "spawn-agent allowed auto commit for PM"
fi
mkdir -p "$TMP/herdr-state-vault"
HERDR_STUB_LOG="$TMP/spawn-vault.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-vault" HERDR_STUB_ROLE=investigator \
  HERDR_STUB_LABEL=investigator-smart_ai HERDR_ENV=1 \
  HERDR_AGENT_ROLE=pm HERDR_TEAM_VAULT_PATH="$TMP/team-home/Workspaces/vault" \
  SPAWN_STARTUP_DELAY_SECONDS=0 PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p7 --role investigator --project smart_ai \
  --task-class investigation --knowledge-source vault \
  --vault-read-scope projects/smart_ai --cwd "$TMP/spawn-repo" \
  --runtime pi --model opencode-go/deepseek-v4.1-flash \
  --task-tier standard >/dev/null
grep -q -- '--knowledge-source vault --vault-read-scope' "$TMP/spawn-vault.log" \
  && grep -q -- "HERDR_TEAM_VAULT_PATH=$TMP/team-home/Workspaces/vault" \
    "$TMP/spawn-vault.log" \
  || fail "spawn-agent did not forward the validated vault retrieval scope"
: > "$TMP/spawn-rejected.log"
for rejected_args in \
  "--runtime auto --model opencode-go/deepseek-v4.1-flash" \
  "--runtime pi" \
  "--runtime pi --model auto" \
  "--runtime claude --model sonnet" \
  "--runtime pi --model unlisted-model"; do
  if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
    HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
    HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
    PATH="$TMP/herdr-bin:$PATH" \
    bin/spawn-agent --pane w1:p9 --role coder --project smart_ai \
    --workstream rejected --base-branch main --work-branch feature/rejected \
    --cwd "$TMP/spawn-repo" --task-tier standard $rejected_args >/dev/null 2>&1; then
    fail "spawn-agent accepted invalid controller model selection: $rejected_args"
  fi
done

add_test_alternates "$TMP/team-home/.agents/team.json"
python3 - "$TMP/team-home/.agents/team.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
team = json.loads(path.read_text())
# Fixed PM must keep an enabled default while its shipped provider is disabled.
team["roles"]["pm"]["models"] = {"claude": ["sonnet"]}
team["roles"]["pm"]["default_model"] = "sonnet"
team["disabled_model_providers"] = ["opencode-go"]
path.write_text(json.dumps(team, indent=2) + "\n")
PY

if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  AGENTS_HOME="$TMP/team-home/.agents" \
  HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role coder --project smart_ai \
  --workstream rejected --base-branch main --work-branch feature/rejected \
  --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/step-5-preview \
  --task-tier standard --routing-exception >/dev/null \
  2>"$TMP/spawn-disabled-provider.err"; then
  fail "spawn-agent accepted the disabled OpenCode Go provider"
fi
grep -q 'model provider is disabled: opencode-go' "$TMP/spawn-disabled-provider.err" \
  || fail "spawn-agent did not explain the disabled OpenCode Go provider"
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role designer --project smart_ai \
  --cwd "$TMP/spawn-repo" --task-tier standard >/dev/null 2>&1; then
  fail "spawn-agent accepted task-tier routing for fixed Designer"
fi
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role coder --project smart_ai \
    --workstream rejected --base-branch main --work-branch feature/rejected \
    --cwd "$TMP/spawn-repo" --runtime pi --model opencode-go/deepseek-v4.1-flash \
  >/dev/null 2>&1; then
  fail "spawn-agent accepted a controller-selected role without a task tier"
fi
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role coder --project smart_ai \
  --workstream rejected --base-branch main --work-branch feature/rejected \
  --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/step-5-preview --task-tier standard >/dev/null 2>&1; then
  fail "spawn-agent accepted an alternate without --routing-exception"
fi
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role reviewer --project smart_ai \
  --cwd "$TMP/spawn-repo" --runtime pi --model antigravity/gemini-3.8-flash \
  --task-tier critical --routing-exception >/dev/null 2>&1; then
  fail "spawn-agent accepted an allowlisted model that is not a configured alternate"
fi
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role coder --project smart_ai \
  --workstream rejected --base-branch main --work-branch feature/rejected \
  --cwd "$TMP/spawn-repo" --runtime pi --model opencode-go/deepseek-v4.1-flash \
  --task-tier standard --routing-exception >/dev/null 2>&1; then
  fail "spawn-agent accepted --routing-exception for a primary model"
fi
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role designer --project smart_ai \
  --cwd "$TMP/spawn-repo" --runtime pi --model opus --task-tier standard \
  >/dev/null 2>&1; then
  fail "spawn-agent accepted a model from another runtime allowlist"
fi
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p9 --role coder --project smart_ai \
  --workstream rejected --base-branch main --work-branch feature/rejected \
  --staffing full --cwd "$TMP/spawn-repo" --runtime pi \
  --model alibaba-token-intl/deepseek-v4.1-flash-1017 --task-tier standard --routing-exception \
  >/dev/null 2>&1; then
  fail "spawn-agent allowed PM to launch a full staffing Worker directly"
fi
[ ! -s "$TMP/spawn-rejected.log" ] \
  || fail "rejected model selection mutated a pane"
test "$("$REAL_GIT" -C "$TMP/spawn-repo" branch --show-current)" = main \
  || fail "rejected model selection mutated the Worker branch"

mkdir -p "$TMP/herdr-state-failover"
HERDR_STUB_LOG="$TMP/spawn-failover.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-failover" \
  HERDR_STUB_LABEL=supervisor-smart_ai HERDR_STUB_ROLE=supervisor \
  HERDR_ENV=1 AGENTS_HOME="$TMP/team-home/.agents" HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p11 --role supervisor --project smart_ai \
  --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard \
  >/dev/null 2>"$TMP/spawn-failover.err"
grep -q -- '--runtime claude --model sonnet' "$TMP/spawn-failover.log" \
  && grep -q -- '--routing-exception' "$TMP/spawn-failover.log" \
  && grep -q -- 'HERDR_ROUTING_RESOLUTION=disabled-primary-failover' \
    "$TMP/spawn-failover.log" \
  || fail "spawn-agent did not launch the first enabled failover model"
grep -q -- 'routing failover role=supervisor tier=standard' \
  "$TMP/spawn-failover.err" \
  || fail "spawn-agent did not report the disabled-primary failover"

if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p10 --role tester --project smart_ai \
  --task-class document --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard >/dev/null 2>&1; then
  fail "spawn-agent allowed Tester for a document without runnable acceptance"
fi
if HERDR_STUB_LOG="$TMP/spawn-rejected.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-rejected" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=pm HERDR_TEAM_VAULT_PATH="$TMP/team-home/Workspaces/vault" \
  SPAWN_STARTUP_DELAY_SECONDS=0 PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p10 --role investigator --project smart_ai \
  --task-class investigation --knowledge-source vault --vault-read-scope . \
  --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard \
  >/dev/null 2>&1; then
  fail "spawn-agent accepted the entire vault as a retrieval scope"
fi

HERDR_STUB_LOG="$TMP/spawn.log" HERDR_STUB_STATE="$TMP/herdr-state" \
  HERDR_ENV=1 HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p2 --role coder --project smart_ai \
  --workstream api --base-branch main --work-branch feature/api-change \
  --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard >/dev/null
grep -q '^pane rename w1:p2 coder-smart_ai-api$' "$TMP/spawn.log" \
  || fail "spawn-agent did not apply the expected pane label"
grep -q '^pane run w1:p2 ' "$TMP/spawn.log" \
  || fail "spawn-agent did not launch the runtime through pane run"
grep -q -- '--runtime pi --model opencode-go/deepseek-v4.1-flash' \
  "$TMP/spawn.log" \
  || fail "spawn-agent did not forward the validated runtime/model pair"
grep -q -- '--task-tier standard' "$TMP/spawn.log" \
  || fail "spawn-agent did not forward the validated task tier"
grep -q -- 'HERDR_PROJECT=smart_ai' "$TMP/spawn.log" \
  || fail "spawn-agent did not propagate the project context"
test "$("$REAL_GIT" -C "$TMP/spawn-repo" branch --show-current)" = \
  'feature/api-change' \
  || fail "spawn-agent did not create and switch to the approved work branch"
"$REAL_GIT" -C "$TMP/spawn-repo" merge-base --is-ancestor main feature/api-change \
  || fail "spawn-agent prepared a work branch from the wrong base"

"$REAL_GIT" -C "$TMP/spawn-repo" switch -q main
mkdir -p "$TMP/herdr-state-direct"
HERDR_STUB_LOG="$TMP/spawn-direct.log" HERDR_STUB_STATE="$TMP/herdr-state-direct" \
  HERDR_ENV=1 HERDR_AGENT_ROLE=pm SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p6 --role coder --project smart_ai \
  --workstream api --base-branch main --work-branch feature/direct \
  --staffing minimal --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard >/dev/null
grep -q -- '--controller-role pm --staffing minimal' "$TMP/spawn-direct.log" \
  || fail "PM direct spawn did not pass its controller and staffing mode"
grep -q -- '--runtime pi --model opencode-go/deepseek-v4.1-flash' \
  "$TMP/spawn-direct.log" \
  && grep -q -- '--task-tier standard' "$TMP/spawn-direct.log" \
  || fail "spawn-agent did not forward the direct path primary model"
if grep -q -- '--routing-exception' "$TMP/spawn-direct.log"; then
  fail "spawn-agent marked a primary model as a routing exception"
fi
test "$("$REAL_GIT" -C "$TMP/spawn-repo" branch --show-current)" = \
  'feature/direct' \
  || fail "PM direct spawn did not prepare the approved work branch"

"$REAL_GIT" -C "$TMP/spawn-repo" switch -q feature/api-change
mkdir -p "$TMP/herdr-state-reuse"
HERDR_STUB_LOG="$TMP/spawn-reuse.log" HERDR_STUB_STATE="$TMP/herdr-state-reuse" \
  HERDR_ENV=1 HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p4 --role coder --project smart_ai \
  --workstream api --base-branch feature/api-change \
  --work-branch feature/api-change --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard >/dev/null
test "$("$REAL_GIT" -C "$TMP/spawn-repo" branch --show-current)" = \
  'feature/api-change' \
  || fail "spawn-agent did not reuse the approved existing Work branch"

"$REAL_GIT" -C "$TMP/spawn-repo" switch -q main
printf '%s\n' dirty > "$TMP/spawn-repo/untracked.txt"
if HERDR_STUB_LOG="$TMP/spawn-dirty.log" \
  HERDR_STUB_STATE="$TMP/herdr-state-dirty" HERDR_ENV=1 \
  HERDR_AGENT_ROLE=supervisor SPAWN_STARTUP_DELAY_SECONDS=0 \
  PATH="$TMP/herdr-bin:$PATH" \
  bin/spawn-agent --pane w1:p3 --role coder --project smart_ai \
  --workstream dirty --base-branch main --work-branch feature/dirty \
  --cwd "$TMP/spawn-repo" --runtime pi \
  --model opencode-go/deepseek-v4.1-flash --task-tier standard >/dev/null 2>&1; then
  fail "spawn-agent created a work branch from a dirty worktree"
fi
test "$("$REAL_GIT" -C "$TMP/spawn-repo" branch --show-current)" = main \
  || fail "failed branch preparation changed the current branch"

mkdir -p "$TMP/uninstall-home/Workspaces/.agents/task-board/demo/task-1"
printf '%s\n' durable > "$TMP/uninstall-home/Workspaces/.agents/task-board/demo/task-1/events.jsonl"
mkdir -p \
  "$TMP/uninstall-home/.agents/skills/current-skill" \
  "$TMP/uninstall-home/.agents/agents" \
  "$TMP/uninstall-home/.agents/protocols" \
  "$TMP/uninstall-home/.agents/extensions" \
  "$TMP/uninstall-home/.config/herdr" \
  "$TMP/uninstall-home/.agents/workflows" \
  "$TMP/uninstall-home/.claude/agents" \
  "$TMP/uninstall-home/.claude/skills/herdr" \
  "$TMP/uninstall-home/.claude/skills/agent-team" \
  "$TMP/uninstall-home/.claude/skills/agent-shared" \
  "$TMP/uninstall-home/.claude/skills/user-skill" \
  "$TMP/uninstall-home/.claude/commands" \
  "$TMP/uninstall-home/.cursor" \
  "$TMP/uninstall-home/bin"
printf '%s\n' current-skill > \
  "$TMP/uninstall-home/.agents/project-scaffold-skills.txt"
printf '%s\n' current-bin > \
  "$TMP/uninstall-home/.agents/project-scaffold-bin-files.txt"
printf '%s\n' herdr-coder.md > \
  "$TMP/uninstall-home/.agents/project-scaffold-claude-agents.txt"
printf '%s\n' herdr agent-team agent-shared > \
  "$TMP/uninstall-home/.agents/project-scaffold-claude-skills.txt"
printf '%s\n' orchestrator-shutdown.ts > \
  "$TMP/uninstall-home/.agents/project-scaffold-pi-extensions.txt"
printf '%s\n' tts-thai.sh > \
  "$TMP/uninstall-home/.agents/project-scaffold-voice-files.txt"
touch \
  "$TMP/uninstall-home/bin/current-bin" \
  "$TMP/uninstall-home/.claude/agents/herdr-coder.md" \
  "$TMP/uninstall-home/.agents/extensions/orchestrator-shutdown.ts" \
  "$TMP/uninstall-home/.config/herdr/tts-thai.sh" \
  "$TMP/uninstall-home/.claude/skills/herdr/SKILL.md" \
  "$TMP/uninstall-home/.claude/skills/agent-team/SKILL.md" \
  "$TMP/uninstall-home/.claude/skills/agent-shared/SKILL.md" \
  "$TMP/uninstall-home/.claude/skills/user-skill/SKILL.md" \
  "$TMP/uninstall-home/.claude/commands/ap-prd.md" \
  "$TMP/uninstall-home/.claude/commands/user-command.md" \
  "$TMP/uninstall-home/.agents/agents.md" \
  "$TMP/uninstall-home/.agents/team.json"
cat > "$TMP/uninstall-home/.agents/project-scaffold-mcp-servers.json" <<'JSON'
["managed-server"]
JSON
cat > "$TMP/uninstall-home/.cursor/mcp.json" <<'JSON'
{
  "mcpServers": {
    "managed-server": {"command": "managed"},
    "user-server": {"command": "user"}
  }
}
JSON
HOME="$TMP/uninstall-home" ./uninstall.sh >/dev/null
[ -e "$TMP/uninstall-home/Workspaces/.agents/task-board/demo/task-1/events.jsonl" ] \
  || fail "uninstall deleted Task Board history"
[ ! -e "$TMP/uninstall-home/.agents/skills/current-skill" ] \
  || fail "uninstall kept a manifest-owned skill"
[ ! -e "$TMP/uninstall-home/bin/current-bin" ] \
  || fail "uninstall kept a manifest-owned binary"
[ ! -e "$TMP/uninstall-home/.claude/agents/herdr-coder.md" ] \
  || fail "uninstall kept a manifest-owned Claude agent"
[ ! -e "$TMP/uninstall-home/.agents/extensions/orchestrator-shutdown.ts" ] \
  || fail "uninstall kept a manifest-owned Pi extension"
[ ! -e "$TMP/uninstall-home/.config/herdr/tts-thai.sh" ] \
  || fail "uninstall kept the manifest-owned TTS adapter"
for skill in herdr agent-team agent-shared; do
  [ ! -e "$TMP/uninstall-home/.claude/skills/$skill" ] \
    || fail "uninstall kept a manifest-owned Claude skill: $skill"
done
[ ! -e "$TMP/uninstall-home/.claude/commands/ap-prd.md" ] \
  || fail "uninstall kept a legacy full-sync workflow"
[ -e "$TMP/uninstall-home/.claude/skills/user-skill/SKILL.md" ] \
  || fail "uninstall removed an unrelated skill"
[ -e "$TMP/uninstall-home/.claude/commands/user-command.md" ] \
  || fail "uninstall removed an unrelated workflow"
python3 - "$TMP/uninstall-home/.cursor/mcp.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    servers = json.load(handle)["mcpServers"]
if "managed-server" in servers:
    raise SystemExit("uninstall kept a managed MCP server")
if "user-server" not in servers:
    raise SystemExit("uninstall removed an unrelated MCP server")
PY
HOME="$TMP/uninstall-home" ./uninstall.sh --check >/dev/null \
  || fail "uninstall --check found residue after cleanup"

bash tests/task-board.test.sh || fail "task-board tests failed"
bash tests/micro-verification.test.sh || fail "micro verification tests failed"
bash tests/workflow-shape.test.sh || fail "workflow shape tests failed"
bash tests/clickup-watch.test.sh || fail "clickup-watch tests failed"
bash tests/herdr-app-spawn-role.test.sh || fail "herdr-app-spawn-role tests failed"
bash tests/hteam.test.sh || fail "hteam tests failed"
bash tests/hteam-dispatch.test.sh || fail "hteam-dispatch tests failed"
bash tests/extensions.test.sh || fail "role extension tests failed"

echo "validate: ok"
