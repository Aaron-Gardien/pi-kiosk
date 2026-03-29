#!/bin/bash
set -euo pipefail

cec-ctl -d /dev/cec1 --playback --to 0 --standby || true

