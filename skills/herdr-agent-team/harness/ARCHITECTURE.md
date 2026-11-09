# Architecture

## Purpose

Provide the smallest maintainable runtime for independent Pi or Claude agents
coordinated through Herdr across multiple projects.

## Layers

```text
Human
  -> Global Orchestrator
     -> Project PM
        -> Planner Team
        -> Supervisor
           -> Worker Team
           -> Verifier Team

Herdr: workspace, tab, pane, state, input
Runtime adapter: Pi or Claude process launch
Protocol: push messages and bounded diagnostic inspection
```

Herdr owns terminal topology. This repository owns team topology. Pi and Claude
own agent execution. Those responsibilities must not be duplicated.

## Project Workspace

One Herdr workspace represents one project. Logical labels are stable; Herdr
IDs are opaque runtime values and must always be read from command responses.

| Tab | Contents |
|---|---|
| `manager-{project}` | PM, Supervisor |
| `planner-{project}` | Up to three active Planner specialists |
| `worker-{project}` | Coder, Refactor for one simple workstream |
| `worker-{project}-{workstream}` | Coder, Refactor for a named workstream |
| `verifier-{project}` | Reviewer, Tester |

Do not mix a generic Worker tab with workstream-specific Worker tabs in the
same project. Use the generic form for one stream and suffix every Worker tab
when there are multiple streams.

## Control Plane

- Orchestrator controls PM and has multi-project visibility.
- PM controls Planner agents and Supervisor within one project.
- Supervisor controls Worker and Verifier agents within one project.
- Non-controller agents do not control or inspect other panes.
- Cross-project work is routed through Orchestrator.

## Data Plane

- Planner Team produces an approved plan and supporting evidence.
- Worker Team changes the deliverable.
- Verifier Team independently evaluates the result.
- Reviewer and Tester do not silently repair findings; Supervisor routes a
  revision to Worker and requests fresh verification from the same selected
  Verifier agents in their existing panes. Fresh verification reruns the
  checks; it does not create another Verifier pane.

## Runtime Adapter

`agent-runtime` is the only place that knows Pi and Claude command syntax.

```text
runtime=auto
  -> healthy Pi? launch Pi
  -> otherwise healthy Claude? launch Claude
  -> otherwise fail with diagnostics
```

Role files are shared. Pi receives a combined common/role system prompt.
Claude runs the installed role as its main-session custom agent and always uses
`--dangerously-skip-permissions` as explicitly required by the runtime owner.

Runtime selection happens before the task starts. An active session is never
silently replaced by another runtime.

## Safety Boundaries

- Herdr control requires `HERDR_ENV=1`.
- Blocking wait commands are not part of this runtime.
- Transcript access is capability-limited by controller ownership.
- Coder and Refactor cannot launch on protected branches.
- Local commits require a Human-reviewed staged-diff artifact and an exact
  branch/diff/message SHA-256 authorization token; raw commits are blocked.
- Remote delivery requires exact human authorization for branch and commit.
- Installer writes only manifest-owned global files.

## Source of Truth Split

- `team.json` (routing, model allowlists) and the role contracts
  (`references/roles/*.md` in agent-skills) are the policy source. This repo's
  `.agents/team.json` and `.agents/agents/*.md` are the in-repo copies used by
  the validator and as the fallback when `~/.agents` is absent.
- `setup_harness.sh` links `~/.agents/team.json` to the agent-skills canonical
  file when present, otherwise copies it. Role prompts are still copied.
- Runtime scripts (`bin/`) stay here: they depend on the machine (Herdr app,
  ClickUp login, voice, `~/.agents` extensions) and are not moved into the skill.
- Keep the in-repo role prompts identical to the agent-skills copies; the
  validator checks the concrete runtime commands they name.

## Dependency Direction

```text
role definitions -> AGENTS.md + communication protocol
agent-team skill  -> herdr skill + spawn-agent
spawn-agent       -> agent-runtime + verify-pane-agent + herdr CLI
agent-runtime     -> team.json + role definitions + Pi/Claude CLI
setup_harness     -> repository source files
```

No product workflow, MCP server, vault, browser, slide, QA document pipeline,
or compatibility layer belongs in this repository.
