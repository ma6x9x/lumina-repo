#!/usr/bin/env bash
set -euo pipefail
# 12 mini 17.3 LAN. Override: FKT_HOST=root@ip FKT_PORT=22 ./deploy.sh
HOST="${FKT_HOST:-root@192.168.1.231}"
PORT="${FKT_PORT:-22}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> make package"
export THEOS="${THEOS:-/Users/kolby/theos}"
make clean package

DEB="$(ls -t packages/*.deb 2>/dev/null | head -n 1 || true)"
if [[ -z "${DEB}" ]]; then
  echo "error: no .deb" >&2
  exit 1
fi
echo "==> ${DEB}"
scp -P "${PORT}" "${DEB}" "${HOST}:/var/root/"
DEB_NAME="$(basename "${DEB}")"
ssh -p "${PORT}" "${HOST}" "dpkg -i '/var/root/${DEB_NAME}' && (uicache -p /var/jb/Applications/Lum1naFKTApp.app || uicache || true) && killall -9 SpringBoard"
echo "==> installed. Open Lum1naFKT app → Dump Now"
echo "    helper: /var/jb/usr/bin/lum1na-fkt-dump (setuid root)"
echo "    file: /var/mobile/Documents/lum1na-fkt-dump.txt"
echo "    expect: backend=dopamine… kbase≠0 magic=0xfeedfacf"
