#!/usr/bin/env bash
# install-relay.sh — run this on the machine that runs your Hermes agent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -m 755 "$HERE/bin/hermes-speak-relay.sh" /usr/local/bin/hermes-speak-relay.sh 2>/dev/null \
  || sudo install -m 755 "$HERE/bin/hermes-speak-relay.sh" /usr/local/bin/hermes-speak-relay.sh
echo "Installed /usr/local/bin/hermes-speak-relay.sh"
echo
echo "Now add the laptop's public key (~/.ssh/speak_to_hermes.pub) to this"
echo "account's ~/.ssh/authorized_keys. See README 'Security model' before"
echo "you assume that line restricts anything — on a tailnet with Tailscale"
echo "SSH enabled, it currently does not."
