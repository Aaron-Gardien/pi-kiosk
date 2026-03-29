#!/bin/bash
set -euo pipefail

touch /tmp/kiosk.disabled

pkill -f "/usr/lib/chromium/chromium" || true
pkill -f "chromium --" || true
pkill -f "/home/pi/kiosk_wayland.sh" || true

