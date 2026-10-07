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
  # Voxtype 1.1.0 warns on every invocation if [parakeet] exists without
  # model. That partial table is already the default; drop it.
  "$HERE/bin/repair-voxtype-parakeet.sh" || true
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

# Voxtype's own OSD is one layer on one screen. This pill is one layer
# per output, so a second monitor still shows that listening started.
if command -v qs >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/share/speak-to-hermes" "$HOME/.config/systemd/user"
  rm -rf "$HOME/.local/share/speak-to-hermes/every-screen"
  cp -r "$HERE/osd/every-screen" "$HOME/.local/share/speak-to-hermes/every-screen"
  cp "$HERE/systemd/speak-to-hermes-osd.service" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now speak-to-hermes-osd.service
  echo "Every-screen indicator enabled (speak-to-hermes-osd.service)."
else
  echo "qs not found — skipped the every-screen indicator. Install Quickshell, then re-run."
fi

if command -v python3 >/dev/null 2>&1; then
  echo
  read -rp "Listen for a wake name on this machine? Audio stays here until the name is heard. [y/N] " WAKE_ANSWER
  if [ "${WAKE_ANSWER:-n}" = "y" ] || [ "${WAKE_ANSWER:-n}" = "Y" ]; then
    python3 -m venv "$HOME/.local/share/speak-to-hermes/wake-venv"
    "$HOME/.local/share/speak-to-hermes/wake-venv/bin/pip" install sherpa-onnx numpy sentencepiece pypinyin
    install -m 755 "$HERE/bin/wake-listen.py" "$HOME/.local/bin/wake-listen.py"
    mkdir -p "$HOME/.config/speak-to-hermes" "$HOME/.config/systemd/user"
    if [ ! -f "$HOME/.config/speak-to-hermes/wake-phrase" ]; then
      cp "$HERE/config/wake-phrase.example" "$HOME/.config/speak-to-hermes/wake-phrase"
      echo "Wrote ~/.config/speak-to-hermes/wake-phrase — edit the name before relying on it."
    fi
    cp "$HERE/systemd/speak-to-hermes-wake.service" "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    systemctl --user enable --now speak-to-hermes-wake.service
    echo "Name wake enabled. Super+Shift+k toggles it. Stop with: systemctl --user stop speak-to-hermes-wake"
  fi
fi

if [ -d "$HOME/.config/omarchy/plugins" ] || command -v omarchy-shell >/dev/null 2>&1; then
  echo
  read -rp "Install the Hermes Voice top-bar widget (pick the reply voice, click to cycle)? [Y/n] " BAR_ANSWER
  if [ "${BAR_ANSWER:-Y}" != "n" ] && [ "${BAR_ANSWER:-Y}" != "N" ]; then
    mkdir -p "$HOME/.config/omarchy/plugins/speak-to-hermes.voice"
    cp "$HERE/omarchy-bar-widget/manifest.json" "$HERE/omarchy-bar-widget/Widget.qml" \
      "$HOME/.config/omarchy/plugins/speak-to-hermes.voice/"
    if command -v omarchy-shell >/dev/null 2>&1; then
      omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
      omarchy-shell shell enablePlugin speak-to-hermes.voice true >/dev/null 2>&1 || true
      echo "Installed and enabled -- look for it in the top bar. If it's not"
      echo "there yet: omarchy-shell shell reloadConfig"
    else
      echo "Copied the plugin. Run 'omarchy-shell shell rescanPlugins' then"
      echo "'omarchy-shell shell enablePlugin speak-to-hermes.voice true' to turn it on."
    fi
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
