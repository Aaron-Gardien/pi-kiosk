#!/bin/bash
set -euo pipefail
REPO="/home/pi/pi-kiosk"
cd "$REPO"

if [[ ! -d .git ]]; then
  echo "pi-kiosk: not a git clone; skipping update." >&2
  exit 0
fi

STASH_CREATED=0
cleanup() {
  if [[ "$STASH_CREATED" -eq 1 ]]; then
    if git stash pop --index >/dev/null 2>&1; then
      echo "pi-kiosk: restored local changes after update."
    else
      echo "pi-kiosk: local changes could not be auto-restored cleanly." >&2
      echo "Resolve conflicts, then run: git stash list" >&2
      return 1
    fi
  fi
}
trap cleanup EXIT

if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push -m "pi-kiosk-update-autostash" >/dev/null
  STASH_CREATED=1
  echo "pi-kiosk: stashed local changes before update."
fi

git pull --ff-only
sudo "$REPO/install.sh" --no-apt
