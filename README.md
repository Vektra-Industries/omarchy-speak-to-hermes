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

## Hotkeys at a glance

| Keys | What it does |
|------|--------------|
| `SUPER + h` | Omarchy's normal Voxtype dictation. Types into the focused window. |
| `SUPER + SHIFT + h` | **Speak to Hermes.** Press once to start, press again to send. The reply is spoken and shown as a notification. |
| `SUPER + SHIFT + j` | Toggle the transcript window. |

These are the defaults in `hypr/bindings.lua.snippet`; change them there. It works alongside Omarchy's dictation, not instead of it: both use the same Voxtype engine, and your normal dictation key is untouched.

**AI agents:** read [`SKILL.md`](SKILL.md) for install, verify and debug steps before changing anything.

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

## Visual feedback — a real HUD, not another notification

Voxtype ships its own Quickshell-based OSD system with a cinematic,
voice-reactive showcase style called `aegis-hud` — concentric rings, a
waveform arc, telemetry readout, glow. Rather than reinvent that, this
project drives the SAME daemon state file Voxtype's own OSD watches
(`$XDG_RUNTIME_DIR/voxtype/state`: `idle`/`recording`/`transcribing`/
`streaming`), so if you enable Voxtype's own OSD, you get that HUD for
free for this flow too — no custom GUI toolkit, no second process to
maintain.

`osd/hermes-voice/` is a small derivative of `aegis-hud` (installed as a
real, discoverable Voxtype style package — it shows up in `voxtype info
styles` and inside Voxtype's own `voxtype configure` TUI, not hidden) that
additionally watches a sibling `mode` file (`hermes`/`dictate`) this
project's script writes, and swaps the HUD's telemetry label + accent
color to a distinct "HERMES" badge while that flow is live. Native
Voxtype dictation never touches the mode file, so it's unaffected and
renders exactly like stock `aegis-hud`. See `osd/hermes-voice/README.md`.

`install.sh` offers to set this up; it's entirely optional — the hotkey
works fine with just desktop notifications if you skip it.

Voxtype's OSD is one layer, and it anchors to a single screen (usually
the first). On a laptop plus an external monitor the glow can start on
the panel you are not looking at, which feels like the hotkey did
nothing. `osd/every-screen/` watches the same state file and draws a
small pill on every output. `install.sh` enables
`speak-to-hermes-osd.service` for that. See `osd/every-screen/README.md`.

## Top-bar voice picker

Voxtype has no voice/TTS concept at all (it only does speech-to-text), so
there's nowhere inside Voxtype's own config to choose which voice
`speak-to-hermes.sh` replies with. `omarchy-bar-widget/` is a small
Omarchy Quickshell bar-widget plugin that fills that specific gap: it
shows the current voice in the top bar, left-click cycles through a
short list of edge-tts voices, right-click resets to the default. It
writes its choice to `~/.config/speak-to-hermes/voice`, which
`speak-to-hermes.sh` reads (a one-off `HERMES_VOICE` env var still wins
if set). `install.sh` offers to install and enable it.

## Transcript — see what was said, which model answered, how long it took

`bin/speak-to-hermes-transcript.py` is a small GTK4 window, toggled with
a second hotkey (`SUPER+SHIFT+j`), that renders the running JSONL log
(`~/.local/share/speak-to-hermes/transcript.jsonl`) every exchange gets
appended to: your text, the reply, which model answered, and how long it
took — pulled straight from the relay's `--format stream-json` parse of
the real `hermes chat` run, not guessed. You can also pin a specific
model per utterance with the `HERMES_SPEAK_MODEL` env var (passed through
to the relay's `-m`), so the transcript becomes a real record of which
model handled which turn if you switch around.

## Install

**On the Hermes host** (run this first — it prints a token and a URL you'll
need on the laptop):

```bash
git clone https://github.com/Vektra-Industries/omarchy-speak-to-hermes.git
cd omarchy-speak-to-hermes
./install-relay.sh
```

No root needed — it's a `systemd --user` unit. It'll ask for the interface
IP to bind to (your tailscale0 IP, or another private interface — **never
0.0.0.0**, see "Security model").

**On the Omarchy laptop** (the Voxtype side):

```bash
git clone https://github.com/Vektra-Industries/omarchy-speak-to-hermes.git
cd omarchy-speak-to-hermes
./install.sh
```

Then:
1. Put the relay's URL in `~/.config/speak-to-hermes/config.sh` as
   `HERMES_RELAY_URL`
2. Put the token `install-relay.sh` printed into
   `~/.config/speak-to-hermes/token` (mode 600)
3. Add the lines from `hypr/bindings.lua.snippet` to
   `~/.config/hypr/bindings.lua` (one for the hotkey, one toggles the
   transcript viewer)
4. `hyprctl reload` — if that doesn't pick up new binds, Omarchy's Lua
   config sometimes needs `omarchy-restart-hyprctl` instead (a full
   Hyprland config re-source, not just a keyword reload)
5. `pip install --user edge-tts` for a real voice, or `pacman -S espeak-ng`
   for a robotic fallback. Without either, you still get the text in a
   desktop notification.
6. Install the `osd/hermes-voice` style (`install.sh` offers this) if you
   want the cinematic HUD from "Visual feedback" above, then
   `systemctl --user restart voxtype` to apply it.

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
- **Device identity, verified by Tailscale itself.** `install-relay.sh`
  optionally asks for your laptop's tailnet machine name and sets
  `HERMES_SPEAK_ALLOWED_DEVICES`. On every request the relay runs
  `tailscale whois <source-ip>` — this asks the **local tailscaled daemon**
  (not the connecting client) which tailnet machine actually owns that IP.
  It's the same primitive Tailscale's own Go `tsnet`/`LocalClient.WhoIs()`
  docs recommend for "identifying callers" — invoked here via the
  `tailscale` CLI so the relay stays plain Python. A client can't spoof
  this; it isn't reading anything the client sent, it's asking Tailscale's
  own control-plane-synced peer table.
- **Bearer token.** A 32-byte random token, generated once, required on
  every request. It lives in two places only: the relay's
  `~/.config/hermes-speak/token` and the laptop's
  `~/.config/speak-to-hermes/token`, both mode 600.
- **One verb.** The relay answers exactly one route (`POST /speak`) with
  exactly one effect (one `hermes chat -Q` turn). There's no shell to
  escape to, because there isn't a shell in the first place.

Three independent factors — network reachability, Tailscale-verified device
identity, and token possession — not one assumed one. Skip the device-name
prompt in `install-relay.sh` to fall back to the first and third only
(matches this project's original v1). If you're on a LAN instead of
Tailscale, run it over `https` (put a reverse proxy with TLS in front)
rather than bare `http` across anything wider than a trusted segment —
and the `tailscale whois` layer doesn't apply off a tailnet.

## Voxtype warns about `[parakeet]`

```
WARN Config section 'parakeet' could not be read and is using defaults.
WARN 1 config section(s) were skipped: parakeet
```

Voxtype 1.1.0 cannot read a `[parakeet]` table that has no `model` key
(a lone `streaming = false` is the usual shape). It skips the section and
warns on every command, including `voxtype transcribe`. That value is
already the default. `install.sh` runs `bin/repair-voxtype-parakeet.sh`,
which deletes only that unreadable table. A table that already sets
`model` is left alone. Run the script yourself if you already have the warning.

## Files

- `bin/speak-to-hermes.sh` — runs on the laptop, bound to a hotkey
- `bin/hermes-speak-relay.py` — runs on the Hermes host; the only thing the
  laptop can reach, and the only thing it can do
- `bin/speak-to-hermes-transcript.py` — GrokBot-style transcript viewer
- `osd/hermes-voice/` — optional Voxtype OSD style: the stock cinematic
  `aegis-hud` HUD plus a "HERMES" mode badge
- `osd/every-screen/` — listening pill on every monitor (Voxtype's own OSD is one screen)
- `systemd/speak-to-hermes-osd.service` — user unit for that pill
- `config.example.sh` — copy to `~/.config/speak-to-hermes/config.sh`
- `hypr/bindings.lua.snippet` — the Hyprland bind lines (hotkey + transcript)
- `bin/repair-voxtype-parakeet.sh` — drops an unreadable `[parakeet]` table (see above)
- `install.sh`, `install-relay.sh` — one-shot installers for each side

## License

MIT — see [LICENSE](LICENSE). Built by [Pablo](https://github.com/PabloTheThinker).
