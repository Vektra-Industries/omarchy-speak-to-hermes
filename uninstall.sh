#!/usr/bin/env bash
# uninstall.sh — take this project off the laptop.
# Leaves Voxtype's own dictation (SUPER + h) and Hermes Desktop voice alone.
# Moves removed files to ~/.trash so they can be put back.
set -euo pipefail

stamp="$(date +%Y%m%d)"
trash="$HOME/.trash/speak-to-hermes-removed-${stamp}"
mkdir -p "$trash"
echo "Backup directory: $trash"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if command -v systemctl >/dev/null 2>&1; then
  for unit in speak-to-hermes-wake.service speak-to-hermes-osd.service speak-to-hermes-orb.service; do
    systemctl --user disable --now "$unit" 2>/dev/null || true
    if [ -f "$HOME/.config/systemd/user/$unit" ]; then
      mv "$HOME/.config/systemd/user/$unit" "$trash/" || true
    fi
  done
  systemctl --user daemon-reload 2>/dev/null || true
fi

move_if() {
  if [ -e "$1" ]; then
    mkdir -p "$trash/$(dirname "${1#$HOME/}")"
    mv "$1" "$trash/$(dirname "${1#$HOME/}")/" || true
    echo "moved $1"
  fi
}

move_if "$HOME/.local/bin/speak-to-hermes.sh"
move_if "$HOME/.local/bin/ilo-speak.sh"
move_if "$HOME/.local/bin/ilo-speak.sh.bak-wake"
move_if "$HOME/.local/bin/voxtype-handoff.sh"
move_if "$HOME/.local/bin/wake-listen.py"
move_if "$HOME/.local/bin/speak-to-hermes-transcript.py"
move_if "$HOME/.local/bin/speak-to-hermes-orb.py"
move_if "$HOME/.config/speak-to-hermes"
move_if "$HOME/.local/share/speak-to-hermes"
move_if "$HOME/.local/share/voxtype/osd/hermes-voice"

python3 - <<'PY'
from pathlib import Path
import os
home = Path.home()
cfg = home / ".config/voxtype/config.toml"
if cfg.exists():
    text = cfg.read_text()
    lines = text.splitlines(keepends=True)
    out = []
    skip = False
    for line in lines:
        stripped = line.strip()
        if stripped == "[output.post_process]":
            skip = True
            continue
        if skip:
            if stripped.startswith("[") and stripped.endswith("]"):
                skip = False
            else:
                continue
        if stripped.startswith("eager_processing"):
            out.append("eager_processing = false\n")
            continue
        if "voxtype-handoff.sh" in line:
            continue
        out.append(line)
    cfg.write_text("".join(out))
    print("cleared voxtype speak hook")
binds = home / ".config/hypr/bindings.lua"
if binds.exists():
    kept = []
    for line in binds.read_text().splitlines(keepends=True):
        if "ilo-speak.sh" in line or "speak-to-hermes" in line or "Speak to ILO" in line:
            continue
        if "use the dictation system they have already" in line:
            continue
        if "instead of typing into the focused window" in line:
            continue
        if "Toggle: press to start, press again to" in line:
            continue
        kept.append(line)
    binds.write_text("".join(kept))
    print("cleared hypr speak binds")
mode = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "voxtype" / "mode"
if mode.parent.exists():
    mode.write_text("dictate")
PY

if command -v voxtype >/dev/null 2>&1; then
  current_style="$(voxtype config get osd.style 2>/dev/null || true)"
  if [ "$current_style" = "hermes-voice" ]; then
    voxtype config set osd.style aegis-hud || true
  fi
  systemctl --user restart voxtype 2>/dev/null || true
fi

if [ -x /usr/bin/omarchy-restart-hyprctl ]; then
  /usr/bin/omarchy-restart-hyprctl >/dev/null 2>&1 || true
elif command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

echo "Uninstalled. Voxtype dictation and Hermes Desktop voice were not removed."
echo "Put files back from $trash if you want the hotkey again."
