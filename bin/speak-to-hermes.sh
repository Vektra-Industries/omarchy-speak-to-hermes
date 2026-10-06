#!/usr/bin/env bash
# speak-to-hermes.sh — a second dictation mode for Omarchy's built-in
# Voxtype, sitting right next to the normal "type into the focused
# window" hotkey. Instead of pasting, it ships your words to a Hermes
# agent (https://hermes-agent.nousresearch.com) over HTTP and speaks
# the reply back.
#
# Toggle: first press starts recording, second press stops, transcribes,
# sends, and speaks the reply.
#
# UI/UX: if Voxtype's OSD is enabled with a Quickshell style (e.g. the
# bundled "aegis-hud" cinematic voice HUD -- see README "Visual
# feedback"), this script drives the SAME state file the real Voxtype
# daemon writes to, so you get that same glowing, voice-reactive HUD for
# this flow too, with zero extra UI code: idle/recording/transcribing/
# streaming. No Voxtype OSD configured? The script still works fine,
# just with desktop notifications only.
#
# Every exchange (your text, the reply, which model answered, how long
# it took) is appended to a JSONL transcript that
# bin/speak-to-hermes-transcript.py renders as a scrollable history --
# toggle it with a second hotkey (see hypr/bindings.lua.snippet).
#
# Config: copy config.example.sh to ~/.config/speak-to-hermes/config.sh
# and edit it, or export the same variables before this script runs.
# Optional: HERMES_SPEAK_MODEL env var pins a specific model for this
# call (passed through to the relay's `-m`).
set -uo pipefail

CONFIG="$HOME/.config/speak-to-hermes/config.sh"
[ -f "$CONFIG" ] && source "$CONFIG"

HERMES_RELAY_URL="${HERMES_RELAY_URL:?set HERMES_RELAY_URL, e.g. http://100.x.x.x:47113/speak}"
HERMES_TOKEN_FILE="${HERMES_TOKEN_FILE:-$HOME/.config/speak-to-hermes/token}"
HERMES_VOICE="${HERMES_VOICE:-en-US-AvaNeural}"

PIDFILE="/tmp/speak-to-hermes-record.pid"
WAVFILE="/tmp/speak-to-hermes-capture.wav"
# Shared with the real Voxtype daemon's own OSD state machine -- see
# StateReader.qml in the Voxtype source. Values: idle | recording |
# transcribing | streaming. Writing here makes Voxtype's own OSD (if
# enabled) render for this flow exactly like it does for native dictation.
STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voxtype/state"
TRANSCRIPT_FILE="$HOME/.local/share/speak-to-hermes/transcript.jsonl"

mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$TRANSCRIPT_FILE")"
set_state() { printf '%s' "$1" > "$STATE_FILE" 2>/dev/null || true; }
notify() { notify-send -a "Hermes" "$1" "$2" 2>/dev/null || true; }

if [ ! -f "$PIDFILE" ]; then
  # --- start recording ---
  rm -f "$WAVFILE"
  pw-record --format=s16 --rate=16000 --channels=1 "$WAVFILE" &
  echo $! > "$PIDFILE"
  set_state recording
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
  set_state idle
  notify "Didn't catch that" "No audio recorded."
  exit 0
fi

set_state transcribing

# voxtype transcribe writes "Loading audio file:"/"Audio format:"/"Processing N
# samples"/ANSI-colored INFO/WARN/ERROR log lines to STDOUT, not stderr -- a
# plain stderr redirect never filters them (confirmed: caught real log noise
# sent to the relay as if it were speech). Filter those known patterns out,
# then take the last non-blank remaining line -- that's always the real
# transcript, and comes back genuinely empty for a silent/no-speech capture.
TEXT="$(voxtype transcribe "$WAVFILE" 2>/tmp/speak-to-hermes-transcribe.err \
  | grep -avE '^Loading audio file:|^Audio format:|^Processing [0-9]|INFO|WARN|ERROR' \
  | awk 'NF{last=$0} END{print last}' | sed 's/[[:space:]]*$//')"
# voxtype transcribe writes "Loading audio file:"/"Audio format:"/"Processing N
# samples"/ANSI-colored INFO-WARN log lines to STDOUT (not stderr -- stderr
# redirection alone never filters them). The real transcript is always the
# LAST non-blank stdout line; awk takes exactly that.
rm -f "$WAVFILE"
if [ -z "$TEXT" ]; then
  set_state idle
  notify "Didn't catch that" "Transcription came back empty."
  exit 0
fi
notify "You said" "$TEXT"

TOKEN="$(cat "$HERMES_TOKEN_FILE" 2>/dev/null)"
PAYLOAD="$(python3 -c 'import json,sys,os; print(json.dumps({"text": sys.argv[1], **({"model": os.environ["HERMES_SPEAK_MODEL"]} if os.environ.get("HERMES_SPEAK_MODEL") else {})}))' "$TEXT")"
AUTH_HEADER="Authorization: Bearer ${TOKEN}"
RESP="$(curl -sf -m 60 -X POST "$HERMES_RELAY_URL" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>/tmp/speak-to-hermes-http.err)"
if [ -z "$RESP" ]; then
  # one retry -- covers a relay mid-restart or a transient network blip
  sleep 1.5
  RESP="$(curl -sf -m 60 -X POST "$HERMES_RELAY_URL" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>>/tmp/speak-to-hermes-http.err)"
fi

if [ -z "$RESP" ]; then
  set_state idle
  notify "Hermes" "Couldn't reach the relay. See /tmp/speak-to-hermes-http.err"
  exit 0
fi

REPLY="$(printf '%s' "$RESP" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("reply", "") or "")
except Exception:
    print("")
')"
[ -z "$REPLY" ] && REPLY="(no reply text)"
notify "Hermes" "$REPLY"

# log the full exchange for the transcript viewer (model/session/timing
# come straight from the relay's --format stream-json parse, not a guess)
python3 -c '
import json, sys, time
resp_raw, text, transcript_file = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    resp = json.loads(resp_raw)
except Exception:
    resp = {}
entry = {
    "ts": time.time(),
    "text": text,
    "reply": resp.get("reply", ""),
    "model": resp.get("model"),
    "session_id": resp.get("session_id"),
    "duration_ms": resp.get("duration_ms"),
}
with open(transcript_file, "a") as f:
    f.write(json.dumps(entry) + "\n")
' "$RESP" "$TEXT" "$TRANSCRIPT_FILE" 2>/dev/null

set_state streaming
PATH="$HOME/.local/bin:$PATH"
if command -v edge-tts >/dev/null 2>&1; then
  edge-tts --voice "$HERMES_VOICE" --text "$REPLY" --write-media /tmp/speak-to-hermes-reply.mp3 >/dev/null 2>&1 \
    && ffplay -nodisp -autoexit -loglevel quiet /tmp/speak-to-hermes-reply.mp3 >/dev/null 2>&1
elif command -v espeak-ng >/dev/null 2>&1; then
  espeak-ng -s 170 "$REPLY" >/dev/null 2>&1
fi
set_state idle
exit 0
