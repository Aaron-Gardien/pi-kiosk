#!/bin/bash
set -euo pipefail
REPO="/home/pi/pi-kiosk"
cd "$REPO"
git pull --ff-only
sudo "$REPO/install.sh" --no-apt
