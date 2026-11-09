#!/usr/bin/env bash

# Project-managed Thai TTS adapter: gTTS only.
#
# Speak a short Thai line with gtts-cli, caching by text+speed so a repeated line
# costs no network. There is deliberately no local model and no offline `say`
# fallback: if gTTS cannot run (no network, missing CLI) the adapter says so on
# stderr and exits non-zero instead of switching to a voice nobody chose.

set -u

TEXT="${1:-}"
[ -n "$TEXT" ] || exit 0

# Preferred engine: VoiceStudio OmniVoice with the Thai-native profile the Human
# approved (band-pass PA chain, speed 0.9). Falls back to gTTS below when the
# backend is not running, so a machine without VoiceStudio still speaks.
OMNI_BIN="${TTS_OMNI_BIN:-$HOME/bin/tts-speak-omni}"
if [ -x "$OMNI_BIN" ] && [ "${TTS_OMNI_DISABLE:-0}" != "1" ] \
  && curl -s --max-time 2 -o /dev/null --fail "${VS_URL:-http://127.0.0.1:3900}/.well-known/voicestudio-speech"; then
  exec "$OMNI_BIN" "$TEXT"
fi

# Thai accent for English loanwords: the engine's accent comes from the voice,
# so the only lever is Thai script. Unknown words stay Latin on purpose.
ACCENT_BIN="${TTS_THAI_ACCENT_BIN:-$HOME/bin/thai-accent}"
if [ -x "$ACCENT_BIN" ] && [ "${TTS_THAI_ACCENT:-0}" = "1" ]; then
  ACCENTED="$(printf '%s' "$TEXT" | "$ACCENT_BIN")" && TEXT="$ACCENTED"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEED="${HERDR_VOICE_SPEED:-1.0}"
CACHE_DIR="${HERDR_VOICE_CACHE_DIR:-$SCRIPT_DIR/tts-cache}"
TMP_DIR="$CACHE_DIR/.tmp"
AFPLAY="${TTS_THAI_AFPLAY:-/usr/bin/afplay}"

find_gtts() {
  local cli="${HERDR_GTTS_CLI:-}"
  if [ -n "$cli" ] && [ -x "$cli" ]; then
    printf '%s' "$cli"
    return 0
  fi
  local candidate
  for candidate in \
    "$SCRIPT_DIR/tts-venv/bin/gtts-cli" \
    "$HOME/.codex/tts-venv/bin/gtts-cli" \
    "$HOME/.config/opencode/tts-venv/bin/gtts-cli"; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  candidate="$(command -v gtts-cli 2>/dev/null || true)"
  [ -n "$candidate" ] || return 1
  printf '%s' "$candidate"
}

speak() {
  local cli="$1"
  local hash file raw
  mkdir -p "$CACHE_DIR" "$TMP_DIR" 2>/dev/null || return 1

  hash="$(printf '%s|%s' "$TEXT" "$SPEED" | shasum -a 256 | cut -c1-16)"
  file="$CACHE_DIR/gtts-$hash.mp3"
  raw="$TMP_DIR/gtts-$hash.raw.mp3"

  if [ -s "$file" ]; then
    echo "tts-thai: provider=gtts cache=hit"
    "$AFPLAY" "$file" >/dev/null 2>&1
    return $?
  fi

  if ! "$cli" --lang th --output "$raw" "$TEXT" >/dev/null 2>&1; then
    rm -f "$raw"
    return 1
  fi
  [ -s "$raw" ] || { rm -f "$raw"; return 1; }

  if [ "$SPEED" != "1.0" ] && command -v ffmpeg >/dev/null 2>&1; then
    if ! ffmpeg -y -i "$raw" -filter:a "atempo=$SPEED" "$file" >/dev/null 2>&1; then
      mv "$raw" "$file"
    fi
  else
    mv "$raw" "$file"
  fi
  rm -f "$raw"

  echo "tts-thai: provider=gtts cache=miss"
  "$AFPLAY" "$file" >/dev/null 2>&1
}

GTTS_CLI="$(find_gtts)" || {
  echo "tts-thai: gtts-cli not found (set HERDR_GTTS_CLI or install gTTS in a venv)" >&2
  exit 1
}

if ! speak "$GTTS_CLI"; then
  echo "tts-thai: gtts failed (network or endpoint error); nothing was spoken" >&2
  exit 1
fi