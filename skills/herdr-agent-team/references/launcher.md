# Launcher — `hteam` in the Herdr app

`hteam` is the Human's alias for `bin/herdr-app-team`, the launcher that starts
the agent-team Orchestrator **inside the Herdr desktop app** (an `herdr-app`
window whose terminals live in `herdr-core`). It is not a chat instruction and
not a task prompt: a bare `hteam` in a chat pane means "run the launcher".

This page is the operator entry point. The delivery discipline — staffing,
scope, verification, commit gates — is the rest of this skill.

Two runtimes exist and they do not share state:

| | launcher | transport | scope |
|---|---|---|---|
| Herdr app | `bin/herdr-app-team` (`hteam`) | `hc send/read/run`, `herdr-app do` | this skill (app runtime) |
| herdr TUI | `bin/herdr-team` | `herdr pane run/read` | not this skill |

Never substitute one for the other, never use `tmux`, and never call the `herdr`
TUI binary from an app terminal.

## Before you act

```bash
hteam check          # app reachable, repo, role files, registry, voice
```

`check` needs no model turn and changes nothing. If it fails, report the failing
line instead of trying another path.

Bare `hteam` in a chat pane:

- in a Pi session the real command is the slash command `/hteam`;
- in an app terminal that already runs a team role the launcher refuses on
  purpose (`HERDR_AGENT_ROLE` is set) — that pane must talk to its own
  controller, not open a second team;
- everywhere else it starts (or reports) the Orchestrator. Re-running reports
  the live Orchestrator instead of stacking tabs.

## Commands

```bash
hteam                        # start (or report) the Orchestrator in the app
hteam check                  # validate prerequisites only
hteam --voice on|off         # short Thai status speech from Orchestrator and PM
hteam --space NAME           # control space (default: Herdr Team)
hteam --folder PATH          # where team terminals start (default ~/Workspaces)
```

There is no ClickUp intake watcher: work reaches a PM because the Human hands
it over in the PM pane, not because anything polls a list.

## Per-machine config

`/hteam setup` (Pi) or `hteam-config` writes `~/.config/herdr-team/hteam.yaml`:
`space`, `folder`, `voice`, `repo`, `registry`, `vault`, `activity_log`.

```bash
hteam-config show        # effective values + where each came from
hteam-config show --json
hteam-config get voice
hteam-config set voice off    # unrelated keys are kept
hteam-config write --json '{"space":"Herdr Team","voice":"on"}'
hteam-config validate
hteam-config path
```

Precedence is **flag > env > file > default**; deleting a key falls back to the
built-in default. An invalid value is refused before anything is written.

## Voice engine

Voice is per launch (`--voice on`, or `HERDR_VOICE_MODE=on`, forwarded to every
child). The engine is VoiceStudio `omnivoice` through `bin/tts-speak-omni`; the
Thai-native profile is `c3141426` at speed 0.9 with a light band-pass chain
(120 Hz–7.5 kHz, gentle compression, -16 LUFS, no reverb). gTTS is the fallback
when VoiceStudio is not running, so a machine without the backend still speaks.
`HERDR_GTTS_CLI` selects the gTTS binary, `HERDR_VOICE_SPEED` the rate,
`VS_URL`/`TTS_OMNI_VOICE` the backend and profile. There is no macOS `say`
fallback.

## Requirements

The payload ships with this skill (`harness/`): the binaries, role files,
`team.json`, registry and the `setup_harness.sh` installer. If
`command -v hteam` is empty, the payload is not installed.

Follow [`../setup.md`](../setup.md) in order — do not reconstruct the launcher,
and do not copy files into `~/bin` by hand.

The launcher starts agents through `bin/agent-runtime`, which picks the runtime
from the task tier in `team.json` (`standard` → pi, `critical` → claude) and
applies the role policy. Keep that decision there; never pass a model the tier
does not route to.

## Failure modes worth recognising

- **"Already inside a team terminal"** — the pane runs a team role
  (`HERDR_AGENT_ROLE`); this is a refusal, not a bug.
- **Orchestrator tab appears but stays silent** — read it with
  `hc read <terminal> --lines 200`; a role that never got its brief has no
  conversation to show.
- **A child waits forever at a dialog** — Claude Code asks to trust a new folder
  (the adapter pre-registers it), or a hook wants confirmation for a command
  that carries a secret. Answer or stop; do not retry blindly.
- **Space outlives the team** — `herdr app do space.close --id <space> --confirmed true`
  ends the space and its terminals.
