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

Installs systemd units, Labwc autostart snippet, Plymouth branded boot theme,
nightly kiosk restart cron, and ensures repo scripts are executable.
Re-run after every git pull.
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
    plymouth \
    || apt-get install -y python3-flask chromium wlr-randr v4l-utils plymouth
fi

chown -R "${PI_USER}:${PI_USER}" "$REPO"
find "${REPO}/scripts" -type f -name '*.sh' -exec chmod +x {} \;
chmod +x "${REPO}/install.sh" "${REPO}/update.sh" 2>/dev/null || true

for unit in "${REPO}/systemd"/*.service "${REPO}/systemd"/*.timer; do
  [[ -f "$unit" ]] || continue
  install -m 0644 "$unit" "/etc/systemd/system/$(basename "$unit")"
done

strip_pi_desktop_autostart_lines() {
  local in="$1"
  local out="$2"
  sed \
    -e '/wf-panel-pi/d' \
    -e '/pcmanfm-pi/d' \
    -e '/lxsession-xdg-autostart/d' \
    "$in" >"$out"
}

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
  # Kiosk: no Pi panel / file manager / XDG autostart until admin "Show Pi desktop".
  strip_pi_desktop_autostart_lines "$tmp" "${tmp}.strip"
  mv "${tmp}.strip" "$tmp"
  cat >>"$tmp" <<'LABEOF'

# BEGIN PI-KIOSK-DEPLOY
/home/pi/pi-kiosk/scripts/keep_awake.sh &
/home/pi/pi-kiosk/scripts/kiosk_wayland.sh &
# END PI-KIOSK-DEPLOY
LABEOF
  install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

merge_pi_user_labwc_autostart() {
  local f="${PI_HOME}/.config/labwc/autostart"
  [[ -f "$f" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  strip_pi_desktop_autostart_lines "$f" "$tmp"
  install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
  chown "${PI_USER}:${PI_USER}" "$f"
}

merge_labwc_autostart
merge_pi_user_labwc_autostart

merge_pi_boot_cmdline() {
  local f=""
  for cand in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
    [[ -f "$cand" ]] && f="$cand" && break
  done
  [[ -n "$f" ]] || return 0
  local line filtered=()
  line="$(tr -s '[:space:]' ' ' <"$f" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  read -r -a _toks <<<"$line"
  local t
  for t in "${_toks[@]}"; do
    [[ "$t" == "nosplash" ]] && continue
    filtered+=("$t")
  done
  line="${filtered[*]}"
  local tok
  for tok in splash quiet logo.nologo plymouth.ignore-serial-consoles; do
    if [[ " $line " != *" $tok "* ]]; then
      line="${line} ${tok}"
    fi
  done
  printf '%s\n' "$line" >"${f}.new"
  mv "${f}.new" "$f"
}

merge_pi_config_disable_firmware_splash() {
  local f=""
  for cand in /boot/firmware/config.txt /boot/config.txt; do
    [[ -f "$cand" ]] && f="$cand" && break
  done
  [[ -n "$f" ]] || return 0
  if grep -q '^[[:space:]]*disable_splash=' "$f"; then
    sed -i 's/^[[:space:]]*disable_splash=.*/disable_splash=1/' "$f"
  else
    printf '\n# pi-kiosk: suppress firmware rainbow splash\ndisable_splash=1\n' >>"$f"
  fi
}

install_plymouth_brand_theme() {
  local themed="/usr/share/plymouth/themes/pi-kiosk-brand"
  local src="${REPO}/plymouth/pi-kiosk-brand"
  local splash_src="${REPO}/assets/boot-splash-1080p.png"
  [[ -f "${src}/pi-kiosk-brand.script" ]] || return 0
  [[ -f "$splash_src" ]] || {
    echo "Skipping Plymouth theme: missing $splash_src" >&2
    return 0
  }
  if ! command -v plymouth-set-default-theme >/dev/null 2>&1; then
    echo "Skipping Plymouth theme: install plymouth (re-run without --no-apt)." >&2
    return 0
  fi
  install -d "$themed"
  install -m 0644 "${src}/pi-kiosk-brand.plymouth" "${src}/pi-kiosk-brand.script" "$themed/"
  install -m 0644 "$splash_src" "${themed}/splash.png"
  plymouth-set-default-theme -R pi-kiosk-brand
}

merge_pi_boot_cmdline
merge_pi_config_disable_firmware_splash
install_plymouth_brand_theme

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

echo "Install finished. Reboot the Pi to apply Plymouth, cmdline, and Labwc autostart changes."
