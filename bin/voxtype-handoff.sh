#!/usr/bin/env bash
# Voxtype post-process hook.
#
# The daemon already has the model loaded. It writes the transcript to
# this command's stdin and types whatever we print. Normal dictation
# (mode file absent or "dictate") is passed through unchanged.
# Speak-to-Hermes sets the mode file to "hermes" before `voxtype record`.
# In that case we hand the text to the speak script in the background
# and print nothing, so the words are not typed into the focused window.
# Exit 0 immediately: a slow agent turn must not block Voxtype.
set -u
text=$(cat)
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mode_file="$runtime/voxtype/mode"
mode=$(cat "$mode_file" 2>/dev/null || printf '%s' dictate)
if [ "$mode" != "hermes" ]; then
  printf '%s' "$text"
  exit 0
fi
printf '%s' dictate > "$mode_file" 2>/dev/null || true
speak=""
if [ -n "${SPEAK_BIN:-}" ]; then
  speak="$SPEAK_BIN"
elif [ -s "$HOME/.config/speak-to-hermes/speak-bin" ]; then
  speak=$(head -n 1 "$HOME/.config/speak-to-hermes/speak-bin")
fi
if [ -z "$speak" ]; then
  speak="$HOME/.local/bin/speak-to-hermes.sh"
fi
if [ ! -x "$speak" ]; then
  printf '%s' "$text"
  exit 0
fi
printf '%s' "$text" | "$speak" --from-text >/dev/null 2>&1 &
exit 0
