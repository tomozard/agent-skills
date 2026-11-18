# AI Agent Skills

[![npm](https://img.shields.io/npm/v/herdr-agent-team.svg)](https://www.npmjs.com/package/herdr-agent-team)

Agent skills and workflows for coding agents, installable through
[skills.sh](https://skills.sh).

## `herdr-agent-team` — a delivery team, not a chat prompt

A multi-agent team for real repositories. Staffing, scope, and the commit gate are
decided by rules instead of by whoever holds the conversation:

- **Staffing is resolved.** One intake file maps to one of eleven shapes
  (`W0`–`W10`); a role the shape does not staff is a refused launch.
- **A commit needs a verified diff.** The Worker freezes the staged diff to a
  SHA-256, an independent Verifier passes that exact hash, and only a commit
  helper may create the commit.
- **The Human keeps four tokens.** Scope, commit, push, and PR.

Requires the [Herdr](https://herdr.dev/download/) desktop app (which ships for
macOS, Linux, and Windows) plus macOS for this harness today, Pi, Node 18+, and
Python 3 with PyYAML.

### Install

```bash
npx herdr-agent-team health                # read-only: is this machine ready?
npx -y herdr-agent-team@latest --yes       # skill layer + runtime layer + deep check
hteam check --deep
hteam
```

`hteam setup` walks through folder, vault, project registry, and voice;
`hteam model` pins routing in a machine overlay that survives updates;
`hteam agent` clones a role contract when a machine needs a variant;
`hteam health` re-checks the machine at any time and exits `3` when it cannot run
the team.

Pinned to a version: `npx -y herdr-agent-team@0.2.1 --yes`. Installing straight
from the repository works too: `npx -y github:tomozard/agent-skills --yes`.

The skills CLI copies files and cannot run install scripts, so this wrapper runs
both phases. The two commands, if you prefer them separate:

```bash
npx skills add tomozard/agent-skills/skills/herdr-agent-team -g -y -a pi claude-code
~/.agents/skills/herdr-agent-team/harness/setup_harness.sh
```

### Read next

| Who you are | Read |
|---|---|
| Setting it up yourself | **[Guide](https://tomozard.github.io/agent-skills/)** — install, components, team shapes, model routing, troubleshooting |
| An agent acting for you | **[Agent install runbook](https://tomozard.github.io/agent-skills/agent-install.html)** — exact steps and failure handling |
| Only reading files | [`docs/agent-install.md`](docs/agent-install.md) · [`docs/llms.txt`](docs/llms.txt) |
| Changing the policy | [`SKILL.md`](skills/herdr-agent-team/SKILL.md) · [`setup.md`](skills/herdr-agent-team/setup.md) |
| Cutting a release | [`docs/releasing.md`](docs/releasing.md) — bump, tag, staged publish, verify |

## Other skills

| Skill | Description | Install |
|---|---|---|
| `fullstack-design-patterns` | Guide, evaluate, and architect fullstack applications covering frontend component design, state management, and backend architecture. | `npx skills add tomozard/agent-skills/skills/fullstack-design-patterns` |
| `blender-plan-from-images` | Build and correct Blender house models from floor-plan images, with room-by-room checks and reference overlays. | `npx skills add tomozard/agent-skills/skills/blender-plan-from-images` |

Install every skill in this repository:

```bash
npx skills add tomozard/agent-skills
```

Or list and select interactively:

```bash
npx skills add tomozard/agent-skills --list
```

## Documentation site

The site is plain Markdown under [`docs/`](docs/) and needs no build step beyond
GitHub Pages. To publish it: **Settings → Pages → Source: Deploy from a branch →
`main` / `/docs`**. The entry points are `docs/index.md` (guide),
`docs/agent-install.md` (runbook), and `docs/llms.txt` (machine-readable).

[`docs/check.sh`](docs/check.sh) guards the docs against drift: every command and
every internal link mentioned there must resolve in this repository.

## Migration

The `hteam` skill was merged into `herdr-agent-team`. If you installed it
separately, run `npx skills remove hteam -g -y`; the `/hteam` command itself is
unaffected. The `herdr-team` TUI launcher remains a separate, unrelated entry
point.

## License

MIT — see [LICENSE](LICENSE).
