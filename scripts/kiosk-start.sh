#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rm -f /tmp/kiosk.disabled
nohup "$SCRIPT_DIR/kiosk.sh" >/dev/null 2>&1 &
