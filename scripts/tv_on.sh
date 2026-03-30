#!/bin/bash
set -euo pipefail

# CEC adapter (override with KIOSK_CEC_DEVICE if needed).
CEC_DEV="${KIOSK_CEC_DEVICE:-/dev/cec1}"
# Physical address for the TV input to select (HDMI 1 = 1.0.0.0 per CEC). Override with
# KIOSK_CEC_ACTIVE_PHYS (e.g. 2.0.0.0) if the Pi sits on another TV port labeled HDMI 2.
HDMI_PHYS="${KIOSK_CEC_ACTIVE_PHYS:-1.0.0.0}"

cec-ctl -d "$CEC_DEV" --playback --to 0 --image-view-on || true
sleep 1
cec-ctl -d "$CEC_DEV" --playback --to 0 --active-source "phys-addr=$HDMI_PHYS" || true
