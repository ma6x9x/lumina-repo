#!/usr/bin/env bash
# Pull FKT dumps from the 12 mini so the Mac agent can read them.
# Key auth as root; no password. Override: FKT_HOST=root@ip ./pull.sh
set -euo pipefail
HOST="${FKT_HOST:-root@192.168.1.231}"
PORT="${FKT_PORT:-22}"
DEST="${FKT_PULL:-$(cd "$(dirname "$0")" && pwd)/pulled}"
DESK="${HOME}/Desktop/lumina_primitives/fkt_pull"
mkdir -p "$DEST" "$DESK"
REMOTE=/var/mobile/Documents
FILES=(
  lum1na-fkt-dump.txt
  lum1na-fkt-handoff.txt
  lum1na-fkt-diff.txt
  lum1na-fkt-snap-a.txt
  lum1na-fkt-snap-b.txt
  lum1na-fkt-surfaces.txt
  lum1na-fkt-kcscan.txt
  lum1na-fkt-ane.txt
)
echo "==> $HOST:$REMOTE → $DEST"
ok=0
for f in "${FILES[@]}"; do
  if scp -P "$PORT" -o ConnectTimeout=8 "${HOST}:${REMOTE}/${f}" "$DEST/${f}"; then
    ok=$((ok + 1))
  else
    echo "skip (missing on phone): $f" >&2
  fi
done
if [[ "$ok" -eq 0 ]]; then
  echo "error: nothing pulled — is the mini at $HOST on Wi-Fi?" >&2
  exit 1
fi
cp -f "$DEST"/* "$DESK/" 2>/dev/null || true
ls -lah "$DEST"
echo "==> also copied to $DESK"
echo "Say: read lum1na-fkt/pulled/lum1na-fkt-dump.txt"
