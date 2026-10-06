#!/usr/bin/env python3
"""hermes-speak-relay.py — runs on the machine that hosts your Hermes
agent. Exposes exactly one thing: POST /speak {"text": "..."} -> one
`hermes chat -Q` turn -> {"reply": "..."}.

Why HTTP instead of SSH: if your Hermes host has Tailscale SSH enabled,
Tailscale authenticates the *tailnet peer*, not the *SSH key* (you'll
see "Authenticated ... using none" in a verbose ssh -v log) -- so any
`command=` restriction in authorized_keys is silently a no-op. This
sidesteps that: it's plain HTTP, so Tailscale's SSH identity bypass
never comes into it. Restriction comes from two independent things
instead: (1) bind to your tailscale interface only, so nothing off
your tailnet can even open the port, and (2) a bearer token that only
this process and the laptop's script hold. Neither alone is "any
device on my tailnet gets in" -- both are required.

No root needed. Runs as a normal user (systemd --user unit, see
install-relay.sh).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path.home()
TOKEN_FILE = Path(os.environ.get("HERMES_SPEAK_TOKEN_FILE", HOME / ".config/hermes-speak/token"))
BIND_HOST = os.environ.get("HERMES_SPEAK_BIND_HOST", "")  # REQUIRED: your tailscale/private IP
BIND_PORT = int(os.environ.get("HERMES_SPEAK_BIND_PORT", "47113"))
SID_FILE = Path(os.environ.get("HERMES_SPEAK_SESSION_FILE", HOME / ".config/hermes-speak/session.txt"))
HERMES_BIN = os.environ.get("HERMES_BIN", "hermes")

MAX_BODY = 8192  # a dictated sentence, not a novel


def _load_token() -> str:
    return TOKEN_FILE.read_text().strip()


def _run_hermes(text: str) -> str:
    sid = SID_FILE.read_text().strip() if SID_FILE.exists() else ""
    env = os.environ.copy()
    env["HERMES_HOME"] = env.get("HERMES_HOME", str(HOME / ".hermes"))
    cmd = [HERMES_BIN, "chat", "-Q", "-q", text, "--source", "voxtype-dictate", "--yolo", "--reasoning", "none"]
    if sid:
        cmd += ["--resume", sid]
    raw = subprocess.run(cmd, cwd=str(HOME), env=env, capture_output=True, text=True, timeout=90)
    out = (raw.stdout or "") + ("\n" + raw.stderr if raw.stderr else "")
    m = re.search(r"session[_ ]?id[^A-Za-z0-9]{0,3}([A-Za-z0-9_]{6,})", out)
    if m:
        SID_FILE.parent.mkdir(parents=True, exist_ok=True)
        SID_FILE.write_text(m.group(1))
    clean = "\n".join(
        ln for ln in out.splitlines() if not ln.startswith("↻ Resumed session") and not ln.startswith("session_id")
    )
    return clean.strip()[-4000:] or "I heard you, but came back empty."


class Handler(BaseHTTPRequestHandler):
    server_version = "hermes-speak-relay/1"

    def log_message(self, fmt, *args):  # quiet; systemd journal already timestamps
        pass

    def _reject(self, code: int, msg: str) -> None:
        body = json.dumps({"error": msg}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        if self.path != "/speak":
            self._reject(404, "not found")
            return
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer ") or auth[7:] != _load_token():
            self._reject(401, "unauthorized")
            return
        length = int(self.headers.get("Content-Length", 0))
        if length <= 0 or length > MAX_BODY:
            self._reject(400, "bad length")
            return
        try:
            data = json.loads(self.rfile.read(length))
            text = str(data.get("text", "")).strip()
        except Exception:
            self._reject(400, "bad json")
            return
        if not text:
            self._reject(400, "empty text")
            return
        try:
            reply = _run_hermes(text)
        except subprocess.TimeoutExpired:
            reply = "Still working on that. Try again in a moment."
        except Exception as exc:  # never leak a traceback to the network
            self._reject(500, f"relay error: {type(exc).__name__}")
            return
        body = json.dumps({"reply": reply}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        self._reject(405, "POST /speak only")


def main() -> None:
    if not BIND_HOST:
        raise SystemExit(
            "set HERMES_SPEAK_BIND_HOST to your tailscale/private interface IP "
            "(NOT 0.0.0.0 -- that defeats the whole point)"
        )
    if not TOKEN_FILE.exists():
        raise SystemExit(f"missing token file: {TOKEN_FILE} (install-relay.sh creates one)")
    srv = ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler)
    print(f"hermes-speak-relay listening on {BIND_HOST}:{BIND_PORT}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
