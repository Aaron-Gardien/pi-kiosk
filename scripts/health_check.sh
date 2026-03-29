#!/bin/bash
set -euo pipefail

echo "=== Pi Kiosk Health Check ==="
date
echo

echo "Host: $(hostname)"
echo "IP: $(hostname -I 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//' || true)"
echo

echo "--- Kiosk process ---"
if pgrep -fa "chromium.*--kiosk" >/dev/null 2>&1; then
  echo "Kiosk chromium: RUNNING"
  pgrep -fa "chromium.*--kiosk" | sed -n '1,3p'
else
  echo "Kiosk chromium: NOT RUNNING"
fi
echo

echo "--- Disable flag ---"
if [[ -f /tmp/kiosk.disabled ]]; then
  echo "/tmp/kiosk.disabled is present (kiosk disabled)"
else
  echo "/tmp/kiosk.disabled is not present"
fi
echo

echo "--- TV timers ---"
systemctl status --no-pager pi-tv-on.timer pi-tv-off.timer | sed -n '1,80p'
echo

echo "--- Last TV ON service logs ---"
journalctl -u pi-tv-on.service --no-pager -n 8 || true
echo

echo "--- Last TV OFF service logs ---"
journalctl -u pi-tv-off.service --no-pager -n 8 || true
echo

echo "--- Admin service ---"
systemctl status --no-pager pi-kiosk-admin.service | sed -n '1,35p'

