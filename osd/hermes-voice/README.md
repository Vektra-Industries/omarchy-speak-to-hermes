# hermes-voice — Voxtype OSD style

A Quickshell OSD style package for [Voxtype](https://voxtype.io), derived
from Voxtype's own bundled `aegis-hud` showcase (`/usr/share/voxtype/osd/aegis-hud`,
credit to the Voxtype project — this package keeps its license and just adds
one feature on top).

**What it adds:** `speak-to-hermes.sh` writes a sibling `mode` file
(`hermes` / `dictate`) next to Voxtype's own daemon state file. This HUD
watches that file with the same `Quickshell.Io.FileView` pattern Voxtype's
own `StateReader.qml` uses, and swaps its telemetry label from `A E G I S`
to `H E R M E S` (plus an accent-color shift) whenever you're in the
speak-to-hermes flow — so a glance at the HUD tells you which mode is
live. Native Voxtype dictation never touches the mode file, so it always
renders exactly like stock `aegis-hud`.

## Install

```bash
mkdir -p ~/.local/share/voxtype/osd
cp -r osd/hermes-voice ~/.local/share/voxtype/osd/
voxtype config set osd.frontend quickshell
voxtype config set osd.style hermes-voice
voxtype config set osd.enabled true
systemctl --user restart voxtype
```

(`install.sh` does this for you if you answer yes to the OSD prompt.)

It will also now show up as a selectable style inside Voxtype's own
`voxtype configure` TUI and `voxtype info styles` — this is a real,
discoverable user style package, not a hack bolted on the side.

## Verifying it loaded

```bash
journalctl --user -u voxtype -n 20 | grep -i -E "error|qml"
```

Should be clean. If you see QML errors, `voxtype config set osd.style aegis-hud`
to fall back to the stock style while you investigate.
