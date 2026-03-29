#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DISABLE_FLAG="/tmp/kiosk.disabled"
URL_FILE="/home/pi/kiosk_url.txt"
PROFILE_DIR="/home/pi/.config/chromium-kiosk"
LOADING_PAGE_BASE="file://${REPO_ROOT}/loading.html"

[[ -f "$DISABLE_FLAG" ]] && exit 0

KIOSK_URL="$(grep -v '^[[:space:]]*#' "$URL_FILE" | head -n 1 | tr -d '\r' || true)"
[[ -z "${KIOSK_URL}" ]] && exit 1

mkdir -p "$PROFILE_DIR"

if [[ "${NO_TV_ON:-0}" != "1" ]]; then
  "$SCRIPT_DIR/tv_on.sh" || true
fi

CHROMIUM_BIN=""
if command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium"
else
  exit 1
fi

enc() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1] if len(sys.argv)>1 else ""))' "$1"; }

while true; do
  [[ -f "$DISABLE_FLAG" ]] && exit 0

  HOSTNAME="$(hostname || true)"
  IPS="$(hostname -I 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//' || true)"
  LOADING_PAGE="${LOADING_PAGE_BASE}#target=$(enc "$KIOSK_URL")&host=$(enc "$HOSTNAME")&ips=$(enc "$IPS")"

  "$CHROMIUM_BIN" \
    --ozone-platform=wayland \
    --enable-features=UseOzonePlatform \
    --no-first-run \
    --noerrdialogs \
    --disable-infobars \
    --kiosk \
    --password-store=basic \
    --use-mock-keychain \
    --user-data-dir="$PROFILE_DIR" \
    --disable-features=PasswordManager \
    --disable-session-crashed-bubble \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    --disk-cache-size=10000000 \
    "$LOADING_PAGE" || true

  sleep 2
done
