#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
FAKE_BIN="$TMP/bin"
mkdir -p "$REPO/src" "$FAKE_BIN"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Herdr Test"
printf '%s\n' 'const logoWidth = 64;' > "$REPO/src/logo.tsx"
git -C "$REPO" add src/logo.tsx
git -C "$REPO" commit -q -m baseline
git -C "$REPO" switch -c feature/micro -q

cat > "$FAKE_BIN/herdr" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$FAKE_BIN/herdr"

cd "$REPO"
printf '%s\n' 'const logoWidth = 96;' > src/logo.tsx
git add src/logo.tsx
HERDR_ENV=1 HERDR_PANE_ID=coder:p1 HERDR_TASK_BOARD_ENABLED=0 \
  HERDR_VERIFICATION_PROFILE=deterministic_micro \
  HERDR_SUBMIT_DELAY_SECONDS=0 HERDR_DELIVERY_SETTLE_SECONDS=0 \
  PATH="$FAKE_BIN:$PATH" bash -c '
    source "$1/.agents/skills/agent-shared/lib/agent-helpers.sh"
    agent_prepare_verification_candidate \
      pm:p1 coder pm micro "$2/candidate.txt" src/logo.tsx
  ' _ "$ROOT" "$TMP"
grep -q '^Verification Profile: deterministic_micro$' "$TMP/candidate.txt"

printf '%s\n' 'const logoWidth = 104;' 'const logoHeight = 42;' > src/logo.tsx
git add src/logo.tsx
if HERDR_ENV=1 HERDR_PANE_ID=coder:p1 HERDR_TASK_BOARD_ENABLED=0 \
  HERDR_VERIFICATION_PROFILE=deterministic_micro \
  HERDR_SUBMIT_DELAY_SECONDS=0 HERDR_DELIVERY_SETTLE_SECONDS=0 \
  PATH="$FAKE_BIN:$PATH" bash -c '
    source "$1/.agents/skills/agent-shared/lib/agent-helpers.sh"
    agent_prepare_verification_candidate \
      pm:p1 coder pm micro "$2/rejected.txt" src/logo.tsx
  ' _ "$ROOT" "$TMP"; then
  echo 'micro verification accepted a non-numeric line change' >&2
  exit 1
fi

printf '%s\n' 'micro verification tests: ok'
