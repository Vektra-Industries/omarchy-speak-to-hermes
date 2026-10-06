#!/usr/bin/env bash
# install.sh — run this on the Omarchy laptop (the Voxtype side).
# Installs speak-to-hermes.sh and a blank config for you to fill in.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.config/speak-to-hermes"
install -m 755 "$HERE/bin/speak-to-hermes.sh" "$HOME/.local/bin/speak-to-hermes.sh"

if [ ! -f "$HOME/.config/speak-to-hermes/config.sh" ]; then
  cp "$HERE/config.example.sh" "$HOME/.config/speak-to-hermes/config.sh"
  echo "Wrote $HOME/.config/speak-to-hermes/config.sh — edit it before using the hotkey."
fi

if ! command -v voxtype >/dev/null 2>&1; then
  echo "Voxtype not found. Install it from Omarchy's Install > AI > Dictation menu first."
fi

if command -v voxtype >/dev/null 2>&1; then
  echo
  read -rp "Install the hermes-voice OSD style (cinematic HUD, Hermes-mode badge)? [Y/n] " OSD_ANSWER
  if [ "${OSD_ANSWER:-Y}" != "n" ] && [ "${OSD_ANSWER:-Y}" != "N" ]; then
    mkdir -p "$HOME/.local/share/voxtype/osd"
    cp -r "$HERE/osd/hermes-voice" "$HOME/.local/share/voxtype/osd/"
    voxtype config set osd.frontend quickshell
    voxtype config set osd.style hermes-voice
    voxtype config set osd.enabled true
    echo "Installed. Run 'systemctl --user restart voxtype' to apply (also needed after any future config change)."
    echo "See osd/hermes-voice/README.md for how it works and how to fall back to the stock style."
  fi
fi

echo
echo "Next steps:"
echo "  1. Run install-relay.sh on your Hermes host -- it prints a token and a URL"
echo "  2. Put that token in ~/.config/speak-to-hermes/token (mode 600) on THIS laptop"
echo "  3. Put that URL in ~/.config/speak-to-hermes/config.sh as HERMES_RELAY_URL"
echo "  4. Add the lines from hypr/bindings.lua.snippet to ~/.config/hypr/bindings.lua"
echo "     (one for the hotkey, one for the transcript-viewer toggle)"
echo "  5. hyprctl reload (or omarchy-restart-hyprctl if a plain reload doesn't pick it up)"
echo "  6. pip install --user edge-tts for a real voice, or pacman -S espeak-ng for a robotic one"
echo "  7. systemctl --user restart voxtype -- applies the OSD style change from step above"
