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

echo
echo "Next steps:"
echo "  1. Edit ~/.config/speak-to-hermes/config.sh"
echo "  2. ssh-keygen -t ed25519 -N '' -f ~/.ssh/speak_to_hermes"
echo "  3. Put hermes-speak-relay.sh on your Hermes host (see relay/install-relay.sh)"
echo "  4. Add the two lines from hypr/bindings.lua.snippet to ~/.config/hypr/bindings.lua"
echo "  5. hyprctl reload (or omarchy-restart-hyprctl if a plain reload doesn't pick it up)"
