# Videowall setup (Deskflow KVM + macOS Screen Sharing VNC)

This folder contains **interactive setup scripts** for Raspberry Pi OS / Debian Trixie-based installs used in the videowall.

## What it sets up

- **Keyboard + mouse sharing (KVM)** via **Deskflow** (Barrier-compatible)
  - Server: `deskflow-server` on the chosen host (Pi 6 in your wall)
  - Clients: `deskflow-client` on the other hosts
  - Includes a fixed **2×5 videowall layout** config using hostnames:
    - Row 1: `pi-videowall-1`, `pi-videowall-3`, `pi-videowall-5`, `pi-videowall-7`, `pi-videowall-9`
    - Row 2: `pi-videowall-2`, `pi-videowall-4`, `pi-videowall-6`, `pi-videowall-8`, `pi-videowall-10`

- **Remote screen sharing from macOS Screen Sharing** using **x11vnc**
  - RealVNC is disabled to avoid protocol compatibility issues with macOS Screen Sharing.
  - `x11vnc` runs as a system service on port **5900** with classic VNC auth.

## Files

- `setup-vnc-x11vnc.sh`: installs + enables `x11vnc` service for macOS Screen Sharing.
- `setup-deskflow.sh`: installs + configures Deskflow as **server** or **client** (prompts).
- `deskflow-videowall.conf`: the videowall layout used by the Deskflow server.

## Usage

On each Pi:

```bash
cd ~/pi-kiosk/videowall-setup
chmod +x setup-vnc-x11vnc.sh setup-deskflow.sh
```

### VNC (macOS Screen Sharing)

Run:

```bash
./setup-vnc-x11vnc.sh
```

Then from macOS:

- Connect to `vnc://<pi-ip>`
- Use the password you set during the script

### Deskflow (KVM)

On the **server** (Pi 6 / `pi-videowall-6`):

```bash
./setup-deskflow.sh
```

Choose **server**, and it will install Deskflow, install the videowall layout config, and configure autostart.

On each **client**:

```bash
./setup-deskflow.sh
```

Choose **client** and enter the **server hostname** (e.g. `pi-videowall-6`) or server IP.

## Notes / constraints

- `x11vnc` requires an **X11** desktop session on `:0` to share. (This is what macOS Screen Sharing expects.)
- Classic VNC passwords are effectively **8 characters**. The VNC script enforces this to avoid client quirks.

