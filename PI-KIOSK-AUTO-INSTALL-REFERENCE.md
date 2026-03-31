# pi-kiosk auto-install reference (field notes)

Use this with your own unattended installer (Ansible, cloud-init, first-boot script, etc.). It summarizes what matters for **x11-version** on Raspberry Pi OS with **Chromium kiosk**, **Flask admin :8088**, and **x11vnc** for **macOS Screen Sharing**.

Upstream repo: [Aaron-Gardien/pi-kiosk — `x11-version`](https://github.com/Aaron-Gardien/pi-kiosk/tree/x11-version).

---

## 1. Clone and install (baseline)

```bash
REPO_URL='https://github.com/aaron-gardien/pi-kiosk.git'
REPO_DIR='/home/pi/pi-kiosk'
KIOSK_URL='https://example.com/'   # your real kiosk URL — no placeholder in production

sudo -u pi git clone --branch x11-version "$REPO_URL" "$REPO_DIR"
chmod +x "$REPO_DIR/install.sh" "$REPO_DIR/update.sh" "$REPO_DIR/scripts/"*.sh
# First install: run apt (do not use --no-apt) so chromium, x11vnc, deskflow get pulled in.
sudo "$REPO_DIR/install.sh" --url "$KIOSK_URL"
```

**Updates** (after `git pull` on `x11-version`):

```bash
sudo "$REPO_DIR/install.sh" --no-apt
```

**Why `--no-apt` sometimes breaks things:** `install.sh --no-apt` skips `apt-get install`, so **`x11vnc` may never get installed** if the first full install was skipped on that image. Ensure at least one run **without** `--no-apt**, or explicitly `apt-get install -y x11vnc` before enabling the VNC unit.

---

## 2. Desktop session: must be X11 for kiosk + x11vnc

The **x11-version** branch targets **X11** (classic Raspberry Pi Desktop on X), not **Wayland / Labwc**.

**Symptom if wrong session:** LightDM uses `user-session=rpd-labwc` / `autologin-session=rpd-labwc` → session is **Wayland** with **rootless Xwayland** on `:0` → **x11vnc** can fail (`X_GetImage` / `BadMatch`) or auth/X authority issues.

**Fix (LightDM):** force **X11** session:

```bash
sudo sed -i 's/^user-session=rpd-labwc$/user-session=rpd-x/' /etc/lightdm/lightdm.conf
sudo sed -i 's/^autologin-session=rpd-labwc$/autologin-session=rpd-x/' /etc/lightdm/lightdm.conf
```

**Backup first:**

```bash
sudo cp -a /etc/lightdm/lightdm.conf "/etc/lightdm/lightdm.conf.bak-$(date +%Y%m%d%H%M)"
```

`install.sh` on current **pi-kiosk** `x11-version` also tries `raspi-config nonint do_wayland W2` and, when needed, applies the `rpd-labwc` → `rpd-x` LightDM edits above.

**Reboot** after changing the default session so `:0` is a real X11 desktop suitable for **x11vnc** and the LXDE-pi autostart snippets.

---

## 3. x11vnc: systemd unit (working pattern)

Run **x11vnc as user `pi`** with **`DISPLAY=:0`** and **`XAUTHORITY=/home/pi/.Xauthority`**. Running as **root** with **`-auth guess`** often fails under systemd (`xauth: unable to generate an authority file name`).

**Log file:** must be writable by `pi` — use e.g. `/home/pi/pi-kiosk/logs/x11vnc.log`, **not** `/var/log/x11vnc.log`.

**IPv6:** if you see `listen6: bind: Address already in use`, IPv6 may be skipped; **IPv4 :5900** is usually enough for LAN `vnc://` clients.

### 3.1 Password file — critical for macOS Screen Sharing

| Method | Flag | When to use |
|--------|------|-------------|
| **Plain first line + `read:`** | `-passwdfile read:/etc/x11vnc/passwd.txt` | **Preferred for macOS** — file is **reread on each new client** (Screen Sharing often opens **multiple** RFB connections; fixed single-file auth can confuse follow-up handshakes). |
| **Obscured file from `x11vnc -storepasswd`** | `-rfbauth /etc/x11vnc/passwd` | Valid; use **`-rfbauth`**, not `-passwdfile`, for this binary format. |
| **Wrong** | `-passwdfile` pointing at `storepasswd` output | **Broken:** `-passwdfile` treats the first line as **LibVNC text** format, not the 8-byte obscured blob — clients get **password check failed**. |

**Create `passwd.txt` (exactly 8 characters recommended for widest client compatibility):**

```bash
sudo install -d -m 0755 /etc/x11vnc
printf '%s\n' 'Your8Ch!' | sudo tee /etc/x11vnc/passwd.txt >/dev/null
sudo chown root:pi /etc/x11vnc/passwd.txt
sudo chmod 640 /etc/x11vnc/passwd.txt
```

**Regenerate obscured file (if you use `-rfbauth` instead):**

```bash
sudo x11vnc -storepasswd 'Your8Ch!' /etc/x11vnc/passwd
sudo chown root:pi /etc/x11vnc/passwd
sudo chmod 640 /etc/x11vnc/passwd
```

Use **argument form** `-storepasswd PASS FILE` (avoid piping from `printf` unless you are sure the tool strips newlines the way you expect).

### 3.2 Example `/etc/systemd/system/x11vnc.service`

```ini
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
ExecStart=/usr/bin/x11vnc \
  -display :0 \
  -rfbport 5900 \
  -rfbversion 3.8 \
  -passwdfile read:/etc/x11vnc/passwd.txt \
  -desktop RaspberryPi \
  -forever \
  -shared \
  -noxdamage \
  -repeat \
  -cursor most \
  -o /home/pi/pi-kiosk/logs/x11vnc.log
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical.target
```

Enable:

```bash
sudo install -d -m 0755 -o pi -g pi /home/pi/pi-kiosk/logs
sudo systemctl daemon-reload
sudo systemctl enable --now x11vnc.service
```

### 3.3 RealVNC conflict

`install.sh` / `videowall-setup/setup-vnc-x11vnc.sh` disable **`vncserver-x11-serviced`** (RealVNC) — it clashes with **x11vnc** and macOS clients.

### 3.4 macOS client tips

- Connect with **Finder → Go → Connect to Server → `vnc://<pi-ip>`** (or hostname).
- If the password **used to** fail after a partial connection: **delete saved VNC passwords** for that host in **Keychain Access** (search `vnc` / host / IP) so the Mac does not submit an old secret.
- Logs: `journalctl -u x11vnc.service -n 50` and `/home/pi/pi-kiosk/logs/x11vnc.log`.

---

## 4. Piper `install.sh` integration (VNC enable rule)

**Implemented in-tree** in **`install.sh`** (summary):

- Enables **x11vnc** when **`/etc/x11vnc/passwd.txt`** or **`/etc/x11vnc/passwd`** exists.
- If **`passwd.txt`** exists → **`-passwdfile read:/etc/x11vnc/passwd.txt`** (preferred for macOS).
- Else **`passwd`** → **`-rfbauth /etc/x11vnc/passwd`**.
- Service: **`User=pi`**, **`Environment=XAUTHORITY=/home/pi/.Xauthority`**, log **`/home/pi/pi-kiosk/logs/x11vnc.log`**, flags per §3.2.
- **`KIOSK_VNC_PASSWORD`** (exactly 8 characters) before **`sudo install.sh`** creates **`passwd.txt`** and unsets the variable.
- LightDM **`rpd-labwc` → `rpd-x`** is applied when those lines exist in **`/etc/lightdm/lightdm.conf`**.
- Helper **`videowall-setup/setup-vnc-x11vnc.sh`** writes **`passwd.txt`** and runs **`install.sh --no-apt`** when **`kiosk_url.txt`** exists.

Unattended examples:

```bash
sudo KIOSK_VNC_PASSWORD='Your8Ch!' bash /home/pi/pi-kiosk/videowall-setup/setup-vnc-x11vnc.sh
# or in one step with the main installer (creates passwd.txt, then enables unit):
sudo KIOSK_VNC_PASSWORD='Your8Ch!' /home/pi/pi-kiosk/install.sh --url 'https://example.com/'
```

Or create **`passwd.txt`** yourself (§3.1), then **`sudo install.sh --no-apt`** to refresh the unit.

---

## 5. Suggested order of operations (auto-install checklist)

1. Image with desktop, user **`pi`**, network up.
2. **`git clone` `x11-version`** → `/home/pi/pi-kiosk`.
3. **`sudo ./install.sh --url 'https://…'`** (full apt run once).
4. Ensure LightDM **`rpd-x`** (X11) — see §2; **reboot** if you changed session.
5. Create **`/etc/x11vnc/passwd.txt`** (or run **`setup-vnc-x11vnc.sh`**).
6. **`sudo ./install.sh --no-apt`** (syncs systemd unit for x11vnc if passwd file exists).
7. **`systemctl is-active x11vnc.service`** and **`ss -tlnp | grep 5900`**.
8. From Mac: **`vnc://<pi-ip>`**, use the **8-character** password; clear Keychain if needed.

---

## 6. Quick diagnostics

```bash
loginctl show-session "$(loginctl | awk '/seat0/ {print \$1; exit}')" -p Type -p Display
systemctl status x11vnc.service --no-pager
ss -tlnp | grep 5900
sudo tail -50 /home/pi/pi-kiosk/logs/x11vnc.log
grep -E '^(user-session|autologin-session)=' /etc/lightdm/lightdm.conf
```

---

*Generated from deployment notes: Wayland vs X11, x11vnc auth modes, macOS multi-connection behaviour, and LightDM `rpd-x` requirement.*
