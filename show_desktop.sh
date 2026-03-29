#!/bin/bash
set -euo pipefail

# Show the Pi GUI: stop kiosk first so Chromium doesn't keep covering it.
/home/pi/kiosk-stop.sh || true

nohup /usr/bin/lwrespawn /usr/bin/wf-panel-pi >/dev/null 2>&1 &
nohup /usr/bin/lwrespawn /usr/bin/pcmanfm-pi >/dev/null 2>&1 &
nohup /usr/bin/lxsession-xdg-autostart >/dev/null 2>&1 &

