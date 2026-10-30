#!/usr/bin/env python3
"""Render Shopkeeper voice lines through Kokoro and write OGG files.

RUNS ON BRIAN'S MAC, NOT IN CI / THE CLOUD. It talks to a Kokoro-FastAPI server
running locally on the Mac (OpenAI-compatible /v1/audio/speech endpoint on
:8880, per docs/DESIGN.md), renders each row of tools/voice_lines.csv, and
writes <slug>.ogg into game/assets/voice/ — the slug names scripts/audio.gd
asks for. Nothing here runs on the console; nothing leaves the Mac's LAN.

Flow, per row of voice_lines.csv (slug,voice,speed,text):
  1. POST {text, voice, speed} to Kokoro, asking for WAV back,
  2. decode the WAV and re-encode to OGG/Vorbis (libsndfile via soundfile),
  3. peak-normalise loudness so lines sit at a consistent level,
  4. save game/assets/voice/<slug>.ogg.

The game prefers a real .ogg over the Phase 2 placeholder, so dropping these in
needs no code change (see docs/DESIGN.md "Asset naming contract").

Prerequisites (Mac):
  - Kokoro-FastAPI running locally (default http://127.0.0.1:8880).
  - `uv sync` in this folder (installs requests, soundfile, numpy). soundfile
    bundles libsndfile, which encodes OGG/Vorbis — no ffmpeg needed.

Usage:
  uv run tools/make_voice.py                                   # all lines
  uv run tools/make_voice.py --server http://127.0.0.1:8880
  uv run tools/make_voice.py --only thanks,order_apple
  uv run tools/make_voice.py --model kokoro --dry-run
"""

from __future__ import annotations

import argparse
import csv
import io
import sys
from pathlib import Path

try:
    import numpy as np
    import requests
    import soundfile as sf
except ImportError:  # pragma: no cover - guidance only
    sys.exit("make_voice needs requests, soundfile and numpy. Run `uv sync` in this folder first.")


REPO_ROOT = Path(__file__).resolve().parent.parent
VOICE_DIR = REPO_ROOT / "game" / "assets" / "voice"
PEAK = 0.95  # normalise each line so its loudest sample hits this


def _load_manifest(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(r for r in f if not r.lstrip().startswith("#"))
        for row in reader:
            if not row.get("slug") or not row.get("text"):
                continue
            rows.append({k: (v or "").strip() for k, v in row.items()})
    return rows


def _synthesize(server: str, model: str, voice: str, speed: float, text: str) -> tuple[np.ndarray, int]:
    """Ask Kokoro for a WAV of `text` and return (samples float32 mono, sample_rate)."""
    payload = {
        "model": model,
        "input": text,
        "voice": voice,
        "response_format": "wav",
        "speed": speed,
    }
    resp = requests.post(f"{server}/v1/audio/speech", json=payload, timeout=120)
    resp.raise_for_status()
    data, sr = sf.read(io.BytesIO(resp.content), dtype="float32", always_2d=False)
    if data.ndim > 1:  # down-mix to mono
        data = data.mean(axis=1)
    return data, sr


def _normalise(samples: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak > 1e-6:
        samples = samples * (PEAK / peak)
    return samples


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=str(REPO_ROOT / "tools" / "voice_lines.csv"))
    ap.add_argument("--server", default="http://127.0.0.1:8880")
    ap.add_argument("--model", default="kokoro")
    ap.add_argument("--only", default="", help="comma-separated slugs; default all")
    ap.add_argument("--dry-run", action="store_true", help="print lines, synthesise nothing")
    args = ap.parse_args()

    server = args.server.rstrip("/")
    rows = _load_manifest(Path(args.manifest))
    only = {s.strip() for s in args.only.split(",") if s.strip()}
    if only:
        rows = [r for r in rows if r["slug"] in only]
    if not rows:
        print("Nothing to do (manifest empty or --only matched nothing).")
        return 0

    VOICE_DIR.mkdir(parents=True, exist_ok=True)
    failures = 0
    for row in rows:
        slug = row["slug"]
        voice = row.get("voice", "af_heart")
        text = row["text"]
        try:
            speed = float(row.get("speed", "1.0") or "1.0")
        except ValueError:
            speed = 1.0
        dest = VOICE_DIR / f"{slug}.ogg"
        print(f"[{slug}] voice={voice} speed={speed}  \"{text}\"")
        if args.dry_run:
            continue
        try:
            samples, sr = _synthesize(server, args.model, voice, speed, text)
            sf.write(dest, _normalise(samples), sr, format="OGG", subtype="VORBIS")
            print(f"    saved {dest.name} ({len(samples)/sr:.1f}s @ {sr} Hz)")
        except Exception as exc:
            failures += 1
            print(f"    FAILED: {exc}", file=sys.stderr)

    if failures:
        print(f"\nDone with {failures} failure(s).", file=sys.stderr)
        return 1
    print("\nAll voice lines rendered into game/assets/voice/. Open the game to hear them.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
