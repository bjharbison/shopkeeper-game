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
