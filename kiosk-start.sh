#!/bin/bash
set -euo pipefail

rm -f /tmp/kiosk.disabled
nohup /home/pi/kiosk_wayland.sh >/dev/null 2>&1 &

