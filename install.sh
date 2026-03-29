#!/bin/bash
set -euo pipefail

# Idempotent install/update for pi-kiosk. Must run as root.

PI_USER="pi"
PI_HOME="/home/pi"
REPO="${PI_HOME}/pi-kiosk"
URL_FILE="${PI_HOME}/kiosk_url.txt"

usage() {
  cat <<'U'
Usage: sudo /home/pi/pi-kiosk/install.sh [--url https://...] [--no-apt]

  --url URL     Write /home/pi/kiosk_url.txt (required if that file has no URL yet)
  --no-apt      Skip apt-get install (faster repeat runs after git pull)

Installs systemd units, Labwc autostart snippet, nightly kiosk restart cron,
and ensures repo scripts are executable. Re-run after every git pull.
U
}

SKIP_APT=0
URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --no-apt) SKIP_APT=1; shift ;;
    --url)
      URL="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0 $*" >&2
  exit 1
fi

if [[ ! -d "$REPO" ]]; then
  echo "Missing repo at $REPO (clone the git repository there first)." >&2
  exit 1
fi

first_line_url() {
  grep -v '^[[:space:]]*#' "$URL_FILE" 2>/dev/null | head -n 1 | tr -d '\r' || true
}

if [[ -n "$URL" ]]; then
  if [[ ! "$URL" =~ ^https?:// ]]; then
    echo "--url must start with http:// or https://" >&2
    exit 2
  fi
  printf '%s\n' "$URL" >"$URL_FILE"
  chown "${PI_USER}:${PI_USER}" "$URL_FILE"
  chmod 0644 "$URL_FILE"
fi

if [[ ! -f "$URL_FILE" ]] || [[ -z "$(first_line_url)" ]]; then
  echo "Set kiosk URL first, e.g. sudo $REPO/install.sh --url 'https://your-site/'" >&2
  exit 1
fi

mkdir -p "${REPO}/logs"
chown "${PI_USER}:${PI_USER}" "${REPO}/logs"

if [[ "$SKIP_APT" -eq 0 ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y \
    python3-flask \
    chromium-browser \
    wlr-randr \
    v4l-utils \
    || apt-get install -y python3-flask chromium wlr-randr v4l-utils
fi

chown -R "${PI_USER}:${PI_USER}" "$REPO"
find "${REPO}/scripts" -type f -name '*.sh' -exec chmod +x {} \;
chmod +x "${REPO}/install.sh" "${REPO}/update.sh" 2>/dev/null || true

for unit in "${REPO}/systemd"/*.service "${REPO}/systemd"/*.timer; do
  [[ -f "$unit" ]] || continue
  install -m 0644 "$unit" "/etc/systemd/system/$(basename "$unit")"
done

merge_labwc_autostart() {
  local f="/etc/xdg/labwc/autostart"
  local tmp
  tmp="$(mktemp)"
  mkdir -p "$(dirname "$f")"
  if [[ -f "$f" ]]; then
    awk '
      BEGIN { skip=0 }
      /^# BEGIN PI-KIOSK-DEPLOY$/ { skip=1; next }
      /^# END PI-KIOSK-DEPLOY$/ { skip=0; next }
      skip==0 { print }
    ' "$f" >"$tmp"
    # Migrate away from old paths (one-time cleanup on each install)
    sed -e '\|/home/pi/Documents/pi-kiosk/keep_awake.sh|d' \
        -e '\|^/home/pi/kiosk_wayland\.sh[[:space:]]*&|d' "$tmp" >"${tmp}.2"
    mv "${tmp}.2" "$tmp"
  else
    : >"$tmp"
  fi
  cat >>"$tmp" <<'LABEOF'

# BEGIN PI-KIOSK-DEPLOY
/home/pi/pi-kiosk/scripts/keep_awake.sh &
/home/pi/pi-kiosk/scripts/kiosk_wayland.sh &
# END PI-KIOSK-DEPLOY
LABEOF
  install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

merge_labwc_autostart

install -m 0644 "${REPO}/config/cron-pi-kiosk-restart" /etc/cron.d/pi-kiosk-restart

systemctl daemon-reload

systemctl enable pi-kiosk-admin.service
systemctl restart pi-kiosk-admin.service

systemctl enable pi-tv-on.service pi-tv-off.service
systemctl enable pi-tv-on.timer pi-tv-off.timer
systemctl restart pi-tv-on.timer pi-tv-off.timer

systemctl enable pi-kiosk-health.timer
systemctl restart pi-kiosk-health.timer

systemctl enable pi-tv-on-early.service

echo "Install finished. If this was the first Labwc autostart change, reboot the Pi."
