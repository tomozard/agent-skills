#!/usr/bin/env bash
#
# Docs drift guard: every command and every internal link the guide mentions must
# exist in this repository. Run before publishing the site:
#
#   docs/check.sh
#
# It does not build the site. It answers "did we rename a command and forget the
# page?", which is the failure that makes an install guide worse than no guide.

set -euo pipefail

DOCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DOCS_DIR/.." && pwd)"

python3 - "$ROOT" "$DOCS_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
docs = Path(sys.argv[2])
skill = root / "skills" / "herdr-agent-team"

# Documented command -> the file that must exist in this repository.
COMMANDS = {
    "hteam": skill / "harness/bin/herdr-app-team",
    "herdr-app-team": skill / "harness/bin/herdr-app-team",
    "herdr-team": skill / "harness/bin/herdr-team",
    "hteam-config": skill / "harness/bin/hteam-config",
    "hteam-dispatch": skill / "harness/bin/hteam-dispatch",
    "hteam-shutdown": skill / "harness/bin/hteam-shutdown",
    "agent-runtime": skill / "harness/bin/agent-runtime",
    "spawn-agent": skill / "harness/bin/spawn-agent",
    "herdr-app-spawn-role": skill / "harness/bin/herdr-app-spawn-role",
    "verify-pane-agent": skill / "harness/bin/verify-pane-agent",
    "agent-team-shutdown": skill / "harness/bin/agent-team-shutdown",
    "workflow-shape": skill / "harness/bin/workflow-shape",
    "task-board": skill / "harness/bin/task-board",
    "roster": skill / "scripts/roster",
    "runtime-probe": skill / "scripts/runtime-probe",
    "clickup-status": skill / "harness/bin/clickup-status",
    "validate-okf": skill / "harness/bin/validate-okf",
    "voice-notify": skill / "harness/bin/voice-notify",
    "tts-speak-omni": skill / "harness/bin/tts-speak-omni",
    "setup_harness.sh": skill / "harness/setup_harness.sh",
    "uninstall.sh": skill / "harness/uninstall.sh",
    "herdr-install": root / "bin/herdr-install",
    "check.sh": docs / "check.sh",
}

# Link targets on the site <-> markdown source.
PAGE = {".html": ".md"}

problems = []

def check_command(token, where):
    path = COMMANDS.get(token)
    if path is None:
        return
    if not path.is_file():
        problems.append(f"{where}: documented command '{token}' has no file at {path.relative_to(root)}")

def scan_text(text, where):
    # Fenced blocks: first word of each line, minus a prompt sigil.
    for match in re.finditer(r"```[a-z]*\n(.*?)```", text, re.S):
        for line in match.group(1).splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            line = re.sub(r"^\$\s+", "", line)
            check_command(line.split()[0], where)
    # Inline spans.
    for span in re.findall(r"`([^`\n]+)`", text):
        span = span.strip()
        if not span or " " in span.split("=")[0]:
            pass
        token = span.split()[0]
        check_command(token, where)

def scan_links(text, where, base):
    for target in re.findall(r"\]\(([^)]+)\)", text):
        target = target.strip()
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        path = target.split("#", 1)[0]
        if not path:
            continue
        candidate = base / path
        if base == docs and candidate.suffix in PAGE:
            candidate = candidate.with_suffix(PAGE[candidate.suffix])
        if not candidate.exists():
            problems.append(f"{where}: link '{target}' does not resolve to {candidate.relative_to(root)}")

for page in sorted(docs.glob("*.md")):
    text = page.read_text(encoding="utf-8")
    where = page.relative_to(root)
    scan_text(text, where)
    scan_links(text, where, docs)

readme = root / "README.md"
if readme.is_file():
    readme_text = readme.read_text(encoding="utf-8")
    scan_text(readme_text, "README.md")
    scan_links(readme_text, "README.md", root)

if problems:
    print("docs/check.sh: drift found", file=sys.stderr)
    for item in problems:
        print(f"  {item}", file=sys.stderr)
    raise SystemExit(1)

print(f"docs/check.sh: ok ({len(COMMANDS)} documented commands, {len(list(docs.glob('*.md')))} pages)")
PY
