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
 ssh → hermes-speak-relay.sh  (runs on the Hermes host)
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

**On the Omarchy laptop** (the Voxtype side):

```bash
git clone <this repo>
cd omarchy-speak-to-hermes
./install.sh
```

Then:
1. `ssh-keygen -t ed25519 -N "" -f ~/.ssh/speak_to_hermes`
2. Edit `~/.config/speak-to-hermes/config.sh` — set `HERMES_SSH_HOST`
3. Add the two lines from `hypr/bindings.lua.snippet` to
   `~/.config/hypr/bindings.lua`
4. `hyprctl reload` — if that doesn't pick up new binds, Omarchy's Lua
   config sometimes needs `omarchy-restart-hyprctl` instead (a full
   Hyprland config re-source, not just a keyword reload)
5. `pip install --user edge-tts` for a real voice, or `pacman -S espeak-ng`
   for a robotic fallback. Without either, you still get the text in a
   desktop notification.

**On the Hermes host:**

```bash
./install-relay.sh
```

Then add the laptop's `~/.ssh/speak_to_hermes.pub` to that account's
`~/.ssh/authorized_keys` — **read "Security model" below first.**

## Security model — read this before you trust it

This project's safety depends entirely on how the two machines reach each
other, not on anything in these scripts. Be honest with yourself about
which situation you're in:

- **Plain SSH, normal network.** A `command="..."` restriction in
  `authorized_keys` works as expected: that key can run
  `hermes-speak-relay.sh` and nothing else, confirmed by checking the
  `allow:` header on a rejected method and testing a raw command gets
  refused.
- **Tailscale SSH enabled on the Hermes host.** We built this on exactly
  that setup, and found out the hard way: Tailscale SSH authenticates the
  *tailnet peer*, not the *SSH key* — a verbose connection log will show
  `Authenticated ... using "none"`. Once that happens, **every
  `authorized_keys` restriction on that key is silently irrelevant**,
  because OpenSSH's own key-checking step never ran. Whatever Tailscale's
  ACL policy grants that peer (commonly: a normal login as the target
  user) is what you get, regardless of which key was presented.
  - If you're on this setup, treat it as: *the laptop has the same trust
    level as any other device on your tailnet already has to that
    account* — which is probably fine between two devices you own, and
    not something to rely on as an additional restriction.
  - To actually restrict it under Tailscale SSH, you need either a
    dedicated Tailscale ACL grant that maps this connection to a separate,
    unprivileged local account whose login shell *is*
    `hermes-speak-relay.sh` (so there's no shell to escape to, independent
    of which auth method ran), or you disable Tailscale SSH for this
    specific path and fall back to plain SSH's own key checking.

Either way: use a key generated just for this (`speak_to_hermes`), not your
daily driver key, so revoking it later doesn't touch anything else.

## Files

- `bin/speak-to-hermes.sh` — runs on the laptop, bound to a hotkey
- `bin/hermes-speak-relay.sh` — runs on the Hermes host, the only thing the
  laptop is meant to be able to call
- `config.example.sh` — copy to `~/.config/speak-to-hermes/config.sh`
- `hypr/bindings.lua.snippet` — the two Hyprland bind lines
- `install.sh`, `install-relay.sh` — one-shot installers for each side

## License

MIT — see [LICENSE](LICENSE).
