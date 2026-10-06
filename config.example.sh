# Copy to ~/.config/speak-to-hermes/config.sh and edit.

# The relay's URL. Bind it to your tailscale/private interface, not
# 0.0.0.0 -- see install-relay.sh and the README's "Security model".
export HERMES_RELAY_URL="http://100.x.x.x:47113/speak"

# Where the bearer token landed on this laptop (install-relay.sh prints
# the token once; put it in this file, mode 600, nowhere else).
export HERMES_TOKEN_FILE="$HOME/.config/speak-to-hermes/token"

# Any edge-tts voice name. Falls back to espeak-ng if edge-tts isn't
# installed, and to text-only notifications if neither is.
export HERMES_VOICE="en-US-AvaNeural"
