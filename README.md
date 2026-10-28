# Shopkeeper

A touch-based kids' game (built for a 4-year-old), made in **Godot 4 / GDScript**.
A customer walks up, asks for an item; she drags it off the shelf onto the
customer. Correct delivery → cheer, confetti, a coin on the counter, the till
ticks up. Wrong item → the customer giggles and asks again. **No timer, no
penalty, no fail state.** After a fixed number of rounds the shop reaches a warm
"closing time" screen. It ships on an HP Spectre touchscreen laptop first and an
Android app later.

**Status: v1 is code-complete with placeholder art.** Phase 3 (this) added the
packaging and polish around the Phase 2 loop: a title screen with a big start
target, a closing screen with a replay target, a 20-second attract/"come and
play" pause, a hidden parent-exit gesture, landscape lock, the full Mac
asset-generation tooling, and an asset-swap seam so real art/voice drop in with
**zero code change**. The art and sound are still placeholders (flat labelled
shapes + beeps); the remaining v1 work — generating the real art and voice on the
Mac, and a play-test on the Spectre — is on Brian's own hardware. See
[`docs/DESIGN.md`](docs/DESIGN.md) for the full v1 design and the asset naming
contract.

## Layout

```
game/                 # the Godot 4 project (open THIS folder in Godot)
  project.godot       # main scene = scenes/title.tscn; landscape-locked; SFX/Voice buses
  config.cfg          # ALL difficulty / layout knobs, no code (see below)
  audio_bus_layout.tres
  input/              # the portable input seam (Phase 1)
    input_provider.gd # InputProvider + Pointer data class
    touch_provider.gd # finger / mouse -> normalized Pointer (first finger wins)
    replay_provider.gd# deterministic playback of a recorded JSONL file
    recorder.gd       # wraps any provider, writes Pointers to user:// as JSONL
  scripts/            # the game
    game_config.gd    # typed reader for config.cfg (one place, no magic numbers)
    zones.gd          # shelf slots / counter / customer zone as 0..1 rects
    select.gd         # drag + tap-tap gesture state machine over Pointer
    shop_model.gd     # pure rules: shelf, order, till, rounds (tested headless)
    shop.gd           # the playable shop: view + tweens + confetti + audio + attract + exit
    assets.gd         # AssetLibrary — loads every sprite/voice/SFX BY SLUG (the swap seam)
    attract.gd        # the idle "come and play" pause (pure, tested)
    corner_hold.gd    # the hidden parent-exit gesture (pure, tested)
    audio.gd          # SFX/voice by slug (placeholder beeps; real OGG drops in)
    title.gd / closing.gd / session_state.gd
  scenes/
    title.tscn        # shop name + big start target  (main scene)
    shop.tscn         # the game loop
    closing.tscn      # "closing time" wrap-up + replay target
    main.tscn/.gd     # Phase 1 input-seam demo (kept; no longer the entry point)
  assets/
    sprites/ backgrounds/ sfx/ voice/   # PLACEHOLDER art + beeps (see tools/)
  test/               # headless test runner + fixtures
tools/                # Mac-side asset pipeline (NOT run on the console)
  assets.csv          # item/character manifest -> comfy_batch.py
  voice_lines.csv     # voice-line manifest    -> make_voice.py
  comfy_batch.py      # drive local ComfyUI to render sprites/backgrounds
  make_voice.py       # render Kokoro voice lines to OGG
  rembg_all.py        # strip backgrounds + trim the rendered sprites
  make_placeholders.py# regenerate the placeholder art + beeps (Phase 2 stand-in)
  pyproject.toml      # uv; dependencies for tools/ ONLY
docs/
  DESIGN.md           # v1 design spec + asset naming contract
  PLAYTEST.md         # knob-by-knob tuning guide for the Spectre play-test
```

## Run on the Spectre (quickstart)

1. **Install Godot 4.4** — download the standard editor build (it includes the
   headless mode CI uses) from <https://godotengine.org/download>. No other
   dependencies: the game is pure Godot, nothing to `pip install`.
2. **Open the project.** Launch Godot, in the Project Manager click **Import**,
   pick this repo's **`game/`** folder (the one with `project.godot`), and open
   it. Let it finish importing assets the first time.
3. **Press Play (F5).** The title screen appears; tap the big green target (or
   anywhere) to start. Drag an item off the shelf onto the customer on the left
   to serve them. Mouse input is emulated as touch, so the exact code path runs
   on the desktop and on the Spectre's touchscreen.
4. **Full-screen for the real thing.** For a play session, run full-screen
   (Project → Project Settings → Display, or press the OS full-screen key). The
   layout is authored 16:9 and locked to landscape, so it scales to the screen.

**Parent exit:** to quit during play, **press and hold the extreme top-right
corner for about 3 seconds**. It is deliberately invisible (no on-screen
button) so a 4-year-old can't trigger or discover it. Tune the hold time with
`parent_exit_hold_seconds` in `config.cfg`.

**Attract pause:** after ~20 seconds with no touch the game dims and the
shopkeeper waves ("come and play"); the next touch resumes instantly. Tune with
`attract_idle_seconds`.

> **Play-test note:** the whole build is validated headless (see "Run the tests
> headless"), but the *feel* — drag thresholds, hit-box size, pacing for a
> 4-year-old — can only be judged by pressing Play on the touchscreen. That is
> what `config.cfg` is for; [`docs/PLAYTEST.md`](docs/PLAYTEST.md) is a
> knob-by-knob guide (what you see her do → which value to change).

## Change difficulty (`game/config.cfg`)

Everything the game varies lives in `config.cfg`; **nothing is hard-coded**.
Edit a value, restart the game, done. The knobs:

| Section | Key | Default | What it does |
| --- | --- | --- | --- |
| `[interaction]` | `interaction_mode` | `drag` | `drag` (touch & drag onto the customer) or `tap_tap` (tap item, tap customer) |
| `[interaction]` | `hit_box_size` | `0.22` | item pick target, fraction of screen width — **bigger = easier to grab** |
| `[interaction]` | `drop_zone_size` | `0.33` | customer drop-zone width (left strip), fraction of width |
| `[session]` | `rounds_per_session` | `10` | successful deliveries before closing time |
| `[session]` | `items_on_shelf` | `6` | items on the shelf at once (2..8) — more = harder to find |
| `[session]` | `hint_glow` | `on` | glow the correct item as a hint… |
| `[session]` | `hint_rounds` | `3` | …but only for this many opening rounds |
| `[session]` | `shuffle_every` | `3` | reshuffle shelf positions every N rounds |
| `[session]` | `attract_idle_seconds` | `20` | idle seconds before the attract pause |
| `[session]` | `parent_exit_hold_seconds` | `3` | corner-hold seconds to quit (hidden) |
| `[voice]` | `voice_speed` | `1.0` | playback speed of the voice lines |

A gentler first-session starting point and how to walk it back toward the
defaults is in [`docs/PLAYTEST.md`](docs/PLAYTEST.md).

## Record a tuning session and replay it

The input seam records every pointer sample to a JSONL file, so you can capture
a real session on the Spectre and replay it later (deterministically, with no
child in the loop) to tune zone sizes and dwell/drag thresholds.

```sh
# 1. Record. Play a session as normal; the file is written to Godot's user://.
godot --path game -- --record
#    or choose the path:  godot --path game -- --record=user://rose_2026-10-28.jsonl

# 2. Find the file. user:// for this project is:
#    Windows: %APPDATA%\Godot\app_userdata\Shopkeeper\
#    macOS:   ~/Library/Application Support/Godot/app_userdata/Shopkeeper/
#    Linux:   ~/.local/share/godot/app_userdata/Shopkeeper/
#    (default name: tuning_session.jsonl)

# 3. Replay it at real speed into the game (no touchscreen needed).
godot --path game -- --provider=replay --replay=user://rose_2026-10-28.jsonl
```

Recording is **off by default** and only ever writes to local `user://` storage
(a privacy rule from DESIGN) — nothing is captured unless you pass `--record`.
User args come after the `--` separator.

## Regenerate the art and voice (on the Mac)

The committed art/sound under `game/assets/` are **placeholders**. Real assets
are generated on Brian's Mac against the local ComfyUI + Kokoro stack, then
dropped into `game/assets/` under the slug names the game loads — no code
change, because the game resolves every asset by slug through
`scripts/assets.gd` (see [`docs/DESIGN.md`](docs/DESIGN.md) "Asset naming
contract"). These tools **do not run on the console** and are not run in CI.

```sh
cd tools
uv sync                                   # installs the tools' deps (uv)

# 1. Freeze the style. Run the style-anchor pass in ComfyUI first (DESIGN
#    "Asset pipeline"), pick the checkpoint + prompt stem, and paste the stem
#    into STYLE_STEM in comfy_batch.py. Export your workflow as API format to
#    tools/comfy_workflow.api.json.

# 2. Generate sprites + backgrounds from tools/assets.csv into game/assets/.
uv run comfy_batch.py --workflow comfy_workflow.api.json
#    (regenerate one:  uv run comfy_batch.py --workflow ... --only item_apple)

# 3. Cut out backgrounds and trim the sprites (NOT the backgrounds folder).
uv run rembg_all.py ../game/assets/sprites

# 4. Render the voice lines from tools/voice_lines.csv into game/assets/voice/.
uv run make_voice.py

# 5. Open the project in the Godot editor once so it (re)imports the new files,
#    then press Play. The real art/voice replace the placeholders automatically.
```

Real voice/SFX ship as **OGG**; the loader prefers `.ogg` over the placeholder
`.wav` at the same slug, so dropping a real file in simply wins. To rebuild the
placeholders themselves (e.g. after adding an item): `uv run make_placeholders.py`.

## Run the tests headless

No GUI needed. From the repo root, with the Godot binary on your path as
`godot`:

```sh
godot --headless --path game --import                        # first time / CI: import assets
godot --headless --path game --script res://test/run_tests.gd
```

Exit code is `0` when all assertions pass, `1` otherwise (**99 assertions** as of
Phase 3). The suite covers:

- **Phase 1 seam:** deterministic 3-point replay, recorder round-trip, the
  first-finger-wins rule, coordinate clamping to 0..1.
- **Phase 2 loop (driven through `ReplayProvider`):** a full round delivers the
  correct item and ticks the till; a wrong item is not delivered and carries no
  penalty; releasing outside the drop zone returns the item; a ten-round replay
  plays to closing time; `config.cfg` knobs change behavior; the file parses; all
  three scenes build their view without script errors.
- **Phase 3 packaging:** the asset-swap seam (a present slug is used; a missing
  one falls back to a placeholder without crashing; a real `.ogg` is preferred
  over a placeholder `.wav`); the attract pause (trips after the idle timeout,
  resumes on a touch, and trips instantly when a camera reports the room empty);
  and the parent-exit gesture (fires only on a sustained top-right corner hold,
  never on normal mid-screen or shelf play, and resets if the finger leaves the
  corner or lifts).

> The suite uses the repo's own small self-contained runner rather than GUT —
> the Phase 1 choice, kept deliberately: it avoids pinning a GUT/Godot version
> pair before the engine version is fixed on the Spectre, and this cloud build
> environment can't fetch external addons. Each test still maps one-to-one onto a
> GUT test method (`_test_*` == a test, `_check` == an assert), so adopting GUT
> later is a drop-in.

## Swap input providers

The game reads its provider from the `shopkeeper/input/provider` project setting
(`touch` by default). Override on the command line (after a `--` separator):

```sh
godot --path game                                             # touch / mouse (default)
godot --path game -- --provider=replay --replay=res://test/fixtures/replay_3pt.jsonl
godot --path game -- --record                                 # record this session
```

A future camera/pose provider plugs into the same seam without touching the game
code — the `Pointer.present` flag already drives the attract pause, so an empty
room pauses the game the same way an idle timeout does.
