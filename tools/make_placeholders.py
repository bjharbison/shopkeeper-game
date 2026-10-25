#!/usr/bin/env python3
"""Generate PLACEHOLDER art for Shopkeeper (Phase 2).

These are deliberately crude: flat shapes, a label, and a "PLACEHOLDER" stamp,
so nobody mistakes them for the real thing. Phase 3 replaces every file this
writes with hand-finished ComfyUI art (see docs/DESIGN.md "Asset pipeline").
The game loads these by filename; Phase 3 keeps the names and swaps the pixels.

Usage:
    python3 tools/make_placeholders.py            # writes into game/assets/
    python3 tools/make_placeholders.py --out DIR  # custom output root

Requires Pillow (pip install pillow).
"""

from __future__ import annotations

import argparse
import math
import os
import struct
import wave
from PIL import Image, ImageDraw, ImageFont

# Item id -> (fill RGB, short glyph drawn big). Ids match ShopModel.ITEM_POOL.
ITEMS = {
    "apple":   ((214, 69, 65),   "circle"),
    "bread":   ((198, 143, 72),  "loaf"),
    "teddy":   ((150, 103, 66),  "bear"),
    "balloon": ((233, 115, 165), "balloon"),
    "flower":  ((224, 96, 140),  "flower"),
    "fish":    ((86, 160, 200),  "fish"),
    "cake":    ((238, 170, 190), "cake"),
    "hat":     ((94, 110, 180),  "hat"),
}

# Customers: just distinct body colors. Phase 3 makes them characters.
CUSTOMER_COLORS = [
    (242, 180, 92),
    (120, 190, 140),
    (150, 160, 220),
    (230, 140, 120),
    (170, 150, 200),
]

SHOPKEEPER_COLOR = (240, 200, 110)


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # very old Pillow
        return ImageFont.load_default()


def _centered(draw: ImageDraw.ImageDraw, box, text, font, fill):
    x0, y0, x1, y1 = box
    tb = draw.textbbox((0, 0), text, font=font)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    draw.text(
        ((x0 + x1 - tw) / 2 - tb[0], (y0 + y1 - th) / 2 - tb[1]),
        text, font=font, fill=fill,
    )


def _stamp(draw: ImageDraw.ImageDraw, w: int, h: int):
    """Mark the image as temporary."""
    f = _font(max(10, w // 18))
    draw.text((6, h - max(14, w // 16) - 4), "PLACEHOLDER", font=f, fill=(0, 0, 0, 160))


def make_item(item_id: str, fill, size: int = 256) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = size // 8
    # Chunky rounded shape with a thick dark outline — the DESIGN "thick outline"
    # look, in the crudest possible form.
    d.rounded_rectangle([m, m, size - m, size - m], radius=size // 6,
                        fill=fill + (255,), outline=(40, 30, 30, 255), width=max(4, size // 40))
    _centered(d, (0, 0, size, size - size // 6), item_id.upper(), _font(size // 8), (20, 15, 15, 255))
    _stamp(d, size, size)
    return img


def make_character(color, label: str, w: int = 300, h: int = 420) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Body
    d.rounded_rectangle([w * 0.2, h * 0.35, w * 0.8, h * 0.95], radius=w // 6,
                        fill=color + (255,), outline=(40, 30, 30, 255), width=6)
    # Head
    hr = w * 0.22
    cx = w / 2
    cy = h * 0.25
    d.ellipse([cx - hr, cy - hr, cx + hr, cy + hr],
              fill=color + (255,), outline=(40, 30, 30, 255), width=6)
    # Simple face
    d.ellipse([cx - hr * 0.45, cy - hr * 0.2, cx - hr * 0.15, cy + hr * 0.1], fill=(30, 25, 25, 255))
    d.ellipse([cx + hr * 0.15, cy - hr * 0.2, cx + hr * 0.45, cy + hr * 0.1], fill=(30, 25, 25, 255))
    d.arc([cx - hr * 0.4, cy + hr * 0.05, cx + hr * 0.4, cy + hr * 0.5], 20, 160, fill=(30, 25, 25, 255), width=4)
    _centered(d, (0, h * 0.62, w, h * 0.82), label, _font(26), (25, 20, 20, 255))
    _stamp(d, w, h)
    return img


def make_coin(size: int = 96) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([4, 4, size - 4, size - 4], fill=(240, 196, 70, 255), outline=(150, 110, 20, 255), width=5)
    _centered(d, (0, 0, size, size), "$", _font(size // 2), (120, 85, 10, 255))
    return img


def make_background(path: str, wall, floor, w: int = 1920, h: int = 1080):
    img = Image.new("RGBA", (w, h), wall + (255,))
    d = ImageDraw.Draw(img)
    # Floor
    d.rectangle([0, int(h * 0.78), w, h], fill=floor + (255,))
    # A couple of shelf planks across the top-right, matching the shelf region.
    shelf_left = int(w * 0.36)
    for frac in (0.18, 0.40):
        y = int(h * frac)
        d.rectangle([shelf_left, y, int(w * 0.98), y + 18], fill=(120, 86, 55, 255))
    # Counter band along the bottom.
    d.rectangle([shelf_left, int(h * 0.80), int(w * 0.98), int(h * 0.80) + 26], fill=(110, 78, 50, 255))
    d2 = ImageDraw.Draw(img)
    d2.text((20, 20), "PLACEHOLDER BACKGROUND - Phase 3 replaces", font=_font(40), fill=(0, 0, 0, 120))
    img.save(path)


# --- placeholder SFX (stdlib only; no numpy) -------------------------------
# Short distinct beeps so every game event is audible. Phase 3 replaces these
# with real SFX (pop/chime/whoosh) and the Kokoro voice lines.
_SR = 22050


def _write_wav(path: str, samples: list[float]):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(_SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 30000)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


def _tone(freq, dur, vol=0.6, sweep=0.0):
    n = int(_SR * dur)
    out = []
    for i in range(n):
        t = i / _SR
        f = freq + sweep * (i / n)
        env = min(1.0, 10 * t) * min(1.0, 10 * (dur - t))  # quick fade in/out
        out.append(vol * env * math.sin(2 * math.pi * f * t))
    return out


def make_sfx(sfx_dir: str):
    os.makedirs(sfx_dir, exist_ok=True)
    cues = {
        "pop": _tone(880, 0.09, sweep=220),       # item lifts
        "boing": _tone(520, 0.22, sweep=-260),    # floats back
        "cheer": _tone(660, 0.12) + _tone(880, 0.12) + _tone(1100, 0.16),  # little arpeggio
        "giggle": _tone(700, 0.08, sweep=120) + _tone(620, 0.08, sweep=120) + _tone(760, 0.08, sweep=120),
        "coin": _tone(1245, 0.07) + _tone(1660, 0.10),
        "till": _tone(1500, 0.05) + _tone(1900, 0.07),
    }
    for name, samples in cues.items():
        _write_wav(os.path.join(sfx_dir, f"{name}.wav"), samples)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(repo, "game", "assets"))
    args = ap.parse_args()

    sprites = os.path.join(args.out, "sprites")
    backgrounds = os.path.join(args.out, "backgrounds")
    os.makedirs(sprites, exist_ok=True)
    os.makedirs(backgrounds, exist_ok=True)

    for item_id, (fill, _glyph) in ITEMS.items():
        make_item(item_id, fill).save(os.path.join(sprites, f"item_{item_id}.png"))

    for i, color in enumerate(CUSTOMER_COLORS):
        make_character(color, f"customer {i + 1}").save(os.path.join(sprites, f"customer_{i + 1}.png"))

    make_character(SHOPKEEPER_COLOR, "shopkeeper").save(os.path.join(sprites, "shopkeeper.png"))
    make_coin().save(os.path.join(sprites, "coin.png"))

    make_background(os.path.join(backgrounds, "shop.png"), (196, 170, 140), (150, 120, 90))
    make_background(os.path.join(backgrounds, "shop_sunset.png"), (232, 160, 120), (120, 95, 80))

    make_sfx(os.path.join(args.out, "sfx"))

    print(f"Wrote placeholder art + sfx under {args.out}")


if __name__ == "__main__":
    main()
