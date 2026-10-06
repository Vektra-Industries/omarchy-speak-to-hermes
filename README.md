# omarchy-speak-to-hermes

A second dictation mode for [Omarchy](https://omarchy.org)'s built-in
[Voxtype](https://voxtype.io) dictation. Voxtype's normal hotkey transcribes
your speech and types it into whatever window is focused. This project adds
a second hotkey, right next to it, that instead sends the words to a
[Hermes](https://hermes-agent.nousresearch.com) agent and speaks the reply
back out loud — no app to switch to, no browser tab to open.

Built on a real laptop + home server pair: an Omarchy ThinkPad with no GPU,
and a separate Linux box running the actual Hermes agent, talked to over
Tailscale.

## How it works

```
 you press SUPER+SHIFT+h
        │
        ▼
 pw-record (16kHz mono WAV)
        │  press again to stop
        ▼
 voxtype transcribe   ← Voxtype's own local Whisper, reused — no second STT
        │
        ▼
 HTTPS/HTTP POST /speak  →  hermes-speak-relay.py  (runs on the Hermes host,
        │   bearer token          bound to your tailscale/private IP only)
        │                          │
        │                          ▼
        │                    hermes chat -Q  (one real agent turn,
        │                     resumed each time so it's one thread)
        ▼
 desktop notification + edge-tts (or espeak-ng) speaks the reply
```

Nothing here is a new STT or TTS stack bolted on top — it reuses whatever
Voxtype already transcribes with, and whatever Hermes already answers with.
The only new code is the handoff in between.

## Install

**On the Hermes host** (run this first — it prints a token and a URL you'll
need on the laptop):

```bash
git clone <this repo>
cd omarchy-speak-to-hermes
./install-relay.sh
```

No root needed — it's a `systemd --user` unit. It'll ask for the interface
IP to bind to (your tailscale0 IP, or another private interface — **never
0.0.0.0**, see "Security model").

**On the Omarchy laptop** (the Voxtype side):

```bash
git clone <this repo>
cd omarchy-speak-to-hermes
./install.sh
```

Then:
1. Put the relay's URL in `~/.config/speak-to-hermes/config.sh` as
   `HERMES_RELAY_URL`
2. Put the token `install-relay.sh` printed into
   `~/.config/speak-to-hermes/token` (mode 600)
3. Add the two lines from `hypr/bindings.lua.snippet` to
   `~/.config/hypr/bindings.lua`
4. `hyprctl reload` — if that doesn't pick up new binds, Omarchy's Lua
   config sometimes needs `omarchy-restart-hyprctl` instead (a full
   Hyprland config re-source, not just a keyword reload)
5. `pip install --user edge-tts` for a real voice, or `pacman -S espeak-ng`
   for a robotic fallback. Without either, you still get the text in a
   desktop notification.

## Security model — read this before you trust it

This started life as an SSH-based relay with a `command="..."` restriction
in `authorized_keys`. **That approach silently did nothing** on a tailnet
with Tailscale SSH enabled: Tailscale authenticates the *tailnet peer*, not
the *SSH key* — a verbose `ssh -v` log shows `Authenticated ... using
"none"`, meaning OpenSSH's own key-checking step never ran, so whatever
Tailscale's ACL grants that peer (commonly a normal login) is what you get
regardless of which key was presented. If you're building something SSH-based
on a tailnet, check for that line before trusting any `authorized_keys`
restriction.

This project now uses plain HTTP instead, specifically to sidestep that:

- **Interface-bound.** The relay binds to one specific IP you choose (your
  tailscale0 address, or another private interface) — `install-relay.sh`
  refuses `0.0.0.0`. Nothing outside that network can even open the port.
- **Bearer token.** A 32-byte random token, generated once, required on
  every request. It lives in two places only: the relay's
  `~/.config/hermes-speak/token` and the laptop's
  `~/.config/speak-to-hermes/token`, both mode 600.
- **One verb.** The relay answers exactly one route (`POST /speak`) with
  exactly one effect (one `hermes chat -Q` turn). There's no shell to
  escape to, because there isn't a shell in the first place.

Two independent factors — network reachability and token possession — not
one assumed one. If you're on a LAN instead of Tailscale, run it over
`https` (put a reverse proxy with TLS in front) rather than bare `http`
across anything wider than a trusted segment.

## Files

- `bin/speak-to-hermes.sh` — runs on the laptop, bound to a hotkey
- `bin/hermes-speak-relay.py` — runs on the Hermes host; the only thing the
  laptop can reach, and the only thing it can do
- `config.example.sh` — copy to `~/.config/speak-to-hermes/config.sh`
- `hypr/bindings.lua.snippet` — the two Hyprland bind lines
- `install.sh`, `install-relay.sh` — one-shot installers for each side

## License

MIT — see [LICENSE](LICENSE).
