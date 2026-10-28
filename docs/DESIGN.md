# Shopkeeper — v1 Design Spec

This is the self-contained spec later phases build against. Phase 1 (this repo)
ships the scaffold and the input seam only; the game loop is Phase 2.

## What it is

Shopkeeper is a touch game for a 4-year-old. She runs a little shop: a customer
walks up, asks for something, she drags the item off the shelf and hands it over.
That is the whole loop, repeated with different customers and items for about a
five-minute session. v1 is built and played on a touchscreen laptop; it ships as
an Android app later.

## Rules for a 4-year-old

Drag-and-drop, large hit boxes, voice prompts instead of on-screen text (she
can't read). No fail state: a wrong item just makes the customer giggle and ask
again, with the right item glowing. No timer, no score that goes down. Every
difficulty knob — hit-box size, round count, items on shelf, voice speed — lives
in `config.cfg`, never in code.

## Architecture: one seam

The only code that knows about hardware is the input layer. Everything above the
`InputProvider` interface is plain game logic that runs identically on the
laptop, a tablet, or a TV.

A provider emits a stream of `Pointer` samples: `t` (seconds), `x`/`y`
(normalized 0..1, never pixels), `down` (pressed), `present` (anyone there, for a
future attract loop). Three providers, swapped by a project setting or a
`--provider` CLI arg:

- `TouchProvider` — finger/mouse now. First finger wins: once a finger is down it
  owns the pointer; a second touch is ignored until it lifts.
- `ReplayProvider` — plays a recorded JSONL file deterministically, for tests and
  tuning without a child in the loop.
- A future UDP pose provider — a separate Python process sends normalized body
  keypoints for a v3 camera console. The seam already allows it; it is not built.

`Recorder` wraps any provider and writes each `Pointer` as one JSONL line to
local `user://` storage.

## Technology

Engine is Godot 4 with GDScript for the game. Python is reserved for the asset
pipeline and the future pose tracker. Art is pre-rendered PNGs (placeholder
shapes until Brian's Mac ComfyUI pipeline replaces them wholesale). Voice lines
are pre-rendered audio, one voice per character.

## Privacy

No network permission, no accounts, no analytics, no recording unless explicitly
asked. On a future camera console, frames are processed in RAM and discarded.

## Asset naming contract

Every sprite, background, voice line and SFX is loaded **by slug** through
`scripts/assets.gd` (`AssetLibrary`). Nothing in the view code hard-codes a path.
This is the asset-swap seam: the Phase 2 placeholders and the Phase 3 real art
share the same slug names, so Brian's Mac pipeline (see "Asset pipeline") drops
real files in under these names and the game uses them with **zero code change**.
The tool manifests (`tools/assets.csv`, `tools/voice_lines.csv`) generate exactly
these names.

| Folder (`game/assets/…`) | Slug / filename | What it is |
| --- | --- | --- |
| `sprites/` | `item_<id>.png` | a shop item; `<id>` ∈ apple, bread, teddy, balloon, flower, fish, cake, hat |
| `sprites/` | `customer_<n>.png` | a customer, `<n>` = 1..5 |
| `sprites/` | `shopkeeper.png` | her avatar (used for the attract-mode wave) |
| `sprites/` | `coin.png` | the till coin |
| `backgrounds/` | `shop.png` | shop interior (title + play) |
| `backgrounds/` | `shop_sunset.png` | sunset interior (closing screen) |
| `voice/` | `order_<id>.ogg` | the customer asking for `item_<id>` |
| `voice/` | `thanks.ogg` | the thank-you after a correct delivery |
| `sfx/` | `pop` / `boing` / `cheer` / `giggle` / `coin` / `till` | event sounds |

Resolution rules (`AssetLibrary`):

- **Format priority.** Audio tries `.ogg` first, then `.wav`. Real assets ship as
  OGG (Kokoro voice, CC0 SFX); the Phase 2 placeholders are WAV. So a real
  `pop.ogg` dropped next to `pop.wav` wins automatically. Sprites/backgrounds are
  `.png`.
- **Fallback, never a crash.** A missing sprite slug yields an empty
  `PlaceholderTexture2D` (the view still lays out); a missing background yields a
  flat fill; a missing voice/SFX slug is simply silent. Present files are always
  used in preference.
- **Per-customer voice (optional).** `order_<id>_c<n>.ogg` / `thanks_c<n>.ogg`
  (customer `n` = 1..5) are preferred over the shared line when present — this is
  how "one voice per character" and name-baked lines ("thanks, Rose!") ship with
  no code change.

After dropping new files into `game/assets/`, open the project in the Godot
editor once so it (re)imports them; the next launch picks them up.
