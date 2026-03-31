#!/bin/bash
set -euo pipefail

# Idempotent install/update for pi-kiosk. Must run as root.

PI_USER="pi"
PI_HOME="/home/pi"
REPO="${PI_HOME}/pi-kiosk"
URL_FILE="${PI_HOME}/kiosk_url.txt"

usage() {
  cat <<'U'
Usage: sudo /home/pi/pi-kiosk/install.sh [--url https://...] [--no-apt] [deskflow options]

  --url URL     Write /home/pi/kiosk_url.txt (required if that file has no URL yet)
  --no-apt      Skip apt-get install (faster repeat runs after git pull)

Installs systemd units, LXDE-pi (X11) autostart snippet, Plymouth branded boot theme,
nightly kiosk restart cron, Deskflow + x11vnc packages, and ensures repo scripts are executable.
Re-run after every git pull. Also selects the X11 desktop session via raspi-config when available.

  x11vnc: install.sh enables x11vnc.service when /etc/x11vnc/passwd.txt (preferred for macOS)
          or /etc/x11vnc/passwd (-rfbauth) exists. Unattended: export KIOSK_VNC_PASSWORD
          (exactly 8 chars) before sudo; install creates passwd.txt then unsets it. At least
          one apt run without --no-apt is needed so the x11vnc package is installed. See
          PI-KIOSK-AUTO-INSTALL-REFERENCE.md.

Deskflow autostart (optional; packages are always installed when apt runs):

  --deskflow-role server|client
                              Configure deskflow autostart for user pi.
  --deskflow-server-addr HOST Required when role=client: server hostname or IP.
  --deskflow-server-name NAME Optional when role=server: screen name (default: hostname).

Backward-compatible no-ops: --videowall, --enable-x11vnc
U
}

SKIP_APT=0
URL=""
DESKFLOW_ROLE=""
DESKFLOW_SERVER_ADDR=""
DESKFLOW_SERVER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --no-apt) SKIP_APT=1; shift ;;
    --url)
      URL="${2:-}"
      shift 2
      ;;
    --videowall)
      shift
      ;;
    --deskflow-role)
      DESKFLOW_ROLE="${2:-}"
      shift 2
      ;;
    --deskflow-server-addr)
      DESKFLOW_SERVER_ADDR="${2:-}"
      shift 2
      ;;
    --deskflow-server-name)
      DESKFLOW_SERVER_NAME="${2:-}"
      shift 2
      ;;
    --enable-x11vnc)
      shift
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
    x11-xserver-utils \
    v4l-utils \
    plymouth \
    || apt-get install -y python3-flask chromium x11-xserver-utils v4l-utils plymouth

  # Deskflow (KVM) and x11vnc (remote desktop / macOS Screen Sharing). May be absent on some
  # suites or architectures; do not fail the kiosk install if they are unavailable.
  apt-get install -y deskflow x11vnc || true
fi

chown -R "${PI_USER}:${PI_USER}" "$REPO"
find "${REPO}/scripts" -type f -name '*.sh' -exec chmod +x {} \;
chmod +x "${REPO}/install.sh" "${REPO}/update.sh" 2>/dev/null || true
chmod +x "${REPO}/kiosk_wayland.sh" "${REPO}/kiosk-start.sh" "${REPO}/kiosk-stop.sh" "${REPO}/keep_awake.sh" "${REPO}/tv_on.sh" 2>/dev/null || true
find "${REPO}/videowall-setup" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
find "${REPO}/videowall-setup" -type f -name '*.conf' -exec chmod 0644 {} \; 2>/dev/null || true

for unit in "${REPO}/systemd"/*.service "${REPO}/systemd"/*.timer; do
  [[ -f "$unit" ]] || continue
  install -m 0644 "$unit" "/etc/systemd/system/$(basename "$unit")"
done

strip_lxsession_desktop_lines() {
  local in="$1"
  local out="$2"
  sed \
    -e '/wf-panel-pi/d' \
    -e '/lwrespawn/d' \
    -e '/^[[:space:]]*@lxpanel-pi[[:space:]]*$/d' \
    -e '/^[[:space:]]*lxpanel-pi[[:space:]]*$/d' \
    -e '/^[[:space:]]*@lxpanel[[:space:]]/d' \
    -e '/^[[:space:]]*@pcmanfm-pi/d' \
    -e '/^[[:space:]]*pcmanfm-pi/d' \
    -e '/^[[:space:]]*@pcmanfm/d' \
    -e '/^[[:space:]]*@xscreensaver/d' \
    -e '/^[[:space:]]*xscreensaver/d' \
    -e '/pcmanfm-pi/d' \
    -e '/lxsession-xdg-autostart/d' \
    "$in" >"$out"
}

cleanup_labwc_pi_kiosk_block() {
  local f="/etc/xdg/labwc/autostart"
  [[ -f "$f" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { skip=0 }
    /^# BEGIN PI-KIOSK-DEPLOY$/ { skip=1; next }
    /^# END PI-KIOSK-DEPLOY$/ { skip=0; next }
    skip==0 { print }
  ' "$f" >"$tmp"
  install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

cleanup_user_labwc_pi_kiosk_block() {
  local f="${PI_HOME}/.config/labwc/autostart"
  [[ -f "$f" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { skip=0 }
    /^# BEGIN PI-KIOSK-DEPLOY$/ { skip=1; next }
    /^# END PI-KIOSK-DEPLOY$/ { skip=0; next }
    skip==0 { print }
  ' "$f" >"$tmp"
  install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
  chown "${PI_USER}:${PI_USER}" "$f"
}

merge_lxsession_autostart() {
  local f="/etc/xdg/lxsession/LXDE-pi/autostart"
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
    sed -e '\|/home/pi/Documents/pi-kiosk/keep_awake.sh|d' \
        -e '\|^/home/pi/kiosk_wayland\.sh|d' \
        -e '\|^/home/pi/pi-kiosk/scripts/kiosk_wayland\.sh|d' \
        -e '\|^/home/pi/pi-kiosk/scripts/kiosk\.sh|d' \
        -e '\|^/home/pi/pi-kiosk/scripts/keep_awake.sh|d' "$tmp" >"${tmp}.2"
    mv "${tmp}.2" "$tmp"
  else
    : >"$tmp"
  fi
  strip_lxsession_desktop_lines "$tmp" "${tmp}.strip"
  mv "${tmp}.strip" "$tmp"
  cat >>"$tmp" <<'LXEOF'

# BEGIN PI-KIOSK-DEPLOY
/home/pi/pi-kiosk/scripts/keep_awake.sh &
/home/pi/pi-kiosk/scripts/kiosk.sh &
# END PI-KIOSK-DEPLOY
LXEOF
  install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

cleanup_labwc_pi_kiosk_block
cleanup_user_labwc_pi_kiosk_block
merge_lxsession_autostart

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

configure_pi_session_x11() {
  if command -v raspi-config >/dev/null 2>&1; then
    if raspi-config nonint do_wayland W2 >/dev/null 2>&1; then
      echo "Configured desktop session: X11"
    else
      echo "Could not switch to X11 automatically via raspi-config." >&2
      echo "Run manually: sudo raspi-config (Advanced Options -> Wayland -> X11)" >&2
    fi
  else
    echo "raspi-config not found; cannot auto-switch to X11." >&2
    echo "Run manually in Raspberry Pi Configuration / raspi-config." >&2
  fi

  # LightDM may still default to Wayland (rpd-labwc); x11vnc needs a real X11 session on :0.
  local lightdm="/etc/lightdm/lightdm.conf"
  if [[ -f "$lightdm" ]] && grep -qE '^user-session=rpd-labwc$|^autologin-session=rpd-labwc$' "$lightdm" 2>/dev/null; then
    sed -i 's/^user-session=rpd-labwc$/user-session=rpd-x/' "$lightdm"
    sed -i 's/^autologin-session=rpd-labwc$/autologin-session=rpd-x/' "$lightdm"
    echo "LightDM: default session set to rpd-x (X11) for kiosk + x11vnc."
  fi
}

configure_pi_session_x11

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

systemctl enable pi-kiosk-boot-tv.service

configure_deskflow_and_vnc() {
  # Optional unattended VNC (plain passwd file — preferred for macOS Screen Sharing; see
  # PI-KIOSK-AUTO-INSTALL-REFERENCE.md). Clears KIOSK_VNC_PASSWORD from this shell after use.
  if [[ -n "${KIOSK_VNC_PASSWORD:-}" ]]; then
    if [[ ${#KIOSK_VNC_PASSWORD} -ne 8 ]]; then
      echo "install.sh: KIOSK_VNC_PASSWORD must be exactly 8 characters; not writing /etc/x11vnc/passwd.txt." >&2
    else
      install -d -m 0755 /etc/x11vnc
      printf '%s\n' "${KIOSK_VNC_PASSWORD}" > /etc/x11vnc/passwd.txt
      chown root:pi /etc/x11vnc/passwd.txt
      chmod 0640 /etc/x11vnc/passwd.txt
      echo "Created /etc/x11vnc/passwd.txt for x11vnc."
    fi
    unset KIOSK_VNC_PASSWORD
    export -n KIOSK_VNC_PASSWORD 2>/dev/null || true
  fi

  # Deskflow autostart for user pi (server/client). This is a desktop UX feature and
  # is separate from the kiosk LXDE autostart snippet.
  if [[ -n "$DESKFLOW_ROLE" ]]; then
    local role
    role="$(echo "$DESKFLOW_ROLE" | tr '[:upper:]' '[:lower:]' | xargs || true)"
    case "$role" in
      server)
        local server_name
        server_name="${DESKFLOW_SERVER_NAME:-$(hostname || true)}"
        install -d -m 0755 -o pi -g pi /home/pi/.config/deskflow
        install -m 0644 -o pi -g pi "${REPO}/videowall-setup/deskflow-videowall.conf" /home/pi/.config/deskflow/deskflow.conf

        install -d -m 0755 -o pi -g pi /home/pi/.config/autostart
        cat <<EOF >/home/pi/.config/autostart/org.deskflow.server.desktop
[Desktop Entry]
Type=Application
Version=1.0
Name=Deskflow Server
Comment=Deskflow server for videowall KVM
Exec=deskflow-server --no-daemon --restart --name ${server_name} --config /home/pi/.config/deskflow/deskflow.conf
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
        chown pi:pi /home/pi/.config/autostart/org.deskflow.server.desktop
        chmod 0644 /home/pi/.config/autostart/org.deskflow.server.desktop
        ;;
      client)
        if [[ -z "$DESKFLOW_SERVER_ADDR" ]]; then
          echo "install.sh: --deskflow-role client requires --deskflow-server-addr" >&2
          exit 2
        fi
        install -d -m 0755 -o pi -g pi /home/pi/.config/autostart
        cat <<EOF >/home/pi/.config/autostart/org.deskflow.client.desktop
[Desktop Entry]
Type=Application
Version=1.0
Name=Deskflow Client
Comment=Deskflow client for videowall KVM
Exec=deskflow-client --no-daemon --restart ${DESKFLOW_SERVER_ADDR}
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
        chown pi:pi /home/pi/.config/autostart/org.deskflow.client.desktop
        chmod 0644 /home/pi/.config/autostart/org.deskflow.client.desktop
        ;;
      *)
        echo "install.sh: --deskflow-role must be server or client" >&2
        exit 2
        ;;
    esac
  fi

  # x11vnc: working pattern from PI-KIOSK-AUTO-INSTALL-REFERENCE.md — run as pi with
  # XAUTHORITY; passwd.txt + -passwdfile read:… for macOS; else -rfbauth for storepasswd output.
  if [[ -f /etc/x11vnc/passwd.txt ]] || [[ -f /etc/x11vnc/passwd ]]; then
    # Disable RealVNC service-mode to avoid conflicts and macOS incompatibility.
    systemctl stop vncserver-x11-serviced 2>/dev/null || true
    systemctl disable vncserver-x11-serviced 2>/dev/null || true

    install -d -m 0755 /etc/x11vnc
    install -d -m 0755 -o pi -g pi "${REPO}/logs"
    if [[ -f /etc/x11vnc/passwd.txt ]]; then
      chown root:pi /etc/x11vnc/passwd.txt 2>/dev/null || true
      chmod 0640 /etc/x11vnc/passwd.txt 2>/dev/null || true
    fi
    if [[ -f /etc/x11vnc/passwd ]]; then
      chown root:pi /etc/x11vnc/passwd 2>/dev/null || true
      chmod 0640 /etc/x11vnc/passwd 2>/dev/null || true
    fi

    if [[ -f /etc/x11vnc/passwd.txt ]]; then
      cat <<EOF >/etc/systemd/system/x11vnc.service
[Unit]
Description=x11vnc (macOS Screen Sharing compatible)
After=graphical.target
Wants=graphical.target

[Service]
Type=simple
User=pi
Group=pi
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
ExecStart=/usr/bin/x11vnc -display :0 -rfbport 5900 -rfbversion 3.8 -passwdfile read:/etc/x11vnc/passwd.txt -desktop RaspberryPi -forever -shared -noxdamage -repeat -cursor most -o ${REPO}/logs/x11vnc.log
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical.target
EOF
    else
      cat <<EOF >/etc/systemd/system/x11vnc.service
[Unit]
Description=x11vnc (macOS Screen Sharing compatible)
After=graphical.target
Wants=graphical.target

[Service]
Type=simple
User=pi
Group=pi
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
ExecStart=/usr/bin/x11vnc -display :0 -rfbport 5900 -rfbversion 3.8 -rfbauth /etc/x11vnc/passwd -desktop RaspberryPi -forever -shared -noxdamage -repeat -cursor most -o ${REPO}/logs/x11vnc.log
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable --now x11vnc.service
  else
    if ! command -v x11vnc >/dev/null 2>&1; then
      if [[ "$SKIP_APT" -eq 1 ]]; then
        echo "[pi-kiosk] x11vnc is not installed: this run used --no-apt, so apt (including deskflow/x11vnc) was skipped. Run install.sh once without --no-apt, or: sudo apt-get install -y x11vnc" >&2
      else
        echo "[pi-kiosk] x11vnc is not installed (apt install step may have failed, or the package is unavailable)." >&2
      fi
    else
      echo "[pi-kiosk] x11vnc is installed but no secret file — add /etc/x11vnc/passwd.txt (plain) or /etc/x11vnc/passwd (x11vnc -storepasswd). Use KIOSK_VNC_PASSWORD on install, videowall-setup/setup-vnc-x11vnc.sh, or PI-KIOSK-AUTO-INSTALL-REFERENCE.md; then: sudo ${REPO}/install.sh --no-apt" >&2
    fi
  fi
}

configure_deskflow_and_vnc

report_display_session_status() {
  echo "Display session status:"

  if command -v raspi-config >/dev/null 2>&1; then
    local wl_mode
    wl_mode="$(raspi-config nonint get_wayland 2>/dev/null || true)"
    case "$wl_mode" in
      W2) echo "  Configured desktop backend: X11" ;;
      W1) echo "  Configured desktop backend: Wayland" ;;
      *)  echo "  Configured desktop backend: unknown (raspi-config code: ${wl_mode:-n/a})" ;;
    esac
  else
    echo "  Configured desktop backend: unknown (raspi-config not found)"
  fi

  local session_id active_type
  session_id="$(loginctl list-sessions --no-legend 2>/dev/null | awk '$3=="pi"{print $1; exit}' || true)"
  if [[ -n "$session_id" ]]; then
    active_type="$(loginctl show-session "$session_id" -p Type --value 2>/dev/null || true)"
    if [[ -n "$active_type" ]]; then
      echo "  Active session type now: ${active_type}"
    else
      echo "  Active session type now: unknown"
    fi
  else
    echo "  Active session type now: not detected (no logged-in pi graphical session)"
  fi
}

report_display_session_status

echo "Install finished. Reboot the Pi to apply Plymouth, cmdline, and LXDE-pi autostart changes."
