Phase 3 drops the pre-rendered voice lines here (Kokoro MP3/WAV), one voice per
character, loudness-normalized. See docs/DESIGN.md "Asset pipeline".

Expected filenames (read by scripts/audio.gd):
  order_<item>.wav   e.g. order_apple.wav, order_bread.wav, ...  (the customer's request)
  thanks.wav         the shopkeeper / customer thank-you

Until then the game runs silent for voice (SFX use the placeholder beeps in
../sfx/). Nothing here yet — this file just keeps the folder in git.
