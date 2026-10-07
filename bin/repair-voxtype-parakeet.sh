#!/usr/bin/env bash
# Drop a [parakeet] table Voxtype 1.1.0 cannot deserialize.
#
# [parakeet] is Option<ParakeetConfig> (default: absent). `model` has no
# serde default, so a table that only sets `streaming = false` fails to
# parse. Voxtype then skips the whole section and warns on every
# invocation:
#   Config section 'parakeet' could not be read and is using defaults.
# That streaming value is already the default, and a missing table is
# the same result without the warning. A table that sets `model` is a
# real Parakeet config and is left alone.
#
# Usage: repair-voxtype-parakeet.sh [path-to-config.toml]
# Default path: ${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml
set -euo pipefail

CONFIG="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml}"
if [ ! -f "$CONFIG" ]; then
  echo "no voxtype config at $CONFIG — nothing to repair"
  exit 0
fi

python3 - "$CONFIG" << 'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines(keepends=True)

def is_header(line: str) -> bool:
    s = line.strip()
    return len(s) >= 3 and s.startswith("[") and s.endswith("]") and '"' not in s

def has_model_key(body: list[str]) -> bool:
    for raw in body:
        code = raw.split("#", 1)[0].strip()
        if "=" not in code:
            continue
        key = code.split("=", 1)[0].strip()
        if key == "model":
            return True
    return False

out: list[str] = []
i = 0
removed = False
while i < len(lines):
    if lines[i].strip() == "[parakeet]":
        j = i + 1
        body: list[str] = []
        while j < len(lines) and not is_header(lines[j]):
            body.append(lines[j])
            j += 1
        if has_model_key(body):
            out.append(lines[i])
            out.extend(body)
        else:
            removed = True
            # Keep comments and blank lines. They often belong to the
            # next topic, not to this table (a dumped `streaming = false`
            # was inserted above an older comment block).
            for raw in body:
                code = raw.split("#", 1)[0].strip()
                if code and "=" in code:
                    continue
                out.append(raw)
        i = j
        continue
    out.append(lines[i])
    i += 1

if not removed:
    print("parakeet section already readable or absent")
    sys.exit(0)

new = "".join(out)
while "\n\n\n\n" in new:
    new = new.replace("\n\n\n\n", "\n\n\n")
path.write_text(new if new.endswith("\n") or text == "" else new + "\n")
print(f"removed unreadable [parakeet] section from {path}")
PY
