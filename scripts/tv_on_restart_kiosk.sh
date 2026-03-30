#!/bin/bash
set -euo pipefail

# Run after TV powers: CEC (wake + HDMI 1 / active source), then restart Chromium kiosk.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/home/pi/.Xauthority}"

"$SCRIPT_DIR/tv_on.sh" || true
sleep 2
"$SCRIPT_DIR/kiosk-stop.sh" || true
sleep 1
export NO_TV_ON=1
"$SCRIPT_DIR/kiosk-start.sh" || true

exit 0
