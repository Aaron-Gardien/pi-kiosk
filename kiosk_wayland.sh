#!/bin/bash
# Legacy name: forwards to the X11 kiosk script.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/kiosk.sh" "$@"
