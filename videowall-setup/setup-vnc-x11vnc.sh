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

read -r -s -p "Enter VNC password (exactly 8 chars): " VNCPASS
echo
if [[ ${#VNCPASS} -ne 8 ]]; then
  echo "ERROR: VNC password must be exactly 8 characters for best compatibility."
  exit 1
fi
printf '%s\n' "$VNCPASS" | x11vnc -storepasswd - /etc/x11vnc/passwd >/dev/null
chmod 600 /etc/x11vnc/passwd
unset VNCPASS

cat <<'EOF' > /etc/systemd/system/x11vnc.service
[Unit]
Description=x11vnc (macOS Screen Sharing compatible)
After=graphical.target
Wants=graphical.target

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc \
  -display :0 \
  -auth guess \
  -rfbport 5900 \
  -passwdfile /etc/x11vnc/passwd \
  -forever \
  -shared \
  -noxdamage \
  -repeat \
  -o /var/log/x11vnc.log
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable --now x11vnc

echo
echo "OK: x11vnc is running."
echo "Connect from macOS: Finder -> Go -> Connect to Server -> vnc://<pi-ip>"

