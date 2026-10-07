---
name: omarchy-speak-to-hermes
description: Use when setting up or fixing voice chat with Hermes on Omarchy.
version: 1.0.0
author: Pablo
license: MIT
metadata:
  hermes:
    tags: [omarchy, voxtype, voice, dictation, hyprland, hermes]
    related_skills: []
---

# omarchy-speak-to-hermes (agent guide)

Read this first if you are an AI agent asked to install, use, debug or extend this project. A human-oriented overview is in `README.md`.

## What it is
A second dictation hotkey for Omarchy's built-in Voxtype dictation. Voxtype's normal hotkey transcribes speech and types it into the focused window. This project adds a hotkey that sends the transcript to a Hermes agent and speaks the reply aloud.

## Hotkeys (defaults from `hypr/bindings.lua.snippet`)
| Keys | Action |
|------|--------|
| `SUPER + h` | Plain Voxtype dictation. Types into the focused window. Not part of this project; it is Voxtype's own `voxtype record toggle`. |
| `SUPER + SHIFT + h` | **Speak to Hermes.** Toggle: press once to start recording, press again to stop and send. The reply is spoken and shown as a notification. |
| `SUPER + SHIFT + k` | Toggle the local name wake. Off means the microphone is not listening for the name. |
| `SUPER + SHIFT + j` | Toggle the transcript window (what was said, which model answered, how long it took). |

Rules that bite:
- Hyprland reads an uppercase key as Shift plus that key. Write binds with lowercase letters and `SHIFT` explicitly, or two binds collide on the same combo.
- Newer Omarchy keeps binds in `~/.config/hypr/bindings.lua` (`o.bind(...)`). Older setups use `bindings.conf`. Search both before concluding a bind is missing.
- If `hyprctl reload` does not pick up new binds, run `omarchy-restart-hyprctl`.

## Parts and where each runs
- **Laptop (Omarchy, Voxtype side):** `bin/speak-to-hermes.sh` (record with `pw-record`, transcribe with `voxtype transcribe`, POST, speak the reply), `bin/speak-to-hermes-transcript.py`, optional `osd/hermes-voice/` HUD style, optional `omarchy-bar-widget/` voice picker. Config in `~/.config/speak-to-hermes/` (`config.sh`, `token`, `voice`).
- **Hermes host:** `bin/hermes-speak-relay.py`, a `systemd --user` unit. One route, `POST /speak`, one effect: one `hermes chat -Q` turn.
- Flow: hotkey, record, Voxtype STT, bearer-token POST over a private network (Tailscale), Hermes turn, reply text back, TTS on the laptop (edge-tts, else espeak-ng, else text notification only).

## Install (summary; full steps in README)
1. On the Hermes host: `./install-relay.sh`. It prints a token and URL. Bind to a private interface IP, never `0.0.0.0`.
2. On the laptop: `./install.sh`. Put the URL in `~/.config/speak-to-hermes/config.sh` (`HERMES_RELAY_URL`) and the token in `~/.config/speak-to-hermes/token` (mode 600).
3. Add the lines from `hypr/bindings.lua.snippet` to the Hyprland bindings file, then reload.
4. `pip install --user edge-tts` for a real voice. Optionally install the HUD style and run `systemctl --user restart voxtype`.

## Verify (do this before saying it works)
- Relay: the service is active and the port is listening on the private IP.
- Laptop: `~/.local/bin/speak-to-hermes.sh` exists and is executable; `voxtype` is running (`pgrep voxtype`).
- Binding: `grep -rn "speak-to-hermes" ~/.config/hypr/` shows the `SUPER + SHIFT + h` line.
- Round trip: ask the human to press the hotkey once. Do not simulate key presses and do not take over their mic or keyboard.

## Debug map
| Symptom | Likely cause |
|---------|--------------|
| Hotkey does nothing | Bind missing or Hyprland not reloaded; uppercase-key collision; script not executable. Also: Voxtype's own glow is one screen — if you are looking at the other monitor, the every-screen pill (`speak-to-hermes-osd.service`) is what should appear there. Name wake is separate: `speak-to-hermes-wake.service`, phrase file `~/.config/speak-to-hermes/wake-phrase`. Audio before the name stays on the machine. |
| Recorded but no reply | Wrong `HERMES_RELAY_URL`, missing or wrong token, device not in `HERMES_SPEAK_ALLOWED_DEVICES`, relay not running |
| Reply takes many seconds | The relay was running a full tool-using agent turn. Voice turns are one short spoken reply (`--max-turns 1`, no tool catalog). Transcription for this flow uses `tiny.en`, not the daemon's larger Whisper model. |
| Reply text but no sound | `edge-tts` and `espeak-ng` both missing; check the voice file and network for edge-tts |
| Transcript includes log noise | Use the current `voxtype transcribe` handling in `speak-to-hermes.sh`; stdout must be the text only |
| `Config section 'parakeet' could not be read` | `[parakeet]` exists without `model`. Voxtype 1.1.0 requires that key and skips the whole table, warning on every invocation. Run `bin/repair-voxtype-parakeet.sh`. Do not write a partial `[parakeet]` table (a lone `streaming = false` is already the default). |
| 401 or 403 from relay | Token mismatch, or the Tailscale identity check rejected the device |

## Security rules (do not weaken)
- Relay binds to one private IP, requires a bearer token, and can verify the caller with `tailscale whois`. Keep all three.
- One verb only. Never add a shell, file or command route to the relay.
- Tokens live only in the two mode-600 files. Never print them, commit them or paste them into chat.

## Extending
- Keep the repo generic: no personal names, hostnames, IPs or tokens. The two attribution lines to the author are the only exceptions.
- Model per utterance: set `HERMES_SPEAK_MODEL` (passed to the relay as `-m`).
- Voice: `~/.config/speak-to-hermes/voice` or `HERMES_VOICE`.
- After changing a script, copy it to `~/.local/bin/` on the laptop and test with one real utterance.
