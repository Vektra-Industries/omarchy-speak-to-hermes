#!/usr/bin/env bash
# speak-to-hermes.sh — a second dictation mode for Omarchy's built-in
# Voxtype, sitting right next to the normal "type into the focused
# window" hotkey. Instead of pasting, it ships your words to a Hermes
# agent (https://hermes-agent.nousresearch.com) over SSH and speaks the
# reply back.
#
# Toggle: first press starts recording, second press stops, transcribes,
# sends, and speaks the reply.
#
# Config: copy config.example.sh to ~/.config/speak-to-hermes/config.sh
# and edit it, or export the same variables before this script runs.
set -uo pipefail

CONFIG="$HOME/.config/speak-to-hermes/config.sh"
[ -f "$CONFIG" ] && source "$CONFIG"

HERMES_SSH_HOST="${HERMES_SSH_HOST:?set HERMES_SSH_HOST, e.g. user@100.x.x.x (Tailscale) or user@your.host}"
HERMES_SSH_KEY="${HERMES_SSH_KEY:-$HOME/.ssh/speak_to_hermes}"
HERMES_RELAY_PATH="${HERMES_RELAY_PATH:-/usr/local/bin/hermes-speak-relay.sh}"
HERMES_VOICE="${HERMES_VOICE:-en-US-AvaNeural}"

PIDFILE="/tmp/speak-to-hermes-record.pid"
WAVFILE="/tmp/speak-to-hermes-capture.wav"

notify() { notify-send -a "Hermes" "$1" "$2" 2>/dev/null || true; }

if [ ! -f "$PIDFILE" ]; then
  # --- start recording ---
  rm -f "$WAVFILE"
  pw-record --format=s16 --rate=16000 --channels=1 "$WAVFILE" &
  echo $! > "$PIDFILE"
  notify "Listening…" "Press the key again when you're done."
  exit 0
fi

# --- stop recording + transcribe + send ---
REC_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
rm -f "$PIDFILE"
if [ -n "$REC_PID" ]; then
  kill "$REC_PID" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$REC_PID" 2>/dev/null || break
    sleep 0.1
  done
fi
sleep 0.2

if [ ! -s "$WAVFILE" ]; then
  notify "Didn't catch that" "No audio recorded."
  exit 0
fi

TEXT="$(voxtype transcribe "$WAVFILE" 2>/tmp/speak-to-hermes-transcribe.err | sed 's/[[:space:]]*$//')"
rm -f "$WAVFILE"
if [ -z "$TEXT" ]; then
  notify "Didn't catch that" "Transcription came back empty."
  exit 0
fi
notify "You said" "$TEXT"

REPLY="$(printf '%s' "$TEXT" | ssh -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes \
  -i "$HERMES_SSH_KEY" "$HERMES_SSH_HOST" "$HERMES_RELAY_PATH" 2>/tmp/speak-to-hermes-ssh.err)"

if [ -z "$REPLY" ]; then
  notify "Hermes" "Couldn't reach Hermes. See /tmp/speak-to-hermes-ssh.err"
  exit 0
fi
notify "Hermes" "$REPLY"

PATH="$HOME/.local/bin:$PATH"
if command -v edge-tts >/dev/null 2>&1; then
  edge-tts --voice "$HERMES_VOICE" --text "$REPLY" --write-media /tmp/speak-to-hermes-reply.mp3 >/dev/null 2>&1 \
    && ffplay -nodisp -autoexit -loglevel quiet /tmp/speak-to-hermes-reply.mp3 >/dev/null 2>&1 &
elif command -v espeak-ng >/dev/null 2>&1; then
  espeak-ng -s 170 "$REPLY" >/dev/null 2>&1 &
fi
exit 0
