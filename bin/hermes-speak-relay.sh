#!/usr/bin/env bash
# hermes-speak-relay.sh — install this on the machine that runs your
# Hermes agent (same host as HERMES_HOME). It is the ONLY thing the
# laptop-side script is allowed to call: reads the dictated text
# (argv[1], $SSH_ORIGINAL_COMMAND, or stdin — whichever is present),
# runs ONE `hermes chat -Q` turn, and prints the clean reply.
#
# Session continuity: replies are threaded into one resumable session
# (~/.ilo/voxtype-dictate-session.txt by default) so repeated dictations
# stay one conversation instead of starting fresh every time.
set -uo pipefail

TEXT="${1:-${SSH_ORIGINAL_COMMAND:-}}"
if [ -z "$TEXT" ] && [ ! -t 0 ]; then
  TEXT="$(cat)"
fi
if [ -z "$TEXT" ]; then
  echo "I didn't catch any words."
  exit 0
fi

SID_FILE="${HERMES_SPEAK_SESSION_FILE:-$HOME/.ilo/voxtype-dictate-session.txt}"
mkdir -p "$(dirname "$SID_FILE")" 2>/dev/null || true
SID=""
[ -f "$SID_FILE" ] && SID="$(cat "$SID_FILE" 2>/dev/null)"

export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_BIN="${HERMES_BIN:-$(command -v hermes || echo "$HOME/.local/bin/hermes")}"

CMD=("$HERMES_BIN" chat -Q -q "$TEXT" --source voxtype-dictate --yolo --reasoning none)
[ -n "$SID" ] && CMD+=(--resume "$SID")

RAW="$(cd "$HOME" && "${CMD[@]}" 2>&1)"

NEW_SID="$(printf '%s\n' "$RAW" | grep -oE 'session[_ ]?id[^A-Za-z0-9]{0,3}[A-Za-z0-9_]{6,}' | head -1 | grep -oE '[A-Za-z0-9_]{6,}$')"
[ -n "$NEW_SID" ] && echo "$NEW_SID" > "$SID_FILE"

CLEAN="$(printf '%s\n' "$RAW" | sed '/^↻ Resumed session/d; /^session_id/d')"
printf '%s' "$CLEAN" | tail -c 4000
