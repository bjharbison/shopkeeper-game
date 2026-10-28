#!/usr/bin/env python3
"""Batch-generate Shopkeeper sprites/backgrounds from a local ComfyUI.

RUNS ON BRIAN'S MAC, NOT IN CI / THE CLOUD. It talks to a ComfyUI instance
running locally (the Mac inference stack), posts one render job per row of
tools/assets.csv, waits for each to finish, and downloads the result into
game/assets/ under the slug name the game loads. Nothing here runs on the
Spectre or the Pi, and nothing contacts the network beyond the local ComfyUI.

What it does, per row of assets.csv:
  1. builds the prompt = the FROZEN STYLE STEM (below) + the row's `subject`,
  2. injects that prompt (and a per-slug seed) into your exported ComfyUI
     API-format workflow JSON,
  3. POSTs it to  {--server}/prompt,
  4. polls {--server}/history/<id> until the job completes,
  5. GETs the image from {--server}/view and saves it to
     game/assets/<target_dir>/<slug>.png  (e.g. sprites/item_apple.png).

Freezing the style: run the style-anchor pass FIRST (see docs/DESIGN.md "Asset
pipeline"), pick the checkpoint + prompt stem + seed family that look right,
then paste the stem into STYLE_STEM below and commit it. Every asset reuses it,
which is what keeps 30 sprites looking like one game.

Prerequisites (Mac):
  - ComfyUI running locally (default http://127.0.0.1:8188).
  - An API-format workflow exported from ComfyUI (Save (API Format)) saved to
    tools/comfy_workflow.api.json, with your checkpoint + sampler wired up.
  - `uv sync` in this folder (installs `requests`).

Usage:
  uv run tools/comfy_batch.py \
      --workflow tools/comfy_workflow.api.json \
      --manifest tools/assets.csv \
      --server http://127.0.0.1:8188 \
      --prompt-node 6 --seed-node 3            # node ids in YOUR workflow
  # then strip backgrounds / trim:  uv run tools/rembg_all.py game/assets/sprites

Only --workflow is required; the rest have the defaults shown. Use --only
<slug>[,<slug>] to regenerate a single asset, and --dry-run to print the jobs
without posting them.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
import zlib
from pathlib import Path

try:
    import requests
except ImportError:  # pragma: no cover - guidance only
    sys.exit("comfy_batch needs `requests`. Run `uv sync` in this folder first.")


# ---------------------------------------------------------------------------
# FROZEN STYLE STEM. Assembled from the words in docs/DESIGN.md "Graphics
# direction" / "Asset pipeline": painterly cartoon, thick outlines, warm limited
# palette, chunky rounded shapes, transparent/plain background. Replace with the
# exact stem you froze after the style-anchor pass; keep it identical across runs.
STYLE_STEM = (
    "children's book illustration, painterly cartoon style, soft warm limited "
    "palette, chunky rounded shapes with thick dark outlines, friendly and cute, "
    "high quality, centered"
)
NEGATIVE = "photo, realistic, text, watermark, extra limbs, blurry, cluttered background"

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_ROOT = REPO_ROOT / "game" / "assets"


def _seed_for(slug: str) -> int:
    """Stable per-slug seed so a re-run reproduces the same asset (and a changed
    STYLE_STEM re-rolls them all together)."""
    return zlib.adler32((STYLE_STEM + "::" + slug).encode("utf-8")) & 0x7FFFFFFF


def _load_manifest(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(r for r in f if not r.lstrip().startswith("#"))
        for row in reader:
            if not row.get("slug"):
                continue
            rows.append({k: (v or "").strip() for k, v in row.items()})
    return rows


def _inject(workflow: dict, prompt_node: str, seed_node: str, prompt: str, seed: int) -> dict:
    """Return a copy of the workflow with the positive prompt and seed set.

    ComfyUI API-format workflows are {node_id: {"inputs": {...}, "class_type": ...}}.
    We set the positive CLIPTextEncode node's `text` and the sampler node's `seed`.
    Node ids differ per workflow, so they are passed on the command line.
    """
    wf = json.loads(json.dumps(workflow))  # deep copy
    if prompt_node not in wf:
        raise KeyError(f"prompt node '{prompt_node}' not in workflow")
    wf[prompt_node].setdefault("inputs", {})["text"] = prompt
    if seed_node in wf:
        inputs = wf[seed_node].setdefault("inputs", {})
        # Different samplers name it "seed" or "noise_seed".
        if "noise_seed" in inputs:
            inputs["noise_seed"] = seed
        else:
            inputs["seed"] = seed
    return wf


def _submit(server: str, workflow: dict) -> str:
    resp = requests.post(f"{server}/prompt", json={"prompt": workflow}, timeout=30)
    resp.raise_for_status()
    prompt_id = resp.json().get("prompt_id")
    if not prompt_id:
        raise RuntimeError(f"ComfyUI did not return a prompt_id: {resp.text[:200]}")
    return prompt_id


def _wait(server: str, prompt_id: str, timeout_s: float) -> dict:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        resp = requests.get(f"{server}/history/{prompt_id}", timeout=30)
        resp.raise_for_status()
        hist = resp.json()
        if prompt_id in hist:
            return hist[prompt_id]
        time.sleep(1.0)
    raise TimeoutError(f"job {prompt_id} did not finish within {timeout_s:.0f}s")


def _first_image(history: dict) -> dict:
    for node_out in history.get("outputs", {}).values():
        for img in node_out.get("images", []):
            return img  # {"filename","subfolder","type"}
    raise RuntimeError("job finished but produced no image (check the workflow's SaveImage node)")


def _download(server: str, img: dict, dest: Path) -> None:
    params = {"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")}
    resp = requests.get(f"{server}/view", params=params, timeout=60)
    resp.raise_for_status()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(resp.content)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workflow", required=True, help="ComfyUI API-format workflow JSON")
    ap.add_argument("--manifest", default=str(REPO_ROOT / "tools" / "assets.csv"))
    ap.add_argument("--server", default="http://127.0.0.1:8188")
    ap.add_argument("--prompt-node", default="6", help="node id of the positive CLIPTextEncode")
    ap.add_argument("--seed-node", default="3", help="node id of the sampler (KSampler)")
    ap.add_argument("--only", default="", help="comma-separated slugs to (re)generate; default all")
    ap.add_argument("--timeout", type=float, default=180.0, help="per-job wait, seconds")
    ap.add_argument("--dry-run", action="store_true", help="print jobs, post nothing")
    args = ap.parse_args()

    server = args.server.rstrip("/")
    workflow = json.loads(Path(args.workflow).read_text(encoding="utf-8"))
    rows = _load_manifest(Path(args.manifest))
    only = {s.strip() for s in args.only.split(",") if s.strip()}
    if only:
        rows = [r for r in rows if r["slug"] in only]
    if not rows:
        print("Nothing to do (manifest empty or --only matched nothing).")
        return 0

    failures = 0
    for row in rows:
        slug = row["slug"]
        subject = row.get("subject", "")
        target_dir = row.get("target_dir", "sprites")
        prompt = f"{STYLE_STEM}, {subject}"
        seed = _seed_for(slug)
        dest = ASSETS_ROOT / target_dir / f"{slug}.png"
        print(f"[{slug}] -> {dest.relative_to(REPO_ROOT)}  (seed {seed})")
        print(f"    prompt: {prompt}")
        if args.dry_run:
            continue
        try:
            wf = _inject(workflow, args.prompt_node, args.seed_node, prompt, seed)
            prompt_id = _submit(server, wf)
            history = _wait(server, prompt_id, args.timeout)
            _download(server, _first_image(history), dest)
            print(f"    saved {dest.name}")
        except Exception as exc:  # keep going; one bad asset shouldn't stop the batch
            failures += 1
            print(f"    FAILED: {exc}", file=sys.stderr)

    if failures:
        print(f"\nDone with {failures} failure(s).", file=sys.stderr)
        return 1
    print("\nAll assets generated. Next: rembg_all.py to strip/trim, then open the game.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
