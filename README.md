# Shopkeeper

A touch-based kids' game (built for a 4-year-old), made in **Godot 4 / GDScript**.
It ships as a Windows build on an HP Spectre touchscreen laptop first and an
Android app later.

This repository is being built in phases. **Phase 2 (this PR)** adds the actual
game loop on top of the Phase 1 input seam: a customer walks up, asks for an
item, and she drags it off the shelf and onto the customer. Correct delivery →
cheer, confetti, a coin on the counter and the till ticks up; wrong item → the
customer giggles and asks again (no penalty, no timer, no fail state); after a
fixed number of rounds the shop reaches "closing time". All of it is driven
through the same swappable `InputProvider`, so a recording plays a whole session
with no screen. **The art is placeholder only** (flat labelled shapes); Phase 3
replaces every sprite, background and sound with real ComfyUI art and Kokoro
voice. See [`docs/DESIGN.md`](docs/DESIGN.md) for the full v1 design.

## Layout

```
game/                 # the Godot 4 project (open this folder in Godot)
  project.godot       # main scene = scenes/title.tscn; SFX/Voice audio buses
  config.cfg          # ALL difficulty / layout knobs, no code (see below)
  audio_bus_layout.tres
  input/              # the input seam (Phase 1)
    input_provider.gd # InputProvider + Pointer data class
    touch_provider.gd # finger / mouse -> normalized Pointer (first finger wins)
    replay_provider.gd# deterministic playback of a recorded JSONL file
    recorder.gd       # wraps any provider, writes Pointers to user:// as JSONL
  scripts/            # the game loop (Phase 2)
    game_config.gd    # typed reader for config.cfg (one place, no magic numbers)
    zones.gd          # shelf slots / counter / customer zone as 0..1 rects
    select.gd         # drag + tap-tap gesture state machine over Pointer
    shop_model.gd     # pure rules: shelf, order, till, rounds (tested headless)
    shop.gd           # the playable shop: view + tweens + confetti + audio
    audio.gd          # SFX/voice hooks (placeholder beeps; Phase 3 real audio)
    title.gd / closing.gd / session_state.gd
  scenes/
    title.tscn        # shop name + tap to play  (main scene)
    shop.tscn         # the game loop
    closing.tscn      # "closing time" wrap-up
    main.tscn/.gd     # Phase 1 input-seam demo (kept; no longer the entry point)
  assets/
    sprites/ backgrounds/ sfx/ voice/   # PLACEHOLDER art + beeps (see tools/)
  test/               # headless test runner + fixtures
tools/
  make_placeholders.py # regenerates the placeholder art + beeps (Pillow)
docs/DESIGN.md        # v1 design spec (read this for Phase 3)
```

## Open and run in Godot 4

1. Install **Godot 4.4+** (standard editor build — it includes headless mode).
2. In the Godot Project Manager choose **Import**, pick this repo's `game/`
   folder (the one with `project.godot`), and open it.
3. Press **Play** (F5). The title screen appears; tap/click to start. Drag an
   item off the shelf onto the customer on the left to serve them. (Mouse input
   is emulated as touch, so the same code path runs on the desktop and on the
   Spectre's touchscreen.)

> **Play-test on the Spectre:** this PR was validated headless in the cloud
> (see "Run the tests"), but the *feel* — drag thresholds, hit-box size, pacing
> for a 4-year-old — can only be judged by pressing Play on the touchscreen.
> That tuning is what `config.cfg` is for.

## Difficulty knobs (`game/config.cfg`)

Everything the game varies lives in `config.cfg`; nothing is hard-coded. Edit,
restart, done. `interaction_mode` = `drag` or `tap_tap`; `hit_box_size` and
`drop_zone_size` are fractions of screen width (bigger = easier); plus
`rounds_per_session`, `items_on_shelf`, `hint_glow` (+ `hint_rounds`),
`shuffle_every`, and `voice_speed`.

## Regenerate the placeholder art

The sprites, backgrounds and beeps under `game/assets/` are committed but
disposable. To rebuild them:

```
pip install pillow
python3 tools/make_placeholders.py
```

Phase 3 replaces this script's output wholesale with real art and voice.

## Run the tests headless

No GUI needed. From the repo root, with the Godot binary on your path as
`godot`:

```
godot --headless --path game --import                       # first time / CI: import assets
godot --headless --path game --script res://test/run_tests.gd
```

Exit code is `0` when all assertions pass, `1` otherwise (70 assertions as of
Phase 2). The suite covers:

- **Phase 1 seam:** deterministic 3-point replay, recorder round-trip, the
  first-finger-wins rule, coordinate clamping to 0..1.
- **Phase 2 loop (driven through `ReplayProvider`):** a full round delivers the
  correct item and ticks the till; a wrong item is not delivered and carries no
  penalty (same customer repeats); releasing outside the drop zone returns the
  item; a ten-round replay plays through to closing time; the `config.cfg` knobs
  actually change behavior (`interaction_mode` routes drag vs. tap-tap; a larger
  `hit_box_size` widens the pickable area); `config.cfg` itself parses; and all
  three scenes build their view without script errors.

> The suite uses the repo's own small self-contained runner rather than GUT.
> Phase 1 chose this deliberately — to avoid pinning a GUT/Godot version pair
> before the engine version is fixed on the Spectre — and the Phase 2 tests
> keep that choice. They still map one-to-one onto GUT test methods (one
> `_test_*` per behavior, `_check` == an assert), so adopting GUT later remains
> a drop-in.

## Swap input providers

The game reads its provider from the `shopkeeper/input/provider` project setting
(`touch` by default). Override it on the command line (user args come after a
`--` separator):

```
# touch / mouse (default)
godot --path game

# play back a recorded session deterministically-at-real-time
godot --path game -- --provider=replay --replay=res://test/fixtures/replay_3pt.jsonl
```

A future camera/pose provider plugs into the same seam without touching the game
code.
