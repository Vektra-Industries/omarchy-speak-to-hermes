#!/usr/bin/env python3
"""speak-to-hermes-transcript.py — a floating transcript viewer, GrokBot
style: every "speak to hermes" exchange, who said what, which model
answered, how long it took. Reads the JSONL log speak-to-hermes.sh
already writes; toggled by a hotkey (see hypr/bindings.lua.snippet).

Run with no args: opens (or raises, if already open) the window.
Run with --toggle: opens if closed, closes if open (for a hotkey that
should act like a panel toggle rather than always re-raising).
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib, Gdk  # noqa: E402

TRANSCRIPT_FILE = Path(
    os.environ.get("SPEAK_TO_HERMES_TRANSCRIPT_FILE", Path.home() / ".local/share/speak-to-hermes/transcript.jsonl")
)
LOCK_FILE = Path(os.environ.get("SPEAK_TO_HERMES_WINDOW_LOCK", "/tmp/speak-to-hermes-transcript.lock"))

CSS = b"""
window { background-color: rgba(18, 18, 22, 0.96); }
.bubble-user {
  background-color: #2a3a52; color: #e8eef7; border-radius: 12px;
  padding: 8px 12px; margin: 4px 60px 4px 8px;
}
.bubble-reply {
  background-color: #1e2a22; color: #e6f3ea; border-radius: 12px;
  padding: 8px 12px; margin: 4px 8px 4px 60px;
}
.meta { color: #8a8f98; font-size: 11px; }
.empty-state { color: #6b7280; font-size: 14px; }
"""


def _load_entries() -> list[dict]:
    if not TRANSCRIPT_FILE.exists():
        return []
    out = []
    for line in TRANSCRIPT_FILE.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def _fmt_time(ts: float) -> str:
    try:
        return datetime.fromtimestamp(ts).strftime("%H:%M:%S")
    except Exception:
        return ""


class TranscriptWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application) -> None:
        super().__init__(application=app, title="Speak to Hermes — Transcript")
        self.set_default_size(460, 620)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(box)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header.set_margin_top(10)
        header.set_margin_bottom(6)
        header.set_margin_start(12)
        header.set_margin_end(12)
        title = Gtk.Label(label="<b>Speak to Hermes</b>", use_markup=True, xalign=0)
        header.append(title)
        refresh_btn = Gtk.Button(label="Refresh")
        refresh_btn.connect("clicked", lambda *_: self.reload())
        header.append(refresh_btn)
        box.append(header)
        box.append(Gtk.Separator())

        self.scroller = Gtk.ScrolledWindow()
        self.scroller.set_vexpand(True)
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.list_box.set_margin_top(8)
        self.list_box.set_margin_bottom(8)
        self.scroller.set_child(self.list_box)
        box.append(self.scroller)

        self._last_mtime = 0.0
        self.reload()
        GLib.timeout_add(1000, self._poll)

    def _poll(self) -> bool:
        try:
            mtime = TRANSCRIPT_FILE.stat().st_mtime
        except FileNotFoundError:
            return True
        if mtime != self._last_mtime:
            self._last_mtime = mtime
            self.reload()
        return True

    def reload(self) -> None:
        child = self.list_box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.list_box.remove(child)
            child = nxt

        entries = _load_entries()
        if not entries:
            empty = Gtk.Label(label="No conversations yet. Press your hotkey and speak.")
            empty.add_css_class("empty-state")
            empty.set_margin_top(40)
            self.list_box.append(empty)
            return

        for e in entries[-200:]:
            ts = _fmt_time(e.get("ts", 0))
            model = e.get("model", "")
            dur = e.get("duration_ms")
            dur_s = f" · {dur / 1000:.1f}s" if isinstance(dur, (int, float)) else ""
            meta_bits = [b for b in [ts, model] if b]
            meta_line = " · ".join(meta_bits) + dur_s

            you = Gtk.Label(label=GLib.markup_escape_text(e.get("text", "")), xalign=0, wrap=True)
            you.add_css_class("bubble-user")
            self.list_box.append(you)

            reply = Gtk.Label(label=GLib.markup_escape_text(e.get("reply", "")), xalign=0, wrap=True)
            reply.add_css_class("bubble-reply")
            self.list_box.append(reply)

            meta = Gtk.Label(label=meta_line, xalign=1)
            meta.add_css_class("meta")
            meta.set_margin_end(8)
            meta.set_margin_bottom(6)
            self.list_box.append(meta)

        GLib.idle_add(self._scroll_to_bottom)

    def _scroll_to_bottom(self) -> bool:
        adj = self.scroller.get_vadjustment()
        adj.set_value(adj.get_upper())
        return False


def main() -> None:
    app = Gtk.Application(application_id="com.hermes.speak-to-hermes.transcript")

    def on_activate(a: Gtk.Application) -> None:
        display = Gdk.Display.get_default()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        win = TranscriptWindow(a)
        win.present()

    app.connect("activate", on_activate)
    app.run(None)


if __name__ == "__main__":
    main()
