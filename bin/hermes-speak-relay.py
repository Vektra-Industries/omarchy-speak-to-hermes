#!/usr/bin/env python3
"""hermes-speak-relay.py — runs on the machine that hosts your Hermes
agent. Exposes exactly one thing: POST /speak {"text": "..."} -> one
`hermes chat -Q` turn -> {"reply": "..."}.

Why HTTP instead of SSH: if your Hermes host has Tailscale SSH enabled,
Tailscale authenticates the *tailnet peer*, not the *SSH key* (you'll
see "Authenticated ... using none" in a verbose ssh -v log) -- so any
`command=` restriction in authorized_keys is silently a no-op. This
sidesteps that: it's plain HTTP, so Tailscale's SSH identity bypass
never comes into it.

A request must clear THREE independent checks, none of which an
attacker controls alone:
  1. Network   — bind to your tailscale/private interface only (never
                 0.0.0.0); nothing outside that network can open the port.
  2. Device    — `tailscale whois <source-ip>` asks the LOCAL tailscaled
                 daemon (not the connecting client) which tailnet machine
                 owns that IP. This is the same primitive Tailscale's own
                 Go tsnet/LocalClient.WhoIs() docs recommend for
                 "identifying callers" -- here invoked via the `tailscale`
                 CLI so this stays plain Python with no Go toolchain.
                 Set HERMES_SPEAK_ALLOWED_DEVICES to your laptop's tailnet
                 machine name(s), comma-separated; leave unset to disable
                 (token-only, matches v1 of this project).
  3. Token     — a bearer token only this process and the laptop hold.

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
TAILSCALE_BIN = os.environ.get("TAILSCALE_BIN", "tailscale")
# Machine names as `tailscale whois` reports them (e.g. "laptop.tailnet-name.ts.net").
# Empty/unset = device check disabled (token-only).
ALLOWED_DEVICES = {
    d.strip() for d in os.environ.get("HERMES_SPEAK_ALLOWED_DEVICES", "").split(",") if d.strip()
}

MAX_BODY = 8192  # a dictated sentence, not a novel


def _load_token() -> str:
    return TOKEN_FILE.read_text().strip()


_WHOIS_CACHE: dict[str, tuple[float, str | None]] = {}


def _tailscale_peer_name(remote_ip: str) -> str | None:
    """Ask the LOCAL tailscaled daemon (not the client) who owns remote_ip."""
    import time
    now = time.monotonic()
    cached = _WHOIS_CACHE.get(remote_ip)
    if cached and now - cached[0] < 60:
        return cached[1]
    name = None
    try:
        raw = subprocess.run(
            [TAILSCALE_BIN, "whois", "--json", remote_ip],
            capture_output=True, text=True, timeout=2,
        )
        if raw.returncode == 0:
            data = json.loads(raw.stdout)
            got = (data.get("Node") or {}).get("Name")
            name = got.rstrip(".") if got else None
    except Exception:
        name = None
    _WHOIS_CACHE[remote_ip] = (now, name)
    return name


def _run_hermes(text: str, model: str | None = None) -> dict:
    """One short spoken turn. No tool loop: a voice reply should not
    load the full agent tool catalog or wander into a second call.
    """
    sid = SID_FILE.read_text().strip() if SID_FILE.exists() else ""
    env = os.environ.copy()
    env["HERMES_HOME"] = env.get("HERMES_HOME", str(HOME / ".hermes"))
    spoken = (
        "Voice turn. Reply in one or two short spoken sentences. "
        "No tools, no lists, no file paths.\n\n"
        + text
    )
    cmd = [
        HERMES_BIN, "chat", "-Q", "-q", spoken, "--format", "stream-json",
        "--source", "voxtype-dictate", "--yolo", "--reasoning", "none",
        "--max-turns", "1", "--ignore-rules", "-t", "clarify",
    ]
    if model:
        cmd += ["-m", model]
    if sid:
        cmd += ["--resume", sid]
    raw = subprocess.run(cmd, cwd=str(HOME), env=env, capture_output=True, text=True, timeout=45)

    result: dict = {"reply": "", "model": None, "session_id": sid or None, "duration_ms": None}
    for line in raw.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") == "system" and ev.get("subtype") == "init":
            result["model"] = ev.get("model")
            result["session_id"] = ev.get("session_id") or result["session_id"]
        elif ev.get("type") == "result":
            result["reply"] = ev.get("text", "")
            result["session_id"] = ev.get("session_id") or result["session_id"]
            result["duration_ms"] = ev.get("duration_ms")

    if result["session_id"]:
        SID_FILE.parent.mkdir(parents=True, exist_ok=True)
        SID_FILE.write_text(result["session_id"])

    if not result["reply"]:
        result["reply"] = "I heard you, but came back empty."
    result["reply"] = result["reply"][-4000:]
    return result


class Handler(BaseHTTPRequestHandler):
    server_version = "hermes-speak-relay/2"

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

        if ALLOWED_DEVICES:
            peer = _tailscale_peer_name(self.client_address[0])
            if peer not in ALLOWED_DEVICES:
                self._reject(403, "device not recognized by tailscale whois")
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
            model = data.get("model")
            model = str(model).strip() if model else None
        except Exception:
            self._reject(400, "bad json")
            return
        if not text:
            self._reject(400, "empty text")
            return
        try:
            result = _run_hermes(text, model=model)
        except subprocess.TimeoutExpired:
            result = {"reply": "Still working on that. Try again in a moment.", "model": None, "session_id": None, "duration_ms": None}
        except Exception as exc:  # never leak a traceback to the network
            self._reject(500, f"relay error: {type(exc).__name__}")
            return
        body = json.dumps(result).encode()
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
    mode = f"device-checked ({', '.join(sorted(ALLOWED_DEVICES))}) + token" if ALLOWED_DEVICES else "token-only"
    print(f"hermes-speak-relay listening on {BIND_HOST}:{BIND_PORT} [{mode}]")
    srv.serve_forever()


if __name__ == "__main__":
    main()
