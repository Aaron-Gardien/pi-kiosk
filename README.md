# pi-kiosk

X11 kiosk (Chromium + Raspberry Pi OS desktop / LXDE-pi session) with a small Flask **admin UI** (port **8088**), HDMI-CEC TV on/off, systemd timers, and optional git-based updates.

## What gets installed

- **Kiosk**: LXDE-pi autostart (`/etc/xdg/lxsession/LXDE-pi/autostart`) runs `scripts/keep_awake.sh` and `scripts/kiosk.sh` (Chromium kiosk → local `loading.html` then your URL). Panel and desktop file manager are stripped from that file until you use admin **Show Pi desktop UI**.
- **URL**: First non-comment line in `/home/pi/kiosk_url.txt` (not stored in git). Set with `install.sh --url` or the admin UI.
- **Admin**: `pi-kiosk-admin.service` runs `admin_server.py` as root (needed for systemd timer edits and `runuser`).
- **TV**: `pi-tv-on.service` / `pi-tv-off.service` run `scripts/tv_on_restart_kiosk.sh` (CEC wake, switch to **HDMI 1** via active-source `1.0.0.0`, then restart Chromium) and `scripts/tv_off.sh`. `pi-tv-on-early.service` still runs `tv_on.sh` only (before the display manager). `pi-kiosk-boot-tv.service` repeats TV-on + kiosk refresh after graphical login. Override CEC device or physical address with `KIOSK_CEC_DEVICE` / `KIOSK_CEC_ACTIVE_PHYS` in the environment if needed. Default timers: on **07:30**, off **18:00** (change via admin or edit unit files and re-run install).
- **Health**: `pi-kiosk-health.timer` runs daily; log under `logs/health_check.log`.
- **Nightly kiosk restart**: `/etc/cron.d/pi-kiosk-restart` at **03:00** (no TV power).
- **Deskflow + x11vnc**: On every run that performs `apt` updates, `install.sh` tries to install **deskflow** and **x11vnc** (skipped if unavailable on your suite; core kiosk still installs). Deskflow **autostart** is optional: pass `--deskflow-role server` or `client` plus `--deskflow-server-addr` when `client`. **x11vnc** is enabled as a systemd service when `/etc/x11vnc/passwd` exists (create it with `videowall-setup/setup-vnc-x11vnc.sh`, then re-run install with `--no-apt`).

## One-time setup (10+ Pis)

1. Create a **private** Git repository (GitHub/GitLab/etc.) and push this tree.
2. On each Pi, use the same **deploy key** or **SSH key** with pull access, or HTTPS with a credential helper.
3. On a fresh Pi OS (user `pi`, desktop environment installed):

   ```bash
   cd /home/pi
   git clone https://github.com/aaron-gardien/pi-kiosk.git
   cd pi-kiosk
   chmod +x install.sh
   sudo ./install.sh --url "https://www.google.com/"
   sudo reboot
   ```

   `install.sh` selects the **X11** desktop session via `raspi-config` when available.

4. After reboot, open the admin UI from another machine: `http://<pi-ip>:8088`.

## Updating after you change the repo

On each Pi (or via Ansible/SSH loop):

```bash
/home/pi/pi-kiosk/update.sh
```

That runs `git pull --ff-only` and `sudo ./install.sh --no-apt` so systemd units and autostart stay in sync with the repo.

## Optional: automatic daily updates

1. Install sudoers so user `pi` can re-run the installer without a password:

   ```
   sudo visudo -f /etc/sudoers.d/pi-kiosk-update
   ```

   Add:

   ```
   pi ALL=(ALL) NOPASSWD: /home/pi/pi-kiosk/install.sh
   ```

2. Enable the timer (not enabled by default):

   ```bash
   sudo systemctl enable --now pi-kiosk-update.timer
   ```

The service runs `scripts/git_update_install.sh` as `pi` (git pull + `sudo install.sh --no-apt`).

## Migrating from `/home/pi/Documents/pi-kiosk` or Wayland / Labwc

Run `sudo ./install.sh --no-apt` after cloning to `/home/pi/pi-kiosk`. The installer removes old kiosk lines (including Labwc and legacy paths), clears any **pi-kiosk** block from Labwc autostart if present, and inserts the managed block into the LXDE-pi autostart file. Copy any existing `/home/pi/kiosk_url.txt` or pass `--url`.

If your image uses a nonstandard LXDE session name, adjust the path in `install.sh` (`merge_lxsession_autostart`) to match `/etc/xdg/lxsession/<profile>/autostart`.

## Layout

| Path | Role |
|------|------|
| `admin_server.py` | Flask Kiosk Admin |
| `loading.html` | Bootstraps Chromium then redirects to kiosk URL |
| `scripts/` | Kiosk, TV, health, update helpers |
| `systemd/` | Unit files copied to `/etc/systemd/system` |
| `install.sh` | Idempotent install/update (run as root) |
| `update.sh` | `git pull` + install for interactive use |
| `legacy/install_kiosk_x11.sh` | Old X11/startx installer (reference only) |

## Security

The admin service listens on all interfaces by default. Restrict with a firewall, VPN, or bind to localhost and use SSH port forwarding; change `KIOSK_ADMIN_HOST` in `systemd/pi-kiosk-admin.service` if needed.

## Bulk update (example)

From your workstation, if SSH keys reach all Pis:

```bash
for h in pi@kiosk1 pi@kiosk2; do
  ssh "$h" "/home/pi/pi-kiosk/update.sh"
done
```
