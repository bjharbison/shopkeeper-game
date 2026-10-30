Phase 3 drops the pre-rendered voice lines here, one voice per character,
loudness-normalized. They are generated on Brian's Mac with Kokoro via
tools/make_voice.py (driven by tools/voice_lines.csv) and written as OGG.
See docs/DESIGN.md "Asset pipeline" and "Asset naming contract".

Expected filenames (read by scripts/audio.gd, via AssetLibrary):
  order_<item>.ogg    the customer's request, e.g. order_apple.ogg, order_bread.ogg, ...
  thanks.ogg          the thank-you after a correct delivery
  (optional) order_<item>_c<n>.ogg / thanks_c<n>.ogg  — a per-customer voice
             (customer 1..5); the game prefers it over the shared line if present.

The loader prefers .ogg over .wav for the same slug, so a real OGG dropped in
here automatically wins over any placeholder with zero code change. Until a file
lands, that line is simply silent (SFX still use the placeholder beeps in
../sfx/). Nothing here yet — this file just keeps the folder in git.
