#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

echo "== x11vnc setup for macOS Screen Sharing =="
echo

apt-get update
apt-get install -y x11vnc

# Disable RealVNC service-mode to avoid conflicts and macOS incompatibility.
systemctl stop vncserver-x11-serviced 2>/dev/null || true
systemctl disable vncserver-x11-serviced 2>/dev/null || true

install -d -m 0755 /etc/x11vnc

# Plain-text first line + "read:" is preferred for macOS (multi-connection handshakes).
# Non-interactive: sudo -E KIOSK_VNC_PASSWORD='your8chr' ./setup-vnc-x11vnc.sh
if [[ -n "${KIOSK_VNC_PASSWORD:-}" ]]; then
  VNCPASS="$KIOSK_VNC_PASSWORD"
  unset KIOSK_VNC_PASSWORD
elif [[ -t 0 ]]; then
  read -r -s -p "Enter VNC password (exactly 8 chars): " VNCPASS
  echo
else
  echo "ERROR: No TTY for password prompt. Set KIOSK_VNC_PASSWORD to exactly 8 characters, e.g.:" >&2
  echo "  sudo -E KIOSK_VNC_PASSWORD='your8chr' $0" >&2
  exit 1
fi

if [[ ${#VNCPASS} -ne 8 ]]; then
  unset VNCPASS 2>/dev/null || true
  echo "ERROR: VNC password must be exactly 8 characters for best compatibility." >&2
  exit 1
fi

printf '%s\n' "$VNCPASS" > /etc/x11vnc/passwd.txt
unset VNCPASS
chown root:pi /etc/x11vnc/passwd.txt
chmod 0640 /etc/x11vnc/passwd.txt

if [[ -x /home/pi/pi-kiosk/install.sh ]] && [[ -f /home/pi/kiosk_url.txt ]]; then
  echo "Syncing x11vnc systemd unit from pi-kiosk install.sh..."
  /home/pi/pi-kiosk/install.sh --no-apt
else
  echo "After kiosk URL is set: sudo /home/pi/pi-kiosk/install.sh --no-apt to install the x11vnc unit."
fi

echo
echo "OK: password file created. x11vnc should be managed by install.sh (user pi, repo logs)."
echo "Connect from macOS: Finder -> Go -> Connect to Server -> vnc://<pi-ip>"
