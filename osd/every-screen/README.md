# Every-screen indicator

Voxtype's own OSD is a single layer. It anchors to one screen, usually
the first, so on a two-monitor desk the glow can start on the laptop
panel while you are looking at the other display. It then looks like
the hotkey did nothing.

This shell watches the same `$XDG_RUNTIME_DIR/voxtype/state` file and
draws a small pill on every output while the state is `recording`,
`transcribing`, or `streaming`. If the sibling `mode` file says
`hermes`, the pill reads HERMES. Native dictation leaves mode alone, so
the pill reads LISTENING.

`install.sh` copies this directory to
`~/.local/share/speak-to-hermes/every-screen` and enables
`speak-to-hermes-osd.service`.
