#!/bin/bash
set -euo pipefail

while true; do
  /usr/bin/wlr-randr --output HDMI-A-1 --on >/dev/null 2>&1 || true
  /usr/bin/wlr-randr --output HDMI-A-2 --on >/dev/null 2>&1 || true
  /usr/bin/wlr-randr --output HDMI-1 --on >/dev/null 2>&1 || true
  /usr/bin/wlr-randr --output HDMI-2 --on >/dev/null 2>&1 || true
  sleep 60
done

