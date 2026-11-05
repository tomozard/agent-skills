# Workflow shapes, intake, and tiers

The resolver (`scripts/workflow-shape`) is the executable mirror of the staffing
policy: the same intake always produces the same shape, the same staff, the same
verifiers, and the same recorded reason. It never spawns or writes.

## Intake

One JSON object per task. Unknown keys are ignored; these are the ones that
change the answer:

| Field | Type | Effect |
|---|---|---|
| `task_class` | `advisory`, `document`, `operational`, `delivery`, `investigation`, `bug-fix`, `feature`, `refactor` | picks the candidate shapes |
| `touches_behavior` | bool | behavior changed (fix/feature) rather than text |
| `known_cause` | bool | cause established; otherwise investigate first |
| `runnable_acceptance` | bool | there is an executable check, so a Tester is worth it |
| `structural_cleanup` | bool | the fix is structural → refactor participates |
| `new_behavior` | bool | new capability → specification before code |
| `ui_change` | bool | adds a designer to a feature |
| `external_facts_needed` | bool | adds a researcher |
| `policy_sensitive_doc` | bool | document that changes policy or security → independent reviewer |
| `risk` | `low`, `medium`, `high` | `high` forces the `critical` tier |
| `independent_workstreams` | int ≥ 1 | > 1 forces `isolation: git-worktree` and a supervisor |
| `request` | string | the ask; security/auth/payment/migration keywords force `critical` |

Example: `examples/intake.json`.

## Shape catalogue

| Shape | Selected when | Staff | Verifiers |
|---|---|---|---|
| `W0-answer` | advisory only, no repository write | — | — |
| `W1-doc` | documentation-only change | documenter | reviewer when policy/security |
| `W2-micro` | deterministic micro diff, no behavior change | coder | — (task-board proof) |
| `W3-fix` | known-cause behavior fix, acceptance not runnable | coder | reviewer |
| `W4-fix-test` | known-cause behavior fix with runnable acceptance | coder | tester |
| `W5-refactor` | approved structural cleanup, no behavior change | refactor | reviewer |
| `W6-fix-refactor` | behavior fix whose root cause is structural | coder, refactor (serial) | reviewer, tester |
| `W7-feature` | new behavior; specification before code | sa (plus designer/researcher) , coder | reviewer, tester |
| `W8-investigate` | cause or scope unknown | investigator | — |
| `W9-ops` | operational change, no source behavior change | coder | reviewer |
| `W10-deliver` | commit/push/PR of a verified increment | — | — |

## Escalation and independence

The resolver also decides whether the requested team is *safe*:

- **Model independence.** If a writer and a verifier land on the same model and
  runtime, it tries, in order: a configured alternate on the same tier, raising
  the whole task one tier, then substituting a different verifier role. If none
  of those separate them it returns `partial` or `blocked` and names the model to
  add — `blocked` is `[STUCK]`, never permission to self-verify.
- **Parallelism.** `independent_workstreams > 1` forces worktree isolation and
  the supervised controller.
- **Reasons.** Every rejected larger shape is recorded, so "why not four agents?"
  has an answer in the output rather than in a chat log.

## Tiers

Two tiers, scored on five dimensions from 0–2 (scope, ambiguity, reasoning, risk,
evidence):

| Tier | Score | Use |
|---|---|---|
| `standard` | 0–7 | basic and general work — the bulk of tasks |
| `critical` | 8–10 | highest reasoning; security, authentication, payments, destructive data changes, migrations, production infrastructure, and cross-repository work always land here |

A third middle tier is intentionally absent: standard models now carry general
work, so an extra tier only added routing ambiguity. If a project still runs
three tiers, map `easy`+`advanced` to `standard` before adopting these scripts.

## Wiring it to a runtime

`scripts/workflow-shape` answers "who should work on this". Enforcement lives in
the launcher you write:

1. pass the same intake file to every spawn;
2. refuse any role that is not in `staff` or `verifiers` of the resolved shape;
3. take the tier from the resolver, and refuse a caller-supplied tier that
   disagrees;
4. record the resolved shape on the spawned agent (a label or a task-board
   event) so an audit can reconstruct the decision.