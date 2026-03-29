#!/usr/bin/env python3
"""Build 1920x1080 boot splash from assets/av-booth-logo.png + assets/media-booth-logo.png."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
ASSETS = REPO / "assets"
OUT = ASSETS / "boot-splash-1080p.png"
W, H = 1920, 1080


def fit_in_box(img: Image.Image, box_w: int, box_h: int) -> Image.Image:
    img = img.convert("RGBA")
    iw, ih = img.size
    scale = min(box_w / iw, box_h / ih, 1.0)
    nw = max(1, int(iw * scale))
    nh = max(1, int(ih * scale))
    return img.resize((nw, nh), Image.Resampling.LANCZOS)


def main() -> None:
    left_src = ASSETS / "av-booth-logo.png"
    right_src = ASSETS / "media-booth-logo.png"
    if not left_src.is_file() or not right_src.is_file():
        raise SystemExit(f"Missing {left_src} or {right_src}")

    mid = W // 2
    pad_x, pad_y = 48, 64
    box_w, box_h = mid - 2 * pad_x, H - 2 * pad_y

    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    left = fit_in_box(Image.open(left_src), box_w, box_h)
    right = fit_in_box(Image.open(right_src), box_w, box_h)

    lx = pad_x + (box_w - left.width) // 2
    ly = pad_y + (box_h - left.height) // 2
    canvas.paste(left, (lx, ly), left)

    rx = mid + pad_x + (box_w - right.width) // 2
    ry = pad_y + (box_h - right.height) // 2
    canvas.paste(right, (rx, ry), right)

    rgb = canvas.convert("RGB")
    rgb.save(OUT, "PNG", optimize=True)
    print(f"Wrote {OUT} ({rgb.size[0]}x{rgb.size[1]})")


if __name__ == "__main__":
    main()
