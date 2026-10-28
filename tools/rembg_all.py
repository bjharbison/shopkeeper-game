#!/usr/bin/env python3
"""Strip backgrounds and trim a folder of PNGs to their content.

RUNS ON BRIAN'S MAC, NOT IN CI / THE CLOUD. It is the post-processing step after
comfy_batch.py: ComfyUI renders items and characters on a plain background, and
this removes that background (rembg / U^2-Net) and trims each image to its alpha
bounding box with a little padding, so sprites sit cleanly on the shelf. rembg
downloads its model once on first run; everything else is local, no network at
use time.

By default it edits the sprite PNGs in place (characters/items need cut-outs);
backgrounds do NOT want their background removed, so point it only at
game/assets/sprites (the default), never at game/assets/backgrounds.

Prerequisites (Mac):
  - `uv sync` in this folder (installs rembg, pillow, numpy; rembg pulls
    onnxruntime). First run downloads the rembg model (~170 MB) to your cache.

Usage:
  uv run tools/rembg_all.py                          # defaults to game/assets/sprites, in place
  uv run tools/rembg_all.py game/assets/sprites
  uv run tools/rembg_all.py game/assets/sprites --out game/assets/sprites_cut --pad 8
  uv run tools/rembg_all.py game/assets/sprites --only item_apple,customer_1 --no-trim
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
    from rembg import remove, new_session
except ImportError:  # pragma: no cover - guidance only
    sys.exit("rembg_all needs rembg, pillow and numpy. Run `uv sync` in this folder first.")


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = REPO_ROOT / "game" / "assets" / "sprites"


def _trim(img: Image.Image, pad: int) -> Image.Image:
    """Crop to the alpha bounding box, then pad by `pad` transparent pixels."""
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    alpha = np.asarray(img)[:, :, 3]
    ys, xs = np.where(alpha > 8)
    if xs.size == 0 or ys.size == 0:
        return img  # fully transparent — leave as-is
    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    cropped = img.crop((x0, y0, x1 + 1, y1 + 1))
    if pad <= 0:
        return cropped
    out = Image.new("RGBA", (cropped.width + 2 * pad, cropped.height + 2 * pad), (0, 0, 0, 0))
    out.paste(cropped, (pad, pad))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", nargs="?", default=str(DEFAULT_DIR), help="folder of PNGs (default game/assets/sprites)")
    ap.add_argument("--out", default="", help="output folder (default: edit in place)")
    ap.add_argument("--pad", type=int, default=6, help="transparent padding after trim, px")
    ap.add_argument("--no-trim", action="store_true", help="remove background but keep original size")
    ap.add_argument("--only", default="", help="comma-separated file stems; default all PNGs")
    ap.add_argument("--model", default="u2net", help="rembg model name")
    args = ap.parse_args()

    src = Path(args.folder)
    if not src.is_dir():
        sys.exit(f"not a folder: {src}")
    out_dir = Path(args.out) if args.out else src
    out_dir.mkdir(parents=True, exist_ok=True)

    only = {s.strip() for s in args.only.split(",") if s.strip()}
    pngs = sorted(p for p in src.glob("*.png") if not only or p.stem in only)
    if not pngs:
        print("No matching PNGs found.")
        return 0

    session = new_session(args.model)
    for p in pngs:
        try:
            with Image.open(p) as im:
                cut = remove(im.convert("RGBA"), session=session)
            if not args.no_trim:
                cut = _trim(cut, args.pad)
            dest = out_dir / p.name
            cut.save(dest)
            print(f"[{p.name}] -> {dest.relative_to(REPO_ROOT) if dest.is_relative_to(REPO_ROOT) else dest}")
        except Exception as exc:
            print(f"[{p.name}] FAILED: {exc}", file=sys.stderr)

    print("\nDone. Check the cut-outs at 25% zoom (TV distance) before committing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
