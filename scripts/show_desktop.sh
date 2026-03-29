#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/kiosk-stop.sh" || true

nohup /usr/bin/lwrespawn /usr/bin/wf-panel-pi >/dev/null 2>&1 &
nohup /usr/bin/lwrespawn /usr/bin/pcmanfm-pi >/dev/null 2>&1 &
nohup /usr/bin/lxsession-xdg-autostart >/dev/null 2>&1 &
