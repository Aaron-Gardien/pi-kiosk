#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for _ in 1 2 3; do
  "$SCRIPT_DIR/tv_on.sh" || true
  sleep 2
done
