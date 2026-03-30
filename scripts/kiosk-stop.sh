#!/bin/bash
set -euo pipefail

touch /tmp/kiosk.disabled

pkill -f "/usr/lib/chromium/chromium" || true
pkill -f "chromium --" || true
pkill -f "kiosk_wayland.sh" || true
pkill -f "scripts/kiosk.sh" || true
pkill -f "pi-kiosk/scripts/kiosk.sh" || true
