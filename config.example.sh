# Copy to ~/.config/speak-to-hermes/config.sh and edit.

# Where your Hermes agent lives. Over Tailscale this is just "user@100.x.x.x".
# NOTE: if Tailscale SSH is enabled on that host, it authenticates tailnet
# peers itself and SKIPS normal SSH key checks (see "Security model" in the
# README) — know which model you're in before you rely on key restrictions.
export HERMES_SSH_HOST="user@100.x.x.x"

# Dedicated key for this one purpose (don't reuse your main key).
# ssh-keygen -t ed25519 -N "" -f ~/.ssh/speak_to_hermes
export HERMES_SSH_KEY="$HOME/.ssh/speak_to_hermes"

# Where hermes-speak-relay.sh landed on the Hermes host.
export HERMES_RELAY_PATH="/usr/local/bin/hermes-speak-relay.sh"

# Any edge-tts voice name. Falls back to espeak-ng if edge-tts isn't
# installed, and to text-only notifications if neither is.
export HERMES_VOICE="en-US-AvaNeural"
