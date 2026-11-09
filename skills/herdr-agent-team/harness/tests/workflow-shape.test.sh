#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT/bin/workflow-shape"
TEAM="$ROOT/.agents/team.json"

fail() {
  echo "workflow-shape.test: $*" >&2
  exit 1
}

[ -x "$RESOLVER" ] || fail "bin/workflow-shape is missing or not executable"
[ -f "$TEAM" ] || fail ".agents/team.json is missing"

resolve() {
  printf '%s' "$1" | "$RESOLVER" --intake - --team "$TEAM" --format json
}

field() {
  python3 -c '
import json, sys
data = json.load(sys.stdin)
expr = sys.argv[1]
value = data
for part in expr.split("."):
    if part.isdigit():
        value = value[int(part)]
    elif "[" in part:
        name, key = part.split("[", 1)
        key = key.rstrip("]")
        target = value[name]
        value = target[int(key)] if isinstance(target, list) else target[key]
    else:
        value = value[part]
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, sort_keys=True))
else:
    print(value)
' "$1"
}

expect() {
  local label="$1" intake="$2" expr="$3" want="$4"
  local out
  out="$(resolve "$intake")"
  local got
  got="$(printf '%s' "$out" | field "$expr")" || fail "$label: cannot read $expr"
  [ "$got" = "$want" ] || fail "$label: expected $expr=$want, got $got"
  echo "  ok  $label"
}

expect_json_contains() {
  local label="$1" intake="$2" expr="$3" needle="$4"
  local out got
  out="$(resolve "$intake")"
  got="$(printf '%s' "$out" | field "$expr")" || fail "$label: cannot read $expr"
  case "$got" in
    *"$needle"*) echo "  ok  $label" ;;
    *) fail "$label: expected $expr to contain '$needle', got $got" ;;
  esac
}

echo "workflow-shape: catalogue"
# `--list | grep -q` races: grep exits on the first match and the resolver dies
# with BrokenPipeError, which pipefail turns into a failed install.
LIST="$(mktemp -t workflow-shape-list)"
trap 'rm -f "$LIST"' EXIT
"$RESOLVER" --list > "$LIST" || fail "catalogue could not be listed"
grep -q '^W2-micro ' "$LIST" || fail "catalogue is missing W2-micro"
[ "$(wc -l < "$LIST" | tr -d ' ')" = "11" ] || fail "catalogue must define 11 shapes"

echo "workflow-shape: smallest-shape defaults"
expect "advisory answer stays with PM" \
  '{"task_class":"advisory","request":"is this branch safe to merge"}' \
  "shape" "W0-answer"
expect "advisory opens no pane" \
  '{"task_class":"advisory"}' "staff" "[]"
expect "documentation goes to documenter" \
  '{"task_class":"document"}' "shape" "W1-doc"
expect "deterministic micro edit skips verifiers" \
  '{"task_class":"bug-fix","micro_deterministic":true,"touches_behavior":false}' \
  "staff[0].role" "coder"
expect "deterministic micro edit needs no verifier" \
  '{"task_class":"bug-fix","micro_deterministic":true,"touches_behavior":false}' \
  "verifiers" "[]"

echo "workflow-shape: escalation by evidence"
expect "unknown cause investigates before fixing" \
  '{"task_class":"bug-fix","known_cause":false,"touches_behavior":true,"runnable_acceptance":true}' \
  "shape" "W8-investigate"
expect "behavior fix without runnable acceptance uses reviewer" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true}' \
  "verifiers" '["reviewer"]'
expect "behavior fix with runnable acceptance uses tester" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true}' \
  "verifiers" '["tester"]'
expect "structural cleanup alone is a refactor" \
  '{"task_class":"refactor","structural_cleanup":true}' \
  "shape" "W5-refactor"
expect "cleanup under a bug is a combined shape" \
  '{"task_class":"bug-fix","structural_cleanup":true,"touches_behavior":true,"known_cause":true}' \
  "shape" "W6-fix-refactor"
expect "new behavior is a feature" \
  '{"task_class":"feature","new_behavior":true,"runnable_acceptance":true}' \
  "staff[0].role" "sa"
expect "features with UI work add the designer" \
  '{"task_class":"feature","new_behavior":true,"ui_change":true}' \
  "staff[0].role" "designer"
expect "features needing external facts add the researcher" \
  '{"task_class":"feature","new_behavior":true,"external_facts_needed":true}' \
  "staff[0].role" "researcher"
expect "high risk needs both verifiers" \
  '{"task_class":"feature","new_behavior":true,"risk":"high"}' \
  "verifiers" '["reviewer", "tester"]'
expect "high risk forces critical tier" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"risk":"high"}' \
  "tier" "critical"

echo "workflow-shape: verification independence"
expect "standard-tier coder and tester are already independent" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true,"risk":"low"}' \
  "model_independence.status" "ok"
expect "a clean pair stays on the standard tier" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true,"risk":"low"}' \
  "tier" "standard"
expect "critical coder/reviewer collision uses the reviewer alternate" \
  '{"task_class":"feature","new_behavior":true,"risk":"high"}' \
  "model_independence.status" "alternate"
expect "critical reviewer runs on a non-Claude model" \
  '{"task_class":"feature","new_behavior":true,"risk":"high"}' \
  "model_independence.alternate_models" '{"reviewer": {"model": "alibaba-token-intl/qwen3.8-max", "runtime": "pi"}}'
expect "standard refactor/tester are independent (tester routes to kiro)" \
  '{"task_class":"bug-fix","structural_cleanup":true,"touches_behavior":true,"known_cause":true,"runnable_acceptance":true}' \
  "model_independence.status" "ok"
expect "a policy document is already independent at standard tier" \
  '{"task_class":"document","policy_sensitive_doc":true}' \
  "model_independence.status" "ok"

echo "workflow-shape: parallelism gate"
expect "independent workstreams enable worktrees" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true,"independent_workstreams":3}' \
  "parallel.isolation" "git-worktree"
expect "parallel writers run supervised" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true,"independent_workstreams":3}' \
  "controller" "supervised"
expect "parallelism duplicates only writers" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true,"independent_workstreams":3}' \
  "staff" '[{"model": {"model": "opencode-go/deepseek-v4.1-flash", "runtime": "pi"}, "role": "coder", "workstream": "ws-1"}, {"model": {"model": "opencode-go/deepseek-v4.1-flash", "runtime": "pi"}, "role": "coder", "workstream": "ws-2"}, {"model": {"model": "opencode-go/deepseek-v4.1-flash", "runtime": "pi"}, "role": "coder", "workstream": "ws-3"}]'
expect "single workstream needs no worktree" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true}' \
  "parallel.isolation" "none"

echo "workflow-shape: gates and audit trail"
expect_json_contains "delivery demands a human token" \
  '{"task_class":"delivery","needs_remote_delivery":true}' \
  "gates" "human-delivery-token"
expect_json_contains "delivery gate is not duplicated" \
  '{"task_class":"delivery","needs_remote_delivery":true}' \
  "gates" "verification-gate"
expect_json_contains "behavior work carries the verification gate" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true,"runnable_acceptance":true}' \
  "gates" "verification-gate"
expect "every rejected shape carries a reason" \
  '{"task_class":"bug-fix","micro_deterministic":true,"touches_behavior":false}' \
  "rejected_shapes" '[{"reason": "the request is not a bounded delivery of verified work", "shape": "W10-deliver"}, {"reason": "the intake implies a repository write", "shape": "W0-answer"}, {"reason": "the change is not documentation-only", "shape": "W1-doc"}, {"reason": "the cause is known or no discovery was requested", "shape": "W8-investigate"}, {"reason": "the change touches source behavior, so it is not operational", "shape": "W9-ops"}, {"reason": "no approved structural cleanup sits under a behavior change", "shape": "W6-fix-refactor"}, {"reason": "no approved structural cleanup", "shape": "W5-refactor"}, {"reason": "no new behavior is being added", "shape": "W7-feature"}]'
expect_json_contains "the smallest-shape rule is stated" \
  '{"task_class":"advisory"}' \
  "reminders" "Default to the smallest shape"
expect "escalation is capped at one" \
  '{"task_class":"bug-fix","touches_behavior":true,"known_cause":true}' \
  "escalation.allowed" "1"
expect_json_contains "contradictory intake is flagged" \
  '{"task_class":"refactor","new_behavior":true}' \
  "contradictions" "task_class=refactor but new_behavior is true"

echo "workflow-shape: invalid intake"
if printf '%s' '{"task_class":"nope"}' | "$RESOLVER" --intake - --team "$TEAM" >/dev/null 2>&1; then
  fail "unknown task_class must exit non-zero"
fi
if printf '%s' '{"touches_behavior":"yes"}' | "$RESOLVER" --intake - --team "$TEAM" >/dev/null 2>&1; then
  fail "non-boolean flag must exit non-zero"
fi
if printf '%s' '{"independent_workstreams":0}' | "$RESOLVER" --intake - --team "$TEAM" >/dev/null 2>&1; then
  fail "zero workstreams must exit non-zero"
fi
if printf '%s' '{"bogus_field":1}' | "$RESOLVER" --intake - --team "$TEAM" >/dev/null 2>&1; then
  fail "unknown intake field must exit non-zero"
fi
echo "  ok  invalid intakes are rejected"

echo "workflow-shape: ok"