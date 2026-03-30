#!/bin/bash
set -euo pipefail

REPO=/home/pi/pi-kiosk
cd "$REPO"

DO_STASH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-stash)
      DO_STASH=0
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: /home/pi/pi-kiosk/scripts/git_update_install.sh [--no-stash]

  --no-stash   Do not auto-stash local tracked changes before pull.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

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

if [[ "$DO_STASH" -eq 1 ]] && { ! git diff --quiet || ! git diff --cached --quiet; }; then
  git stash push -m "pi-kiosk-update-autostash" >/dev/null
  STASH_CREATED=1
  echo "pi-kiosk: stashed local changes before update."
fi

git pull --ff-only

if [[ ! -f /home/pi/pi-kiosk/install.sh ]]; then
  echo "pi-kiosk: missing /home/pi/pi-kiosk/install.sh after pull." >&2
  exit 1
fi

exec sudo /bin/bash /home/pi/pi-kiosk/install.sh --no-apt
