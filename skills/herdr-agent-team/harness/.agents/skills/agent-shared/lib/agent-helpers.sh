#!/usr/bin/env bash

# Shared message helpers for Herdr-managed agent panes.

# Delivery transport. The CLI runtime delivers through `herdr pane run`; the
# Herdr app runtime has no herdr server at all (calling it fails with
# server_not_running) and delivers through `hc send`, which pastes and submits
# in one step. A pane only ever has one of the two: pick it from the
# environment, never assume.
_agent_transport() {
  if [ -n "${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null 2>&1; then
    printf 'hc\n'
    return 0
  fi
  if command -v herdr >/dev/null 2>&1; then
    printf 'herdr\n'
    return 0
  fi
  return 1
}

# Kept under its historical name: every helper below already calls it.
_agent_require_herdr() {
  if [ "${HERDR_ENV:-}" != "1" ]; then
    echo "agent helper: HERDR_ENV=1 is required" >&2
    return 1
  fi
  if ! _agent_transport >/dev/null; then
    echo "agent helper: no delivery transport (need the herdr CLI or hc)" >&2
    return 1
  fi
}

_agent_require_value() {
  local name="$1" value="$2"
  if [ -z "$value" ]; then
    echo "agent helper: $name is required" >&2
    return 2
  fi
}

# Encode protocol fields only after message delivery has succeeded. This is
# optional bookkeeping and must never prevent the required Herdr delivery.
_agent_json_object() {
  python3 - "$@" <<'PY'
import json
import sys

values = sys.argv[1:]
if len(values) % 2:
    raise SystemExit("agent helper: JSON fields require key/value pairs")
print(json.dumps(dict(zip(values[::2], values[1::2])),
                 ensure_ascii=False, sort_keys=True, separators=(",", ":")))
PY
}

# Task Board is an optional, best-effort activity index. It never replaces the
# message delivery below and it must never make delivery fail. Controllers own
# authoritative transitions; these hooks only append protocol events.
_agent_task_board_event() {
  local task_id="${1:-}" event_type="${2:-protocol}" payload="${3:-}"
  local project="${HERDR_TASK_BOARD_PROJECT:-${HERDR_PROJECT:-}}"
  [ -n "$payload" ] || payload='{}'
  local board_bin="${HERDR_TASK_BOARD_BIN:-}"
  [ "${HERDR_TASK_BOARD_ENABLED:-1}" != "0" ] || return 0
  [ -n "$task_id" ] && [ "$task_id" != unspecified ] || return 0
  [ -n "$project" ] || return 0
  if [ -z "$board_bin" ]; then
    board_bin="$(command -v task-board 2>/dev/null || true)"
  fi
  [ -x "$board_bin" ] || [ -f "$board_bin" ] || return 0
  HERDR_TASK_BOARD_ROOT="${HERDR_TASK_BOARD_ROOT:-}" \
    "$board_bin" event "$project" "$task_id" \
    --type "$event_type" --payload "$payload" >/dev/null 2>&1 || true
}

_agent_require_target_pane() {
  local target_pane="$1" recipient="$2" sender="$3" sender_pane="${HERDR_PANE_ID:-}"
  if { [ -n "$sender_pane" ] && [ "$target_pane" = "$sender_pane" ]; } \
    || { [ -n "$sender" ] && [ "$target_pane" = "$sender" ] \
      && [ "$target_pane" != "$recipient" ]; }; then
    echo "agent helper: target pane $target_pane is the sender pane; pass the recipient pane as the first argument" >&2
    return 2
  fi
}

_agent_sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "agent helper: no SHA-256 utility found" >&2
    return 127
  fi
}

_agent_path_is_allowed() {
  local candidate="$1"
  shift
  local allowed
  for allowed in "$@"; do
    [ "$candidate" = "$allowed" ] && return 0
  done
  return 1
}

_agent_require_external_file() {
  local name="$1" file="$2" repo_root="$3" absolute
  absolute="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")" || return 1
  case "$absolute" in
    "$repo_root"|"$repo_root"/*)
      echo "agent helper: $name must be outside the repository: $absolute" >&2
      return 2
      ;;
  esac
  printf '%s\n' "$absolute"
}

_agent_write_staged_diff() {
  local output="$1"
  git diff --cached --binary --no-ext-diff --no-textconv \
    --src-prefix=a/ --dst-prefix=b/ > "$output"
}

_agent_write_commit_diff() {
  local output="$1" parent="$2" commit="$3"
  git diff --binary --no-ext-diff --no-textconv \
    --src-prefix=a/ --dst-prefix=b/ "$parent" "$commit" > "$output"
}

_agent_staged_diff_sha256() {
  local staged_file diff_sha256
  staged_file="$(mktemp "${TMPDIR:-/tmp}/herdr-staged-diff.XXXXXX")" || return 1
  _agent_write_staged_diff "$staged_file" || { rm -f "$staged_file"; return 1; }
  if [ ! -s "$staged_file" ]; then
    echo "agent helper: staged diff is empty" >&2
    rm -f "$staged_file"
    return 1
  fi
  if ! diff_sha256="$(_agent_sha256_file "$staged_file")"; then
    rm -f "$staged_file"
    return 1
  fi
  rm -f "$staged_file"
  printf '%s\n' "$diff_sha256"
}

_agent_require_staged_allowlist() (
  local staged_path staged_paths_file
  local allowed_files=("$@")

  staged_paths_file="$(mktemp "${TMPDIR:-/tmp}/herdr-staged-paths.XXXXXX")" || return 1
  trap 'rm -f "$staged_paths_file"' EXIT
  git diff --cached --name-only -z > "$staged_paths_file" || return 1
  while IFS= read -r -d '' staged_path; do
    if ! _agent_path_is_allowed "$staged_path" "${allowed_files[@]}"; then
      echo "agent helper: staged path is outside Allowed files: $staged_path" >&2
      return 1
    fi
  done < "$staged_paths_file"
)

# A deterministic micro candidate is narrower than a normal implementation
# candidate. It accepts only text-line replacements whose non-numeric content
# is unchanged. This keeps the fast lane useful for dimensions, copy, and
# style tokens without treating a normal code change as independently verified.
_agent_require_deterministic_micro_diff() (
  local diff_file
  diff_file="$(mktemp "${TMPDIR:-/tmp}/herdr-micro-diff.XXXXXX")" || return 1
  trap 'rm -f "$diff_file"' EXIT
  git diff --cached --check || return 1
  git diff --cached --unified=0 --no-ext-diff --no-textconv --no-color > "$diff_file" || return 1

  python3 - "$diff_file" <<'PY'
import re
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding="utf-8", errors="strict").splitlines()
removed = []
added = []
for line in lines:
    if line.startswith(("--- ", "+++ ", "@@ ")) or line == r"\\ No newline at end of file":
        continue
    if line.startswith("-"):
        removed.append(line[1:])
    elif line.startswith("+"):
        added.append(line[1:])

if not removed or not added:
    raise SystemExit("deterministic micro verification requires a text replacement")
if len(removed) != len(added):
    raise SystemExit("deterministic micro verification rejects added or deleted lines")

def normalized(value):
    return re.sub(r"[0-9]+", "#", value)

if [normalized(value) for value in removed] != [normalized(value) for value in added]:
    raise SystemExit("deterministic micro verification found a non-numeric change")
if all(left == right for left, right in zip(removed, added)):
    raise SystemExit("deterministic micro verification found no numeric change")
PY
)

_agent_require_frozen_allowed_files() {
  if ! git diff --quiet -- "$@"; then
    echo "agent helper: Allowed files changed after the staged candidate was frozen" >&2
    return 1
  fi
}

_agent_acquire_delivery_lock() {
  local pane="$1"
  local root="${HERDR_DELIVERY_LOCK_DIR:-${TMPDIR:-/tmp}/herdr-agent-delivery}"
  local interval="${HERDR_DELIVERY_LOCK_INTERVAL_SECONDS:-0.1}"
  local max_attempts="${HERDR_DELIVERY_LOCK_ATTEMPTS:-50}"
  local key lock attempt=0

  key="$(printf '%s' "$pane" | tr -c 'A-Za-z0-9._-' '_')"
  lock="$root/$key.lock"
  mkdir -p "$root" || return 1

  while ! mkdir "$lock" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "agent helper: delivery lock timed out for pane $pane" >&2
      return 75
    fi
    sleep "$interval"
  done

  printf '%s\n' "$lock"
}

send_and_submit() (
  local target_pane="${1:-}" from="${2:-}" to="${3:-}" message="${4:-}"
  local submit_delay="${HERDR_SUBMIT_DELAY_SECONDS:-1}"
  local retry_attempts="${HERDR_SUBMIT_RETRY_ATTEMPTS:-0}"
  local retry_delay="${HERDR_SUBMIT_RETRY_DELAY_SECONDS:-1}"
  local settle_delay="${HERDR_DELIVERY_SETTLE_SECONDS:-1}"
  local lock
  _agent_require_herdr || return $?
  _agent_require_value target_pane "$target_pane" || return $?
  _agent_require_value from "$from" || return $?
  _agent_require_value to "$to" || return $?
  _agent_require_value message "$message" || return $?
  _agent_require_target_pane "$target_pane" "$to" "$from" || return $?

  lock="$(_agent_acquire_delivery_lock "$target_pane")" || return $?
  trap 'rmdir "$lock" 2>/dev/null || true' EXIT

  case "$(_agent_transport)" in
    hc)
      if ! hc send "$target_pane" "$message"; then
        echo "agent helper: failed to deliver message to pane $target_pane" >&2
        return 1
      fi
      ;;
    herdr)
      if ! herdr pane run "$target_pane" "$message"; then
        echo "agent helper: failed to deliver message to pane $target_pane" >&2
        return 1
      fi
      sleep "$submit_delay"
      if ! herdr pane send-keys "$target_pane" enter; then
        echo "agent helper: failed to submit message in pane $target_pane" >&2
        return 1
      fi
      for ((attempt = 0; attempt < retry_attempts; attempt++)); do
        sleep "$retry_delay"
        if ! herdr pane send-keys "$target_pane" enter; then
          echo "agent helper: failed to submit retry in pane $target_pane" >&2
          return 1
        fi
      done
      ;;
  esac
  sleep "$settle_delay"
)

send_file_and_submit() {
  local target_pane="${1:-}" from="${2:-}" to="${3:-}" file="${4:-}" task_id="${5:-unspecified}"
  _agent_require_herdr || return $?
  _agent_require_value target_pane "$target_pane" || return $?
  _agent_require_value from "$from" || return $?
  _agent_require_value to "$to" || return $?
  _agent_require_value file "$file" || return $?
  _agent_require_target_pane "$target_pane" "$to" "$from" || return $?

  if [ ! -r "$file" ]; then
    echo "agent helper: file is not readable: $file" >&2
    return 2
  fi

  local absolute
  absolute="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  HERDR_SUBMIT_RETRY_ATTEMPTS="${HERDR_TASK_SUBMIT_RETRIES:-1}" \
  send_and_submit "$target_pane" "$from" "$to" \
    "[TASK_FILE] from: $from -> to: $to task=$task_id file=$absolute | Reply required: [ACK], then [DONE] or [STUCK]."
}

agent_ack() {
  local target_pane="${1:-}" from="${2:-}" to="${3:-}" task_id="${4:-unspecified}" payload
  send_and_submit "$target_pane" "$from" "$to" \
    "[ACK] from: $from -> to: $to task=$task_id" || return $?
  payload="$(_agent_json_object from "$from" to "$to" 2>/dev/null)" || true
  [ -n "$payload" ] && { _agent_task_board_event "$task_id" ACK "$payload"; } 2>/dev/null || true
}

agent_status() {
  local target_pane="${1:-}" from="${2:-}" to="${3:-}" task_id="${4:-unspecified}" state="${5:-}" payload
  _agent_require_value state "$state" || return $?
  send_and_submit "$target_pane" "$from" "$to" \
    "[STATUS] from: $from -> to: $to task=$task_id state=$state" || return $?
  payload="$(_agent_json_object from "$from" to "$to" state "$state" 2>/dev/null)" || true
  [ -n "$payload" ] && { _agent_task_board_event "$task_id" STATUS "$payload"; } 2>/dev/null || true
}

agent_done() {
  local target_pane="${1:-}" from="${2:-}" to="${3:-}" task_id="${4:-unspecified}" summary="${5:-completed}" payload
  send_and_submit "$target_pane" "$from" "$to" \
    "[DONE] from: $from -> to: $to task=$task_id summary=$summary" || return $?
  payload="$(_agent_json_object from "$from" to "$to" summary "$summary" 2>/dev/null)" || true
  [ -n "$payload" ] && { _agent_task_board_event "$task_id" DONE "$payload"; } 2>/dev/null || true
}

agent_stuck() {
  local target_pane="${1:-}" from="${2:-}" to="${3:-}" task_id="${4:-unspecified}" reason="${5:-}" payload
  _agent_require_value reason "$reason" || return $?
  send_and_submit "$target_pane" "$from" "$to" \
    "[STUCK] from: $from -> to: $to task=$task_id reason=$reason" || return $?
  payload="$(_agent_json_object from "$from" to "$to" reason "$reason" 2>/dev/null)" || true
  [ -n "$payload" ] && { _agent_task_board_event "$task_id" STUCK "$payload"; } 2>/dev/null || true
}

agent_pass() {
  local target_pane="${1:-}" from="${2:-}" to="${3:-}" task_id="${4:-unspecified}" evidence="${5:-}" payload
  _agent_require_value evidence "$evidence" || return $?
  send_and_submit "$target_pane" "$from" "$to" \
    "[PASS] from: $from -> to: $to task=$task_id evidence=$evidence" || return $?
  payload="$(_agent_json_object from "$from" to "$to" evidence "$evidence" 2>/dev/null)" || true
  [ -n "$payload" ] && { _agent_task_board_event "$task_id" PASS "$payload"; } 2>/dev/null || true
}

agent_changes_required() {
  local target_pane="${1:-}" from="${2:-}" to="${3:-}" task_id="${4:-unspecified}" findings="${5:-}" payload
  _agent_require_value findings "$findings" || return $?
  send_and_submit "$target_pane" "$from" "$to" \
    "[CHANGES_REQUIRED] from: $from -> to: $to task=$task_id findings=$findings" || return $?
  payload="$(_agent_json_object from "$from" to "$to" findings "$findings" 2>/dev/null)" || true
  [ -n "$payload" ] && { _agent_task_board_event "$task_id" CHANGES_REQUIRED "$payload"; } 2>/dev/null || true
}

agent_revision_gate() {
  local revision="${1:-}" findings_file="${2:-}"
  case "$revision" in
    1|2) ;;
    *)
      echo "agent helper: revision must be 1 or 2" >&2
      return 2
      ;;
  esac
  _agent_require_value findings_file "$findings_file" || return $?
  if [ ! -r "$findings_file" ]; then
    echo "agent helper: revision findings file is not readable: $findings_file" >&2
    return 2
  fi
  grep -Eq "Revision:[[:space:]]*$revision/2" "$findings_file" || {
    echo "agent helper: findings must record Revision: $revision/2" >&2
    return 1
  }
  grep -Eq '(^|[^A-Z])BLOCKER([^A-Z]|$)' "$findings_file" || {
    echo "agent helper: revision requires a BLOCKER finding" >&2
    return 1
  }
}

agent_verify_staged_diff() {
  local expected_diff_sha256="${1:-}" actual_diff_sha256
  _agent_require_value expected_diff_sha256 "$expected_diff_sha256" || return $?
  actual_diff_sha256="$(_agent_staged_diff_sha256)" || return $?
  if [ "$actual_diff_sha256" != "$expected_diff_sha256" ]; then
    echo "agent helper: staged diff changed: expected $expected_diff_sha256, got $actual_diff_sha256" >&2
    return 1
  fi
}

agent_prepare_verification_candidate() (
  local target_pane="${1:-}" from="${2:-}" to="${3:-}"
  local task_id="${4:-unspecified}" candidate_file="${5:-}"
  shift 5 || return 2
  local allowed_files=("$@") repo_root branch candidate_absolute
  local staged_file diff_sha256 event_payload

  _agent_require_herdr || return $?
  _agent_require_value target_pane "$target_pane" || return $?
  _agent_require_value from "$from" || return $?
  _agent_require_value to "$to" || return $?
  _agent_require_value candidate_file "$candidate_file" || return $?
  _agent_require_target_pane "$target_pane" "$to" "$from" || return $?
  if [ "${#allowed_files[@]}" -eq 0 ]; then
    echo "agent helper: at least one allowed file is required" >&2
    return 2
  fi

  repo_root="$(git rev-parse --show-toplevel)" || return 1
  candidate_absolute="$(_agent_require_external_file candidate_file "$candidate_file" "$repo_root")" || return $?
  branch="$(git branch --show-current)" || return 1
  case "$branch" in
    ""|main|master|dev|uat|prod)
      echo "agent helper: verification candidate requires a non-protected branch" >&2
      return 1
      ;;
  esac

  _agent_require_staged_allowlist "${allowed_files[@]}" || return $?
  local -a existing_allowed=() missing_allowed=()
  local _p
  for _p in "${allowed_files[@]}"; do
    if [ -e "$_p" ] || [ -L "$_p" ]; then
      existing_allowed+=("$_p")
    else
      missing_allowed+=("$_p")
    fi
  done
  if [ "${#existing_allowed[@]}" -gt 0 ]; then
    git add -- "${existing_allowed[@]}" || return 1
  fi
  if [ "${#missing_allowed[@]}" -gt 0 ]; then
    git rm --ignore-unmatch -- "${missing_allowed[@]}" >/dev/null 2>&1 || return 1
  fi
  _agent_require_staged_allowlist "${allowed_files[@]}" || return $?
  _agent_require_frozen_allowed_files "${allowed_files[@]}" || return $?

  case "${HERDR_VERIFICATION_PROFILE:-independent}" in
    independent) ;;
    deterministic_micro)
      _agent_require_deterministic_micro_diff || return $?
      ;;
    *)
      echo "agent helper: invalid HERDR_VERIFICATION_PROFILE" >&2
      return 1
      ;;
  esac

  staged_file="$(mktemp "${TMPDIR:-/tmp}/herdr-verification-diff.XXXXXX")" || return 1
  trap 'rm -f "$staged_file"' EXIT
  _agent_write_staged_diff "$staged_file" || return 1
  if [ ! -s "$staged_file" ]; then
    echo "agent helper: staged diff is empty" >&2
    return 1
  fi
  diff_sha256="$(_agent_sha256_file "$staged_file")" || return $?

  {
    printf 'Herdr verification candidate\n\n'
    printf 'Branch: %s\n' "$branch"
    printf 'Candidate Diff SHA-256: %s\n' "$diff_sha256"
    printf 'Verification Profile: %s\n' "${HERDR_VERIFICATION_PROFILE:-independent}"
    printf '\n----- BEGIN STAGED DIFF -----\n'
    command cat "$staged_file"
    printf '\n----- END STAGED DIFF -----\n'
  } > "$candidate_absolute" || return 1

  send_and_submit "$target_pane" "$from" "$to" \
    "[READY_FOR_VERIFICATION] from: $from -> to: $to task=$task_id artifact=$candidate_absolute branch=$branch diff=$diff_sha256 verification=${HERDR_VERIFICATION_PROFILE:-independent}" || return $?
  event_payload="$(_agent_json_object from "$from" to "$to" artifact "$candidate_absolute" \
    branch "$branch" diff "$diff_sha256" verification_profile "${HERDR_VERIFICATION_PROFILE:-independent}" 2>/dev/null)" || true
  [ -n "$event_payload" ] && { _agent_task_board_event "$task_id" READY_FOR_VERIFICATION "$event_payload"; } 2>/dev/null || true
)

agent_prepare_commit_review() (
  local target_pane="${1:-}" from="${2:-}" to="${3:-}"
  local task_id="${4:-unspecified}" verified_diff_sha256="${5:-}"
  local message_file="${6:-}" review_file="${7:-}"
  shift 7 || return 2
  local allowed_files=("$@") repo_root branch message_absolute review_absolute
  local staged_file diff_sha256 message_sha256 event_payload approval marker

  _agent_require_herdr || return $?
  _agent_require_value target_pane "$target_pane" || return $?
  _agent_require_value from "$from" || return $?
  _agent_require_value to "$to" || return $?
  _agent_require_value verified_diff_sha256 "$verified_diff_sha256" || return $?
  _agent_require_value message_file "$message_file" || return $?
  _agent_require_value review_file "$review_file" || return $?
  _agent_require_target_pane "$target_pane" "$to" "$from" || return $?
  if [ "${#allowed_files[@]}" -eq 0 ]; then
    echo "agent helper: at least one allowed file is required" >&2
    return 2
  fi
  if [ ! -s "$message_file" ]; then
    echo "agent helper: commit message file is missing or empty: $message_file" >&2
    return 2
  fi

  repo_root="$(git rev-parse --show-toplevel)" || return 1
  message_absolute="$(_agent_require_external_file message_file "$message_file" "$repo_root")" || return $?
  review_absolute="$(_agent_require_external_file review_file "$review_file" "$repo_root")" || return $?
  branch="$(git branch --show-current)" || return 1
  case "$branch" in
    ""|main|master|dev|uat|prod)
      echo "agent helper: commit review requires a non-protected branch" >&2
      return 1
      ;;
  esac

  _agent_require_staged_allowlist "${allowed_files[@]}" || return $?
  _agent_require_frozen_allowed_files "${allowed_files[@]}" || return $?

  staged_file="$(mktemp "${TMPDIR:-/tmp}/herdr-staged-diff.XXXXXX")" || return 1
  trap 'rm -f "$staged_file"' EXIT
  _agent_write_staged_diff "$staged_file" || return 1
  if [ ! -s "$staged_file" ]; then
    echo "agent helper: staged diff is empty" >&2
    return 1
  fi
  diff_sha256="$(_agent_sha256_file "$staged_file")" || return $?
  if [ "$diff_sha256" != "$verified_diff_sha256" ]; then
    echo "agent helper: staged diff no longer matches verified diff: expected $verified_diff_sha256, got $diff_sha256" >&2
    return 1
  fi
  message_sha256="$(_agent_sha256_file "$message_absolute")" || return $?
  case "${HERDR_COMMIT_MODE:-manual}" in
    manual) approval="APPROVE_COMMIT"; marker="AWAITING_HUMAN_COMMIT" ;;
    auto) approval="AUTO_COMMIT"; marker="AUTO_COMMIT_READY" ;;
    *)
      echo "agent helper: invalid HERDR_COMMIT_MODE" >&2
      return 1
      ;;
  esac

  {
    printf 'Herdr commit review\n\n'
    printf 'Branch: %s\n' "$branch"
    printf 'Diff SHA-256: %s\n' "$diff_sha256"
    printf 'Verified Diff SHA-256: %s\n' "$verified_diff_sha256"
    printf 'Message SHA-256: %s\n' "$message_sha256"
    printf 'Approval: %s\n' "$approval"
    printf '\n----- BEGIN COMMIT MESSAGE -----\n'
    command cat "$message_absolute"
    printf '\n----- END COMMIT MESSAGE -----\n'
    printf '\n----- BEGIN STAGED DIFF -----\n'
    command cat "$staged_file"
    printf '\n----- END STAGED DIFF -----\n'
  } > "$review_absolute" || return 1

  send_and_submit "$target_pane" "$from" "$to" \
    "[$marker] from: $from -> to: $to task=$task_id artifact=$review_absolute branch=$branch diff=$diff_sha256 message_sha256=$message_sha256" || return $?
  event_payload="$(_agent_json_object from "$from" to "$to" artifact "$review_absolute" \
    branch "$branch" diff "$diff_sha256" message_sha256 "$message_sha256" 2>/dev/null)" || true
  [ -n "$event_payload" ] && { _agent_task_board_event "$task_id" "$marker" "$event_payload"; } 2>/dev/null || true
)

agent_authorized_commit() (
  local branch="${1:-}" diff_sha256="${2:-}" message_file="${3:-}"
  local authorization="${4:-}" message_absolute message_sha256
  local actual_branch parent committed_file committed_diff_sha256 commit
  _agent_require_herdr || return $?
  _agent_require_value branch "$branch" || return $?
  _agent_require_value diff_sha256 "$diff_sha256" || return $?
  _agent_require_value message_file "$message_file" || return $?
  _agent_require_value authorization "$authorization" || return $?
  if [ ! -s "$message_file" ]; then
    echo "agent helper: commit message file is missing or empty: $message_file" >&2
    return 2
  fi

  message_absolute="$(cd "$(dirname "$message_file")" && pwd)/$(basename "$message_file")" || return 1
  message_sha256="$(_agent_sha256_file "$message_absolute")" || return $?
  case "$authorization" in
    APPROVE_COMMIT) ;;
    AUTO_COMMIT)
      if [ "${HERDR_COMMIT_MODE:-manual}" != "auto" ]; then
        echo "agent helper: AUTO_COMMIT requires scope-approved auto commit mode" >&2
        return 1
      fi
      ;;
    *)
      echo "agent helper: commit approval must be APPROVE_COMMIT or AUTO_COMMIT" >&2
      return 1
      ;;
  esac

  actual_branch="$(git branch --show-current)" || return 1
  if [ "$actual_branch" != "$branch" ]; then
    echo "agent helper: current branch does not match authorization: $actual_branch" >&2
    return 1
  fi
  agent_verify_staged_diff "$diff_sha256" || return $?
  parent="$(git rev-parse HEAD)" || return 1

  HERDR_COMMIT_AUTHORIZATION="$authorization" \
  HERDR_COMMIT_BRANCH="$branch" \
  HERDR_COMMIT_DIFF="$diff_sha256" \
  HERDR_COMMIT_MESSAGE_SHA256="$message_sha256" \
  HERDR_COMMIT_MESSAGE_FILE="$message_absolute" \
    git commit --cleanup=verbatim -F "$message_absolute" || return $?

  commit="$(git rev-parse HEAD)" || return 1
  committed_file="$(mktemp "${TMPDIR:-/tmp}/herdr-committed-diff.XXXXXX")" || return 1
  trap 'rm -f "$committed_file"' EXIT
  _agent_write_commit_diff "$committed_file" "$parent" "$commit" || return 1
  committed_diff_sha256="$(_agent_sha256_file "$committed_file")" || return $?
  if [ "$committed_diff_sha256" != "$diff_sha256" ]; then
    echo "agent helper: committed diff does not match the Human-authorized diff" >&2
    return 1
  fi
  printf '%s\n' "$commit"
)

agent_auto_commit() (
  if [ "${HERDR_COMMIT_MODE:-manual}" != "auto" ]; then
    echo "agent helper: auto commit was not approved in the scope lock" >&2
    return 1
  fi
  agent_authorized_commit "${1:-}" "${2:-}" "${3:-}" AUTO_COMMIT
)

agent_authorized_push() (
  local branch="${1:-}" commit="${2:-}" authorization="${3:-}"
  _agent_require_herdr || return $?
  _agent_require_value branch "$branch" || return $?
  _agent_require_value commit "$commit" || return $?
  _agent_require_value authorization "$authorization" || return $?

  if [ "$authorization" != "APPROVE_PUSH" ]; then
    echo "agent helper: push approval must be APPROVE_PUSH" >&2
    return 1
  fi
  HERDR_PUSH_AUTHORIZATION="$authorization" \
  HERDR_PUSH_BRANCH="$branch" \
  HERDR_PUSH_COMMIT="$commit" \
    git push origin "$branch"
)

agent_authorized_pr_create() (
  local base="${1:-}" head="${2:-}" commit="${3:-}" title="${4:-}"
  local body_file="${5:-}" authorization="${6:-}"
  local remote_url remote_host body_text
  _agent_require_herdr || return $?
  _agent_require_value base "$base" || return $?
  _agent_require_value head "$head" || return $?
  _agent_require_value commit "$commit" || return $?
  _agent_require_value title "$title" || return $?
  _agent_require_value body_file "$body_file" || return $?
  _agent_require_value authorization "$authorization" || return $?
  if [ ! -r "$body_file" ]; then
    echo "agent helper: PR body file is not readable: $body_file" >&2
    return 2
  fi

  if [ "$authorization" != "APPROVE_PR_DEV" ]; then
    echo "agent helper: PR approval must be APPROVE_PR_DEV" >&2
    return 1
  fi
  remote_url="$(git remote get-url origin)" || return $?
  case "$remote_url" in
    *://*)
      remote_host="${remote_url#*://}"
      remote_host="${remote_host%%/*}"
      remote_host="${remote_host##*@}"
      remote_host="${remote_host%%:*}"
      ;;
    *@*:*)
      remote_host="${remote_url#*@}"
      remote_host="${remote_host%%:*}"
      ;;
    *)
      echo "agent helper: unsupported origin URL: $remote_url" >&2
      return 1
      ;;
  esac
  if [ -z "$remote_host" ]; then
    echo "agent helper: origin host is empty" >&2
    return 1
  fi
  export HERDR_PR_CREATE_AUTHORIZATION="$authorization"
  export HERDR_PR_CREATE_BASE="$base"
  export HERDR_PR_CREATE_HEAD="$head"
  export HERDR_PR_CREATE_COMMIT="$commit"
  case "$remote_host" in
    *gitlab*|*git-lab*)
      body_text="$(cat "$body_file")" || return $?
      [ -n "$body_text" ] || { echo "agent helper: MR body is empty" >&2; return 1; }
      HERDR_PR_CREATE_BODY_FILE="$body_file" \
        glab mr create --repo "$remote_url" \
          --source-branch "$head" --target-branch "$base" \
          --title "$title" --description "$body_text" --yes
      ;;
    *)
      gh pr create --base "$base" --head "$head" --title "$title" \
        --body-file "$body_file"
      ;;
  esac
)

# Jev advisory second signal (optional, never binding).
# Bypass: HERDR_JEV_ENABLED=0, missing key, or missing curl/python3 all skip
# with exit 0 so the LLM-only path continues unchanged. This helper never
# approves, commits, pushes, or creates PRs; it only prints the upstream
# decision JSON (or a {"status":"skipped",...} envelope) to stdout.
# Key source: HERDR_ZEN_API_KEY (or ZEN_API_KEY). Nothing is read from
# opencode auth.json and the key is never printed.
# Usage: agent_jev_advisory <state_file> <questions_file>
agent_jev_advisory() (
  local state_file="${1:-}" questions_file="${2:-}"
  local key model url timeout_seconds payload_file response curl_status
  if [ -z "$state_file" ] || [ -z "$questions_file" ]; then
    echo "agent helper: agent_jev_advisory requires <state_file> <questions_file>" >&2
    return 2
  fi
  if [ "${HERDR_JEV_ENABLED:-1}" = "0" ]; then
    printf '{"status":"skipped","reason":"disabled"}\n'
    return 0
  fi
  key="${HERDR_ZEN_API_KEY:-${ZEN_API_KEY:-}}"
  if [ -z "$key" ]; then
    echo "agent helper: Jev skipped (no Zen API key)" >&2
    printf '{"status":"skipped","reason":"missing_key"}\n'
    return 0
  fi
  if [ ! -r "$state_file" ]; then
    echo "agent helper: state file is not readable: $state_file" >&2
    return 2
  fi
  if [ ! -r "$questions_file" ]; then
    echo "agent helper: questions file is not readable: $questions_file" >&2
    return 2
  fi
  if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "agent helper: Jev skipped (curl or python3 not found)" >&2
    printf '{"status":"skipped","reason":"missing_tool"}\n'
    return 0
  fi
  model="${HERDR_JEV_MODEL:-jev-1.13}"
  url="${HERDR_ZEN_SYSTEMONE_URL:-https://opencode.ai/zen/v1/systemone}"
  timeout_seconds="${HERDR_JEV_TIMEOUT_SECONDS:-30}"
  payload_file="$(mktemp "${TMPDIR:-/tmp}/herdr-jev.XXXXXX")" || return 1
  trap 'rm -f "$payload_file"' EXIT
  if ! python3 - "$state_file" "$questions_file" "$model" "$payload_file" <<'PY'; then
import json
import sys
state_file, questions_file, model, payload_file = sys.argv[1:5]
with open(state_file, encoding="utf-8") as fh:
    state = fh.read()
with open(questions_file, encoding="utf-8") as fh:
    questions = json.load(fh)
if not isinstance(questions, dict) or not questions:
    raise SystemExit("agent helper: questions file must be a non-empty JSON object")
with open(payload_file, "w", encoding="utf-8") as fh:
    json.dump({"state": state, "model": model, "questions": questions}, fh, ensure_ascii=False)
PY
    echo "agent helper: invalid Jev state/questions input" >&2
    return 2
  fi
  response="$(curl --fail --silent --show-error --max-time "$timeout_seconds" \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $key" \
    --data "@$payload_file" 2>/dev/null)" || curl_status=$?
  if [ -n "${curl_status:-}" ]; then
    echo "agent helper: Jev skipped (request failed)" >&2
    printf '{"status":"skipped","reason":"request_failed"}\n'
    return 0
  fi
  printf '%s\n' "$response"
)
