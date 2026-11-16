# Placement

| Room | Who gets it |
|---|---|
| one space per project | every role of that project, and nothing else |
| a tab | orchestrator and PM — the two the Human talks in |
| a child terminal of its controller | every role below PM |

A child is `hc run --bg --parent <controller>` and inherits the controller's
working context; it ends when the controller ends. Start one with
`--outlive-parent` only when the work is deliberately meant to survive its
controller, and say why in the plan.

Rules that follow from the placement:

- **The controller closes what it opened.** PM closes its children when the task
  ends — reports collected, verification and commit gate reached, or `[STUCK]` —
  and a worker closes any child it opened before reporting.
- **Cleanup cascades.** Killing a controller ends its descendants, so nobody has
  to hunt grandchildren.
- **Depth is allowed, visibility is not.** Nesting works at any depth and
  `hc ls` shows the parent chain, but a sidebar renders one level; use `hc ls`
  when you need to know who belongs to whom.
- **Name by role and project** (`{role}-{project}` or
  `{role}-{project}-{workstream}`) so a terminal is identifiable without reading
  its transcript.
