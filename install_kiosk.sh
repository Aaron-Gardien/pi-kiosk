#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  /home/pi/install_kiosk.sh --url 'https://your-real-site.example/path' [options]

Options:
  --url URL                 Required unless kiosk_url.txt already contains a URL
  --install-cron            Install a cron schedule for tv_on/tv_off
  --on HH:MM                TV ON time (default: 07:30) used with --install-cron
  --off HH:MM               TV OFF time (default: 18:00) used with --install-cron
  --skip-packages           Do not apt install dependencies
  --help                    Show this help

Notes:
  - This script sets up kiosk autostart via ~/.bash_profile -> startx -> ~/.xinitrc.
  - Raspberry Pi OS auto-login is still configured via raspi-config (recommended).
EOF
}

URL=""
INSTALL_CRON="0"
ON_TIME="07:30"
OFF_TIME="18:00"
SKIP_PACKAGES="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:-}"
      shift 2
      ;;
    --install-cron)
      INSTALL_CRON="1"
      shift
      ;;
    --on)
      ON_TIME="${2:-}"
      shift 2
      ;;
    --off)
      OFF_TIME="${2:-}"
      shift 2
      ;;
    --skip-packages)
      SKIP_PACKAGES="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Please run as user 'pi' (not root)." >&2
  exit 1
fi

HOME_DIR="${HOME:-/home/pi}"
if [[ "$HOME_DIR" != "/home/pi" ]]; then
  echo "This installer expects /home/pi. Current HOME=$HOME_DIR" >&2
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

validate_time() {
  local t="$1"
  if [[ ! "$t" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "Invalid time '$t' (expected HH:MM 24h)." >&2
    exit 2
  fi
}

validate_time "$ON_TIME"
validate_time "$OFF_TIME"

if [[ "$SKIP_PACKAGES" != "1" ]]; then
  echo "Installing packages..."
  sudo apt update
  sudo apt install -y \
    xserver-xorg \
    x11-xserver-utils \
    xinit \
    openbox \
    chromium \
    unclutter \
    cec-utils
fi

URL_FILE="/home/pi/kiosk_url.txt"
if [[ -n "$URL" ]]; then
  mkdir -p /home/pi
  cat >"$URL_FILE" <<EOF
$URL
EOF
fi

if [[ ! -f "$URL_FILE" ]]; then
  cat >"$URL_FILE" <<'EOF'
# Put your real kiosk URL on the next line (single line, no quotes).
EOF
fi

KIOSK_URL="$(grep -v '^[[:space:]]*#' "$URL_FILE" | head -n 1 | tr -d '\r' || true)"
if [[ -z "${KIOSK_URL}" ]]; then
  echo "No URL configured in $URL_FILE." >&2
  echo "Re-run with: /home/pi/install_kiosk.sh --url 'https://your-real-site/...'" >&2
  exit 1
fi

cat >/home/pi/tv_on.sh <<'EOF'
#!/bin/bash
set -euo pipefail

for _ in {1..3}; do
  echo "on 0" | cec-client -s -d 1 || true
  sleep 2
done
EOF

cat >/home/pi/tv_off.sh <<'EOF'
#!/bin/bash
set -euo pipefail

for _ in {1..3}; do
  echo "standby 0" | cec-client -s -d 1 || true
  sleep 2
done
EOF

cat >/home/pi/kiosk.sh <<'EOF'
#!/bin/bash
set -euo pipefail

URL_FILE="/home/pi/kiosk_url.txt"

if [[ ! -f "$URL_FILE" ]]; then
  echo "Missing $URL_FILE. Create it with your kiosk URL." >&2
  exit 1
fi

KIOSK_URL="$(grep -v '^[[:space:]]*#' "$URL_FILE" | head -n 1 | tr -d '\r' || true)"
if [[ -z "${KIOSK_URL}" ]]; then
  echo "No URL set in $URL_FILE (first non-comment line). Refusing to start." >&2
  exit 1
fi

xset s off || true
xset -dpms || true
xset s noblank || true

unclutter -idle 0.5 -root &

/home/pi/tv_on.sh || true

for _ in {1..60}; do
  if ip route | grep -q '^default ' && ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

CHROMIUM_BIN=""
if command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium"
else
  echo "Chromium not found (chromium/chromium-browser)." >&2
  exit 1
fi

while true; do
  "$CHROMIUM_BIN" \
    --noerrdialogs \
    --disable-infobars \
    --kiosk \
    --disable-session-crashed-bubble \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    --disk-cache-size=10000000 \
    "$KIOSK_URL" || true
  sleep 2
done
EOF

cat >/home/pi/.xinitrc <<'EOF'
#!/bin/bash
set -euo pipefail

command -v openbox-session >/dev/null 2>&1 && openbox-session &

exec /home/pi/kiosk.sh
EOF

cat >/home/pi/.bash_profile <<'EOF'
#!/bin/bash

if [[ -z "${DISPLAY:-}" && "${XDG_VTNR:-0}" -eq 1 ]]; then
  exec startx
fi
EOF

chmod +x /home/pi/kiosk.sh /home/pi/tv_on.sh /home/pi/tv_off.sh /home/pi/.xinitrc /home/pi/.bash_profile

need_cmd cec-client
need_cmd unclutter
need_cmd startx
need_cmd xset
command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1 || { echo "Chromium missing." >&2; exit 1; }

if [[ "$INSTALL_CRON" == "1" ]]; then
  ON_MIN="${ON_TIME#*:}"; ON_HOUR="${ON_TIME%%:*}"
  OFF_MIN="${OFF_TIME#*:}"; OFF_HOUR="${OFF_TIME%%:*}"

  tmp_cron="$(mktemp)"
  trap 'rm -f "$tmp_cron"' EXIT

  # Preserve existing crontab (if any) and replace our managed block.
  (crontab -l 2>/dev/null || true) | awk '
    BEGIN {skip=0}
    /^# BEGIN PI-KIOSK-TV-POWER$/ {skip=1; next}
    /^# END PI-KIOSK-TV-POWER$/ {skip=0; next}
    skip==0 {print}
  ' >"$tmp_cron"

  cat >>"$tmp_cron" <<EOF
# BEGIN PI-KIOSK-TV-POWER
$ON_MIN $ON_HOUR * * * /home/pi/tv_on.sh
$OFF_MIN $OFF_HOUR * * * /home/pi/tv_off.sh
# END PI-KIOSK-TV-POWER
EOF

  crontab "$tmp_cron"
fi

echo "Install complete."
echo "URL: $KIOSK_URL"
echo "Next:"
echo "  - Ensure auto-login is enabled (raspi-config recommended)"
echo "  - Reboot to start kiosk automatically"

