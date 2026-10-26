# Shopkeeper — Play-test tuning guide

This is the field guide for sitting down with the Spectre and a 4-year-old. The
game's job in this phase isn't to look finished (the art is placeholder) — it's
to find out whether the *loop* is reachable and fun for her hands and attention
span. Everything you'd want to adjust while watching her play is a single value
in `game/config.cfg`; there is no code to touch. Watch, change one knob, play
again.

A reminder before you start: **don't judge the art or sound.** The sprites are
flat labelled shapes and the sounds are placeholder beeps — Phase 3 replaces all
of it. What you're testing is whether she can grab an item, carry it to the
customer, and wants to do it again.

## How to change a knob

1. Open `game/config.cfg` in any text editor (Notepad is fine).
2. Change one value. Keep the quotes where they already have them
   (`interaction_mode="drag"`, `hint_glow="on"`); numbers have no quotes.
3. Save, then press **Play** again in Godot. The new value takes effect on
   restart — nothing is baked into the build.

Change **one thing at a time** between sessions, or you won't know which knob did
it.

## The quick map: what you see → what to turn

| What she does / you notice | Turn this | Which way |
| --- | --- | --- |
| Keeps missing the item, grabs empty space | `hit_box_size` | **up** (e.g. 0.22 → 0.30) |
| Dragging is hard — lifts her finger partway and the item drops | `interaction_mode` | set to `"tap_tap"` (tap item, then tap customer) |
| Gets the item but it won't "arrive" at the customer | `drop_zone_size` | **up** (0.33 → 0.45) |
| Grabs the wrong item next to the one she wanted | `hit_box_size` | **down** a little, or `items_on_shelf` **down** |
| Can't tell which item to fetch | `hint_glow` `"on"`, `hint_rounds` | **up** (glow lasts more rounds) |
| Too easy, breezes through | `items_on_shelf` **up** (→ 8), `hint_glow` `"off"` | harder to find |
| Frustrated, too hard | `items_on_shelf` **down** (→ 3), `hit_box_size` **up** | fewer, bigger targets |
| Loses interest before the end | `rounds_per_session` | **down** (→ 5 or 6) |
| "Again! Again!" | `rounds_per_session` | **up** |
| Memorizes positions, goes robotic | `shuffle_every` | **down** (shuffle more often; 1 = every round) |

## Knob reference

All of these live in `game/config.cfg`. Defaults are what ships; ranges are what
the game accepts (values outside are clamped).

**`interaction_mode`** — `"drag"` (default) or `"tap_tap"`. Drag = touch the item
and slide it onto the customer. Tap-tap = tap the item to pick it up, then tap the
customer to hand it over. Tap-tap is the easier fallback if a continuous drag is
too much coordination for her.

**`hit_box_size`** — default `0.22`, range `0.02`–`1.0`. How big the *grab target*
is around each item, as a fraction of screen width. The picture can be small while
the target is big. This is your main "she can't grab it" dial.

**`drop_zone_size`** — default `0.33`, range `0.05`–`1.0`. How wide the customer
drop strip on the left is. She only has to get the item "over there," not onto a
precise spot — widen this if delivery feels fiddly.

**`rounds_per_session`** — default `10`, minimum `1`. How many successful
deliveries before "closing time." This is the session-length / attention dial.

**`items_on_shelf`** — default `6`, range `2`–`8`. How many items are out at once.
Fewer = easier to find the right one; more = a harder search.

**`hint_glow`** — default `"on"` (`"on"`/`"off"`). Whether the correct item glows
as a hint.

**`hint_rounds`** — default `3`, minimum `0`. How many opening rounds the glow
lasts before the training wheels come off. Raise it if she needs the hint longer;
`0` turns the hint off even when `hint_glow="on"`.

**`shuffle_every`** — default `3`, minimum `0`. Re-shuffle which slot holds which
item every N rounds, so positions don't become rote. `1` = every round; `0` =
never shuffle.

**`voice_speed`** — default `1.0`, range `0.25`–`4.0`. Playback speed for the
spoken order lines. **No audible effect yet** — the voice lines arrive in Phase 3;
this knob is here so it's ready for them.

## A good first session

Start at the shipped defaults — they're already aimed at a 4-year-old. If you want
a gentler very-first run, try:

```
[interaction]
interaction_mode="drag"   ; switch to "tap_tap" if dragging frustrates her
hit_box_size=0.28         ; a bit more forgiving than default
drop_zone_size=0.40       ; generous delivery

[session]
rounds_per_session=6      ; short enough to end on a high note
items_on_shelf=4          ; fewer things to hunt through
hint_glow="on"
hint_rounds=6             ; keep the hint up the whole short session
```

Then, over a few sessions, walk it back toward (and past) the defaults as she gets
it: more items, fewer hint rounds, shorter `shuffle_every`. The goal is that she
always finishes wanting one more customer.

## What you can't tune here (yet)

The real art, the spoken voice lines, and the music/SFX are **Phase 3** — none of
that is adjustable in `config.cfg` because it isn't built yet. If something about
the *feel* can't be fixed with a knob above (for example, the item should animate
differently, or a new interaction is needed), jot it down from the play-test and
it becomes input for a later phase rather than a config change.
