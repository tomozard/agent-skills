# Runtime adapters

The team protocol is CLI-agnostic on purpose. A role is "supported" on this
machine only if its runtime can do the verbs below — not because its name is in
a list.

## The six verbs

| Verb | What it must do | If the runtime cannot |
|---|---|---|
| `launch` | start a role with its role prompt, model, working directory, and env | runtime cannot host a role |
| `ask` | run one prompt non-interactively and exit | role must become a persistent session |
| `send` | deliver a message into a session that is already running | use a file mailbox plus `ask`/`resume` (slower, must be declared) |
| `resume` | continue an existing session by id | role cannot join a revision loop |
| `model` | select the model at launch | the roster pair cannot be expressed; treat as unavailable |
| `permissions` | run without interactive prompts (headless) | require an explicit approval step per call |

`send` is not a CLI verb at all: delivery belongs to Herdr, which owns the panes
(`herdr agent prompt`, or `herdr pane run` plus an Enter keypress for a pane
Herdr does not recognise as an agent). Without Herdr there is no push channel;
fall back to a file inbox and an explicit tick, and say so in the plan instead of
pretending delivery happened. Never poll for a reply to compensate.

## Verified adapters

Probed with `scripts/runtime-probe` on this machine — versions are recorded so a
later CLI upgrade that renames a flag is visible as a docs bug, not a failed
spawn.

| runtime | version probed | `ask` | `model` | `system prompt` | `resume` | headless |
|---|---|---|---|---|---|---|
| `pi` | 1.5.0 | `pi -p "<prompt>"` | `--model provider/id` | `--system-prompt` | `--session` / `--session-id` | `-p` |
| `hermes` | v0.23.0 | `hermes -z "<prompt>"` | `-m` + `--provider` | SOUL profile + skills | session | `-z` |
| `codex` | 0.163.0 | `codex exec "<prompt>"` | `-m` | `AGENTS.md`, `-c` overrides | `codex resume --last` | `--full-auto` |
| `claude` | 2.1.318 | `claude -p "<prompt>"` | `--model` | `--append-system-prompt`, `--agents` | `--resume <id>` | `--dangerously-skip-permissions` |
| `opencode` | 2.2.5 | `opencode run "<prompt>"` | `-m provider/model` | `--agent` | `--continue` | agent config |
| `kiro-cli` | 2.37.1 | `kiro-cli chat --no-interactive` | `--model` | `--agent` | `--resume-id` | `--trust-all-tools` |

Role prompts are injected the way each CLI expects: pi and claude take a system
prompt, codex reads `AGENTS.md`, opencode and kiro-cli take `--agent`, hermes
uses its profile and skills. That difference lives here, not in the role
contracts — the contracts describe behaviour, not flags.

## Resolve before you spawn

```bash
./scripts/runtime-probe            # which CLIs exist, which verbs they expose
./scripts/roster coder critical    # role + tier -> runtime, model, selection, source
```

`roster` walks the configured candidates in order and returns the first pair
that is installed, allowlisted for that runtime, and not from a disabled
provider. It prints why each earlier candidate was rejected and exits 3 with
`[STUCK]` when nothing is usable.

Rules the roster enforces, which a plan may not override:

1. **Never invent an identifier.** A model that is not in the roster's allowlist
   for that runtime is refused, not normalized.
2. **Alternates stay in the tier.** An unavailable primary may fall to that
   tier's alternates only; the record must name the fallback reason.
3. **Nothing usable is `[STUCK]`.** Do not substitute a model from another tier,
   another provider, or another runtime to "make it run".
4. **A tier that no longer exists is an error.** `easy` and `advanced` were
   retired into `standard`; the resolver says so instead of guessing.

## What this skill does not do

- It does not install CLIs, log in, or hold credentials. `runtime-probe` runs
  `command -v` and reads help text only.
- It does not pick a runtime for you. `runtime_order` in the roster is a
  preference for reading the file, not a mandate: whichever runtime the roster
  resolves and the machine has is the one to launch.
- It does not switch runtime mid-task. A role's session stays on the runtime it
  started on; a move is a new spawn with a new verification pass.