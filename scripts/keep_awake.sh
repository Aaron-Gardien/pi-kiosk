#!/bin/bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/home/pi/.Xauthority}"

while true; do
  xset s off >/dev/null 2>&1 || true
  xset -dpms >/dev/null 2>&1 || true
  xset s noblank >/dev/null 2>&1 || true
  xset dpms force on >/dev/null 2>&1 || true

  if command -v xrandr >/dev/null 2>&1; then
    for out in HDMI-1 HDMI-2 HDMI-A-1 HDMI-A-2; do
      xrandr --output "$out" --auto >/dev/null 2>&1 || true
    done
  fi
  sleep 60
done
