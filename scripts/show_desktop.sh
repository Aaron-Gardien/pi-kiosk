#!/bin/bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/home/pi/.Xauthority}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/kiosk-stop.sh" || true

if command -v lxpanel-pi >/dev/null 2>&1; then
  nohup lxpanel-pi >/dev/null 2>&1 &
elif command -v lxpanel >/dev/null 2>&1; then
  nohup lxpanel --profile LXDE-pi >/dev/null 2>&1 &
fi

if command -v pcmanfm-pi >/dev/null 2>&1; then
  nohup pcmanfm-pi --desktop >/dev/null 2>&1 &
elif command -v pcmanfm >/dev/null 2>&1; then
  nohup pcmanfm --desktop --profile LXDE-pi >/dev/null 2>&1 &
fi

if command -v lxsession-xdg-autostart >/dev/null 2>&1; then
  nohup lxsession-xdg-autostart >/dev/null 2>&1 &
fi
