class_name SessionState
extends RefCounted

## Tiny carry-between-scenes holder. The only thing the closing screen needs to
## know from the shop is how many coins were earned, and scene changes drop all
## instance state, so it rides here as a static. Kept deliberately minimal — v1
## saves nothing to disk (see docs/DESIGN.md: no saved progress).

static var last_till: int = 0
