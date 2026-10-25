# Shopkeeper

A touch-based kids' game (built for a 4-year-old), made in **Godot 4 / GDScript**.
It ships as a Windows build on an HP Spectre touchscreen laptop first and an
Android app later.

This repository is being built in phases. **Phase 1 (this PR)** is the project
scaffold and the portable *input seam*: a runnable Godot project with one
draggable placeholder that follows the pointer, driven through a swappable
`InputProvider` so the game never knows what hardware it runs on. The game loop
is Phase 2. See [`docs/DESIGN.md`](docs/DESIGN.md) for the full v1 design.

## Layout

```
game/                 # the Godot 4 project (open this folder in Godot)
  project.godot
  input/              # the input seam
    input_provider.gd # InputProvider + Pointer data class
    touch_provider.gd # finger / mouse -> normalized Pointer (first finger wins)
    replay_provider.gd# deterministic playback of a recorded JSONL file
    recorder.gd       # wraps any provider, writes Pointers to user:// as JSONL
  scenes/
    main.tscn/.gd     # picks a provider, drives one draggable placeholder
  config.cfg          # difficulty / layout knobs, no code
  test/               # headless test runner + fixtures
docs/DESIGN.md        # v1 design spec (read this for Phases 2-3)
```

## Open and run in Godot 4

1. Install **Godot 4.4+** (standard editor build — it includes headless mode).
2. In the Godot Project Manager choose **Import**, pick this repo's `game/`
   folder (the one with `project.godot`), and open it.
3. Press **Play** (F5). A colored square appears; press/drag with the mouse or,
   on the Spectre's touchscreen, with a finger, and the square follows and can be
   dragged. (Mouse input is emulated as touch, so the same code path runs either
   way.)

## Run the tests headless

No GUI needed. From the repo root, with the Godot binary on your path as
`godot`:

```
godot --headless --path game --import                       # first time / CI: import assets
godot --headless --path game --script res://test/run_tests.gd
```

Exit code is `0` when all assertions pass, `1` otherwise. The suite covers:
deterministic replay of a 3-point recording, recorder round-trip, the
first-finger-wins rule, and coordinate clamping to 0..1.

> Phase 1 uses a small self-contained test runner rather than GUT, to avoid
> pinning a GUT/Godot version pair before the engine version is fixed on the
> Spectre. The tests map one-to-one onto GUT methods, so adopting GUT later is a
> drop-in.

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
