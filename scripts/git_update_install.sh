#!/bin/bash
set -euo pipefail

REPO=/home/pi/pi-kiosk
cd "$REPO"

if [[ ! -d .git ]]; then
  echo "pi-kiosk: not a git clone; skipping update." >&2
  exit 0
fi

git pull --ff-only

exec sudo /home/pi/pi-kiosk/install.sh --no-apt
