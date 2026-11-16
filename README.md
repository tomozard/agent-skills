# AI Agent Skills

A curated collection of AI Agent skills and architectural workflows for coding agents via [skills.sh](https://skills.sh).

## Available Skills

| Skill | Description | Direct Install Command |
| :--- | :--- | :--- |
| `fullstack-design-patterns` | Guide, evaluate, and architect fullstack applications covering modern Frontend UI component design, state management, and robust Backend architecture. | `npx skills add tomozard/agent-skills/skills/fullstack-design-patterns` |
| `blender-plan-from-images` | Build and correct Blender house models from floor-plan images, with room-by-room checks and reference overlays. | `npx skills add tomozard/agent-skills/skills/blender-plan-from-images` |
| `herdr-agent-team` | Run a multi-agent delivery team with enforced staffing, scope locks and verification gates — and start or check that team in the Herdr desktop app with the `hteam` launcher. Ships a workflow-shape resolver, a durable task board, 12 role contracts, the delivery protocol and the launcher docs. | `npx skills add tomozard/agent-skills/skills/herdr-agent-team` |

> **Migration:** the `hteam` skill was merged into `herdr-agent-team`. If you
> installed it separately, run `npx skills remove hteam -g -y` and install
> `herdr-agent-team` — the `/hteam` command itself is unaffected.

### herdr-agent-team — full install (policy + runtime)

`npx skills add` installs the policy layer only; the skills CLI cannot run
install scripts. Two commands install everything, runnable from any directory:

```bash
npx skills add tomozard/agent-skills/skills/herdr-agent-team -g -y -a pi claude-code
~/.agents/skills/herdr-agent-team/harness/setup_harness.sh
```

Then `hteam check` and `hteam`. `-a pi claude-code` scopes the skill to the two
runtimes the team supports; without it `npx skills` links every detected agent.
Use `--skip-validate` only after machine-local routing edits.

## Installation

Install all skills in this repository:

```bash
npx skills add tomozard/agent-skills
```

Or list and select skills interactively:

```bash
npx skills add tomozard/agent-skills --list
```
