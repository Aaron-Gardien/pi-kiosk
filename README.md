# pi-kiosk

Wayland kiosk (Chromium + Labwc) for Raspberry Pi with a small Flask **admin UI** (port **8088**), HDMI-CEC TV on/off, systemd timers, and optional git-based updates.

## What gets installed

- **Kiosk**: Labwc autostart runs `scripts/keep_awake.sh` and `scripts/kiosk_wayland.sh` (Chromium kiosk → local `loading.html` then your URL).
- **URL**: First non-comment line in `/home/pi/kiosk_url.txt` (not stored in git). Set with `install.sh --url` or the admin UI.
- **Admin**: `pi-kiosk-admin.service` runs `admin_server.py` as root (needed for systemd timer edits and `runuser`).
- **TV**: `pi-tv-on.service` / `pi-tv-off.service` call `scripts/tv_on.sh` and `scripts/tv_off.sh` (adjust CEC device in those scripts if needed). Default timers: on **07:30**, off **18:00** (change via admin or edit unit files and re-run install).
- **Health**: `pi-kiosk-health.timer` runs daily; log under `logs/health_check.log`.
- **Nightly kiosk restart**: `/etc/cron.d/pi-kiosk-restart` at **03:00** (no TV power).

## One-time setup (10+ Pis)

1. Create a **private** Git repository (GitHub/GitLab/etc.) and push this tree.
2. On each Pi, use the same **deploy key** or **SSH key** with pull access, or HTTPS with a credential helper.
3. On a fresh Pi OS (user `pi`, Wayland desktop as shipped):

   ```bash
   cd /home/pi
   git clone git@github.com:aaron-gardien/pi-kiosk.git pi-kiosk
   cd pi-kiosk
   sudo ./install.sh --url "https://www.google.com/"
   sudo reboot
   ```

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

## Migrating from `/home/pi/Documents/pi-kiosk`

Run `sudo ./install.sh --no-apt` after cloning to `/home/pi/pi-kiosk`. The installer removes old Labwc lines that pointed at `Documents/pi-kiosk` or `/home/pi/kiosk_wayland.sh` and inserts the managed block. Copy any existing `/home/pi/kiosk_url.txt` or pass `--url`.

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

