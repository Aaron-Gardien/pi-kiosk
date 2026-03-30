from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

from flask import Flask, Response, jsonify, redirect, render_template_string, request, url_for

PROJECT_DIR = Path(__file__).resolve().parent
SCRIPTS_DIR = PROJECT_DIR / "scripts"
KIOSK_URL_FILE = Path("/home/pi/kiosk_url.txt")
KIOSK_WAYLAND_SH = str(SCRIPTS_DIR / "kiosk_wayland.sh")
KIOSK_STOP_SH = str(SCRIPTS_DIR / "kiosk-stop.sh")
SHOW_DESKTOP_SH = str(SCRIPTS_DIR / "show_desktop.sh")
HEALTH_CHECK_SH = str(SCRIPTS_DIR / "health_check.sh")
TV_ON_TIMER = "pi-tv-on.timer"
TV_OFF_TIMER = "pi-tv-off.timer"

PI_UID = "1000"
PI_USER = "pi"
PI_HOME = "/home/pi"
PI_RUNTIME_DIR = f"/run/user/{PI_UID}"
PI_WAYLAND_DISPLAY = "wayland-0"
PI_X11_DISPLAY = ":0"
PI_XAUTHORITY = f"{PI_HOME}/.Xauthority"

HTML = """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Kiosk Admin</title>
    <style>
      :root { color-scheme: light; }
      body { font-family: system-ui, -apple-system, Segoe UI, sans-serif; margin: 0; background: #0b0c10; color: #e8e8e8; }
      .wrap { max-width: 1100px; margin: 0 auto; padding: 24px 18px 48px; }
      h1 { font-size: 22px; margin: 0 0 14px; }
      .topbar { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 14px; flex-wrap: wrap; }
      .tabs { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 14px; }
      .tab-btn { margin: 0; padding: 9px 12px; border-radius: 10px; border: 1px solid #2e6f66; background: #103934; color: #d7fff8; cursor: pointer; }
      .tab-btn.active { background: #1f8f82; color: #041916; border-color: #5be2d0; }
      .panel { display: none; }
      .panel.active { display: block; }
      .grid { display: grid; grid-template-columns: 1fr; gap: 14px; }
      @media (min-width: 980px) { .grid { grid-template-columns: 1fr 1fr; } }
      .card { background: #11131a; border: 1px solid #262a36; border-radius: 12px; padding: 16px; min-width: 0; }
      .card h2 { font-size: 16px; margin: 0 0 10px; }
      label { display: block; font-size: 12px; opacity: 0.85; margin: 8px 0 6px; }
      input { width: 100%; box-sizing: border-box; padding: 10px 12px; border-radius: 10px; border: 1px solid #2d3342; background: #0b0c10; color: #e8e8e8; }
      .row { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
      .row > * { min-width: 0; }
      button { margin-top: 12px; width: 100%; box-sizing: border-box; padding: 10px 12px; border-radius: 10px; border: 1px solid #394055; background: #1a2133; color: #e8e8e8; cursor: pointer; }
      button:hover { background: #222b42; }
      .meta { font-size: 12px; opacity: 0.8; line-height: 1.4; }
      .ok { color: #7CFC9A; }
      .err { color: #ff6b6b; }
      pre { white-space: pre-wrap; word-break: break-word; background: #0b0c10; border: 1px solid #2d3342; border-radius: 10px; padding: 10px; }
      a { color: #9bbcff; }
      @media (max-width: 760px) {
        .row { grid-template-columns: 1fr; }
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="topbar">
        <h1>Kiosk Admin</h1>
        <div class="meta">Timezone: <code>{{ tz }}</code></div>
      </div>
      {% if flash %}
        <div class="card">
          <div class="{{ 'ok' if flash.ok else 'err' }}">{{ flash.message }}</div>
        </div>
      {% endif %}
      <div class="tabs">
        <button class="tab-btn active" data-tab="kiosk">Kiosk Control</button>
        <button class="tab-btn" data-tab="schedules">Schedules</button>
        <button class="tab-btn" data-tab="maintenance">Maintenance and Logs</button>
      </div>

      <section id="tab-kiosk" class="panel active">
        <div class="grid">
          <div class="card">
            <h2>Kiosk URL</h2>
            <div class="meta">Current URL: <code>{{ current_url or '(not set)' }}</code></div>
            <form method="post" action="{{ url_for('set_url') }}">
              <label for="url">New URL</label>
              <input id="url" name="url" placeholder="https://…" required />
              <button type="submit">Save URL</button>
            </form>
          </div>
          <div class="card">
            <h2>Kiosk Actions</h2>
            <form method="post" action="{{ url_for('restart_kiosk') }}">
              <button type="submit">Restart kiosk</button>
            </form>
            <div class="row" style="margin-top: 10px;">
              <form method="post" action="{{ url_for('kiosk_start') }}">
                <button type="submit">Kiosk start</button>
              </form>
              <form method="post" action="{{ url_for('kiosk_stop') }}">
                <button type="submit">Kiosk stop</button>
              </form>
            </div>
            <div class="row" style="margin-top: 10px;">
              <form method="post" action="{{ url_for('tv_on') }}">
                <button type="submit">TV ON</button>
              </form>
              <form method="post" action="{{ url_for('tv_off') }}">
                <button type="submit">TV OFF</button>
              </form>
            </div>
          </div>
        </div>
      </section>

      <section id="tab-schedules" class="panel">
        <div class="grid">
          <div class="card">
            <h2>TV Schedule</h2>
            <div class="meta">Timers: <code>{{ tv_on_timer }}</code> / <code>{{ tv_off_timer }}</code></div>
            <div class="meta">Current local time: <code id="local-time">{{ local_time }}</code></div>
            <form method="post" action="{{ url_for('set_schedule') }}">
              <div class="row">
                <div>
                  <label for="on_time">TV ON (HH:MM)</label>
                  <input id="on_time" name="on_time" value="{{ on_time }}" required pattern="^([01]\\d|2[0-3]):[0-5]\\d$" />
                </div>
                <div>
                  <label for="off_time">TV OFF (HH:MM)</label>
                  <input id="off_time" name="off_time" value="{{ off_time }}" required pattern="^([01]\\d|2[0-3]):[0-5]\\d$" />
                </div>
              </div>
              <button type="submit">Save schedule</button>
            </form>
          </div>
          <div class="card">
            <h2>TV Controls</h2>
            <div class="row">
              <form method="post" action="{{ url_for('tv_on') }}">
                <button type="submit">TV ON</button>
              </form>
              <form method="post" action="{{ url_for('tv_off') }}">
                <button type="submit">TV OFF</button>
              </form>
            </div>
          </div>
        </div>
      </section>

      <section id="tab-maintenance" class="panel">
        <div class="grid">
          <div class="card">
            <h2>Maintenance</h2>
            <form method="post" action="{{ url_for('show_desktop') }}">
              <button type="submit">Show Pi desktop UI</button>
            </form>
            <form method="post" action="{{ url_for('reboot') }}">
              <button type="submit">Reboot</button>
            </form>
            <p class="meta" style="margin-top: 10px;">
              <a href="{{ url_for('health') }}">Open health report</a>
            </p>
          </div>
          <div class="card">
            <h2>Logs / Timers</h2>
            <pre>{{ timers_text }}</pre>
          </div>
        </div>
      </section>
    </div>
    <script>
      const tabButtons = document.querySelectorAll('.tab-btn');
      const panels = document.querySelectorAll('.panel');
      tabButtons.forEach(btn => {
        btn.addEventListener('click', () => {
          const tab = btn.getAttribute('data-tab');
          tabButtons.forEach(b => b.classList.remove('active'));
          panels.forEach(p => p.classList.remove('active'));
          btn.classList.add('active');
          document.getElementById(`tab-${tab}`).classList.add('active');
        });
      });

      async function refreshLocalTime() {
        const el = document.getElementById('local-time');
        if (!el) return;
        try {
          const r = await fetch('/local-time', { cache: 'no-store' });
          if (!r.ok) return;
          const data = await r.json();
          if (data && data.local_time) el.textContent = data.local_time;
        } catch (_) {}
      }
      setInterval(refreshLocalTime, 1000);
    </script>
  </body>
</html>
"""

app = Flask(__name__)


@dataclass
class Flash:
    ok: bool
    message: str


def _run(cmd: list[str]) -> str:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    return p.stdout


def kiosk_is_running() -> bool:
    p = subprocess.run(
        ["/bin/bash", "-lc", "pgrep -fa 'chromium.*--kiosk' >/dev/null 2>&1"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        text=True,
    )
    return p.returncode == 0


def _pi_env(extra: Optional[dict[str, str]] = None) -> dict[str, str]:
    env = dict(os.environ)
    env.update({"HOME": PI_HOME, "USER": PI_USER, "LOGNAME": PI_USER})

    # Try Wayland first (Labwc), otherwise fall back to X11 (:0).
    wayland_sock = Path(PI_RUNTIME_DIR) / PI_WAYLAND_DISPLAY
    x11_sock = Path("/tmp/.X11-unix/X0")
    if wayland_sock.exists():
        env.update(
            {
                "XDG_RUNTIME_DIR": PI_RUNTIME_DIR,
                "WAYLAND_DISPLAY": PI_WAYLAND_DISPLAY,
                "XDG_SESSION_TYPE": "wayland",
                "DBUS_SESSION_BUS_ADDRESS": f"unix:path={PI_RUNTIME_DIR}/bus",
            }
        )
    elif x11_sock.exists():
        env.update(
            {
                "DISPLAY": PI_X11_DISPLAY,
                "XDG_SESSION_TYPE": "x11",
                "XAUTHORITY": PI_XAUTHORITY,
            }
        )
    if extra:
        env.update(extra)
    return env


def _run_as_pi_bash(script: str, extra_env: Optional[dict[str, str]] = None) -> int:
    env = _pi_env(extra_env)
    p = subprocess.run(
        ["runuser", "-u", PI_USER, "--", "/bin/bash", "-lc", script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        text=True,
        env=env,
    )
    return p.returncode


def read_kiosk_url() -> str:
    if not KIOSK_URL_FILE.exists():
        return ""
    for line in KIOSK_URL_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        return line
    return ""


def parse_oncalendar_hhmm(text: str) -> Optional[str]:
    m = re.search(r"\b(\d{2}):(\d{2}):\d{2}\b", text)
    if not m:
        return None
    return f"{m.group(1)}:{m.group(2)}"


def get_timer_time(timer_name: str) -> str:
    txt = _run(["systemctl", "cat", timer_name])
    m = re.search(r"^OnCalendar=(.+)$", txt, flags=re.MULTILINE)
    if not m:
        return ""
    hhmm = parse_oncalendar_hhmm(m.group(1))
    return hhmm or ""


def set_timer_time(timer_name: str, hhmm: str) -> None:
    if not re.match(r"^([01]\d|2[0-3]):[0-5]\d$", hhmm):
        raise ValueError("Time must be HH:MM (24h)")
    path = Path("/etc/systemd/system") / timer_name
    raw = path.read_text()
    new_line = f"OnCalendar=*-*-* {hhmm}:00"
    raw2, n = re.subn(r"(?m)^[ \t]*OnCalendar[ \t]*=.*$", new_line, raw)
    if n == 0:
        lines = raw.splitlines()
        out: list[str] = []
        in_timer = False
        inserted = False
        for line in lines:
            if re.match(r"^\[Timer\]\s*$", line):
                in_timer = True
                out.append(line)
                out.append(new_line)
                inserted = True
                continue
            if in_timer and re.match(r"^\[.+\]\s*$", line):
                in_timer = False
            out.append(line)
        if not inserted:
            raise RuntimeError(f"Failed to update OnCalendar in {path}")
        raw2 = "\n".join(out) + "\n"
    path.write_text(raw2)
    _run(["systemctl", "daemon-reload"])
    _run(["systemctl", "restart", timer_name])


def get_timezone() -> str:
    txt = _run(["timedatectl"])
    m = re.search(r"Time zone:\s+(.+)$", txt, flags=re.MULTILINE)
    return m.group(1).strip() if m else ""


def timers_status_text() -> str:
    return _run(["systemctl", "list-timers", "--all", "--no-pager"])


def current_local_time() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


@app.get("/")
def index() -> str:
    flash: Optional[Flash] = None
    if request.args.get("ok"):
        flash = Flash(ok=True, message=request.args.get("ok") or "")
    if request.args.get("err"):
        flash = Flash(ok=False, message=request.args.get("err") or "")

    return render_template_string(
        HTML,
        flash=flash,
        current_url=read_kiosk_url(),
        tv_on_timer=TV_ON_TIMER,
        tv_off_timer=TV_OFF_TIMER,
        on_time=get_timer_time(TV_ON_TIMER) or "07:30",
        off_time=get_timer_time(TV_OFF_TIMER) or "23:51",
        tz=get_timezone(),
        local_time=current_local_time(),
        timers_text=timers_status_text(),
    )


@app.get("/device-info")
def device_info() -> Response:
    hostname = (_run(["/bin/hostname"]).strip()) or ""
    ips = (_run(["/bin/bash", "-lc", "hostname -I 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//'"]).strip()) or ""
    resp = jsonify({"hostname": hostname, "ips": ips})
    resp.headers["Access-Control-Allow-Origin"] = "*"
    return resp


@app.get("/local-time")
def local_time() -> Response:
    return jsonify({"local_time": current_local_time(), "tz": get_timezone()})


@app.post("/set-url")
def set_url():
    url = (request.form.get("url") or "").strip()
    try:
        if not re.match(r"^https?://", url):
            raise ValueError("URL must start with http:// or https://")
        KIOSK_URL_FILE.write_text(url + "\n")
        # Apply immediately: restart kiosk in the pi Wayland session without turning TV on.
        _run_as_pi_bash(f"{KIOSK_STOP_SH!r}")
        subprocess.run(["/bin/bash", "-lc", "rm -f /tmp/kiosk.disabled; sleep 1"], check=False)
        rc = _run_as_pi_bash(
            f"rm -f /tmp/kiosk.disabled; NO_TV_ON=1 nohup {KIOSK_WAYLAND_SH!r} >/dev/null 2>&1 &",
            extra_env={"NO_TV_ON": "1"},
        )
        if rc != 0:
            raise RuntimeError("URL saved, but failed to restart kiosk.")
        return redirect(url_for("index", ok="URL updated and kiosk restarted."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.post("/set-schedule")
def set_schedule():
    on_time = (request.form.get("on_time") or "").strip()
    off_time = (request.form.get("off_time") or "").strip()
    try:
        set_timer_time(TV_ON_TIMER, on_time)
        set_timer_time(TV_OFF_TIMER, off_time)
        return redirect(url_for("index", ok="Schedule updated. Timers restarted."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.post("/restart-kiosk")
def restart_kiosk():
    try:
        _run_as_pi_bash(f"{KIOSK_STOP_SH!r}")
        subprocess.run(["/bin/bash", "-lc", "rm -f /tmp/kiosk.disabled; sleep 1"], check=False)
        rc = _run_as_pi_bash(
            f"rm -f /tmp/kiosk.disabled; NO_TV_ON=1 nohup {KIOSK_WAYLAND_SH!r} >/dev/null 2>&1 &",
            extra_env={"NO_TV_ON": "1"},
        )
        if rc != 0:
            raise RuntimeError("Failed to start kiosk in pi Wayland session.")
        return redirect(url_for("index", ok="Kiosk restart triggered."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.post("/kiosk-start")
def kiosk_start():
    try:
        subprocess.run(["/bin/bash", "-lc", "rm -f /tmp/kiosk.disabled"], check=False)
        rc = _run_as_pi_bash(f"rm -f /tmp/kiosk.disabled; nohup {KIOSK_WAYLAND_SH!r} >/dev/null 2>&1 &")
        if rc != 0:
            raise RuntimeError("Failed to start kiosk in pi Wayland session.")
        return redirect(url_for("index", ok="Kiosk start triggered."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.post("/kiosk-stop")
def kiosk_stop():
    try:
        _run_as_pi_bash(f"{KIOSK_STOP_SH!r}")
        return redirect(url_for("index", ok="Kiosk stop triggered."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.post("/show-desktop")
def show_desktop():
    try:
        # Requirement: showing the desktop should stop kiosk too.
        rc = _run_as_pi_bash(f"nohup {SHOW_DESKTOP_SH!r} >/dev/null 2>&1 &")
        if rc != 0:
            raise RuntimeError("Failed to start desktop UI in pi Wayland session.")
        return redirect(url_for("index", ok="Desktop UI started (kiosk stopped)."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.post("/reboot")
def reboot():
    try:
        subprocess.Popen(
            ["/bin/bash", "-lc", "sleep 2; systemctl reboot"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return redirect(url_for("index", ok="Reboot triggered."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.post("/tv-on")
def tv_on():
    try:
        if not kiosk_is_running():
            _run_as_pi_bash(
                f"rm -f /tmp/kiosk.disabled; NO_TV_ON=1 nohup {KIOSK_WAYLAND_SH!r} >/dev/null 2>&1 &",
                extra_env={"NO_TV_ON": "1"},
            )
            subprocess.run(["/bin/bash", "-lc", "sleep 2"], check=False)
        subprocess.run(["systemctl", "start", "pi-tv-on.service"], check=False)
        return redirect(url_for("index", ok="TV ON triggered."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.post("/tv-off")
def tv_off():
    try:
        subprocess.run(["systemctl", "start", "pi-tv-off.service"], check=False)
        return redirect(url_for("index", ok="TV OFF triggered."))
    except Exception as e:
        return redirect(url_for("index", err=str(e)))


@app.get("/health")
def health() -> Response:
    path = Path(HEALTH_CHECK_SH)
    if not path.exists():
        return Response("health_check.sh missing\n", mimetype="text/plain; charset=utf-8", status=500)
    out = _run([str(path)])
    return Response(out, mimetype="text/plain; charset=utf-8")


def main() -> None:
    host = os.environ.get("KIOSK_ADMIN_HOST", "0.0.0.0")
    port = int(os.environ.get("KIOSK_ADMIN_PORT", "8088"))
    app.run(host=host, port=port, debug=False, use_reloader=False)


if __name__ == "__main__":
    main()

