#!/usr/bin/env bash
# install-relay.sh — run this on the machine that runs your Hermes agent.
# No root needed: it's a systemd --user unit.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOKEN_DIR="$HOME/.config/hermes-speak"
mkdir -p "$TOKEN_DIR"
TOKEN_FILE="$TOKEN_DIR/token"
if [ ! -f "$TOKEN_FILE" ]; then
  umask 077
  python3 -c "import secrets; print(secrets.token_urlsafe(32))" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi

mkdir -p "$HOME/.local/bin"
install -m 755 "$HERE/bin/hermes-speak-relay.py" "$HOME/.local/bin/hermes-speak-relay.py"

read -rp "Interface IP to bind to (your tailscale0 / private IP, NOT 0.0.0.0): " BIND_IP
if [ -z "$BIND_IP" ] || [ "$BIND_IP" = "0.0.0.0" ]; then
  echo "Refusing an empty IP or 0.0.0.0 -- that exposes the relay to everything." >&2
  exit 1
fi

mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/hermes-speak-relay.service" << EOF
[Unit]
Description=Hermes speak-to-hermes HTTP relay (bind-scoped + bearer token)
After=network-online.target

[Service]
Type=simple
Environment=HERMES_SPEAK_BIND_HOST=$BIND_IP
ExecStart=/usr/bin/python3 $HOME/.local/bin/hermes-speak-relay.py
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now hermes-speak-relay.service

echo
echo "Token (put this in the laptop's ~/.config/speak-to-hermes/token, mode 600):"
cat "$TOKEN_FILE"
echo
echo "Relay URL for the laptop's config.sh: http://$BIND_IP:47113/speak"
