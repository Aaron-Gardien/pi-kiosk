#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYOUT_SRC="${ROOT_DIR}/deskflow-videowall.conf"

echo "== Deskflow (Barrier-compatible) setup =="
echo

if [[ ! -f "$LAYOUT_SRC" ]]; then
  echo "ERROR: Missing layout file: $LAYOUT_SRC"
  exit 1
fi

apt-get update
apt-get install -y deskflow

read -r -p "Configure this host as (server/client): " ROLE
ROLE="$(echo "$ROLE" | tr '[:upper:]' '[:lower:]' | xargs)"

case "$ROLE" in
  server)
    read -r -p "Server screen name (hostname) [$(hostname)]: " SERVER_NAME
    SERVER_NAME="${SERVER_NAME:-$(hostname)}"

    install -d -m 0755 -o pi -g pi /home/pi/.config/deskflow
    install -m 0644 -o pi -g pi "$LAYOUT_SRC" /home/pi/.config/deskflow/deskflow.conf

    # Start on GUI login (autostart) so it's available during normal desktop use.
    install -d -m 0755 -o pi -g pi /home/pi/.config/autostart
    cat <<EOF > /home/pi/.config/autostart/org.deskflow.server.desktop
[Desktop Entry]
Type=Application
Version=1.0
Name=Deskflow Server
Comment=Deskflow server for videowall KVM
Exec=deskflow-server --no-daemon --restart --name ${SERVER_NAME} --config /home/pi/.config/deskflow/deskflow.conf
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    chown pi:pi /home/pi/.config/autostart/org.deskflow.server.desktop
    chmod 0644 /home/pi/.config/autostart/org.deskflow.server.desktop

    echo
    echo "OK: Deskflow SERVER configured."
    echo "Config: /home/pi/.config/deskflow/deskflow.conf"
    echo "Autostart: /home/pi/.config/autostart/org.deskflow.server.desktop"
    echo "Tip: clients should connect to ${SERVER_NAME} (default port 24800)."
    ;;

  client)
    read -r -p "Deskflow server hostname or IP: " SERVER_ADDR
    if [[ -z "$SERVER_ADDR" ]]; then
      echo "ERROR: server address is required."
      exit 1
    fi

    install -d -m 0755 -o pi -g pi /home/pi/.config/autostart
    cat <<EOF > /home/pi/.config/autostart/org.deskflow.client.desktop
[Desktop Entry]
Type=Application
Version=1.0
Name=Deskflow Client
Comment=Deskflow client for videowall KVM
Exec=deskflow-client --no-daemon --restart ${SERVER_ADDR}
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    chown pi:pi /home/pi/.config/autostart/org.deskflow.client.desktop
    chmod 0644 /home/pi/.config/autostart/org.deskflow.client.desktop

    echo
    echo "OK: Deskflow CLIENT configured."
    echo "Autostart: /home/pi/.config/autostart/org.deskflow.client.desktop"
    ;;

  *)
    echo "ERROR: role must be 'server' or 'client'."
    exit 1
    ;;
esac

