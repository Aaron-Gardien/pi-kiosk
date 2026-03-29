#!/bin/bash
set -euo pipefail

cec-ctl -d /dev/cec1 --playback --to 0 --custom-command cmd=0x04 || true

