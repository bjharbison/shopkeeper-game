class_name AssetLibrary
extends RefCounted

## The asset-swap seam. Every sprite, background, voice line and SFX the game
## draws or plays is fetched BY SLUG through this one class — never by a literal
## path scattered through the view code. That is what makes Phase 3's art/voice
## pass a pure drop-in: Brian generates real files on the Mac (see tools/), drops
## them into game/assets/ under the slug names documented in docs/DESIGN.md, and
## the game uses them with ZERO code change. Until a real file lands, the
## committed placeholder (or a transparent PlaceholderTexture2D / silence) is used
## so the game never errors over a missing asset.
##
## The naming contract (authoritative copy in docs/DESIGN.md "Asset naming
## contract"):
##   sprites/      item_<id>.png   customer_<n>.png   shopkeeper.png   coin.png
##   backgrounds/  shop.png        shop_sunset.png
##   voice/        order_<id>.ogg  thanks.ogg  (optionally *_c<n> per customer)
##   sfx/          pop / boing / cheer / giggle / coin / till  (.ogg)
##
## Real files ship as OGG (Kokoro voice, CC0 SFX); the Phase 2 placeholders are
## WAV. Listing ".ogg" ahead of ".wav" below means a dropped-in real OGG wins
## over the placeholder WAV automatically — the whole point of the seam.

const SPRITES_DIR := "res://assets/sprites/"
const BACKGROUNDS_DIR := "res://assets/backgrounds/"
const VOICE_DIR := "res://assets/voice/"
const SFX_DIR := "res://assets/sfx/"

const SPRITE_EXTS: Array[String] = [".png"]
const BACKGROUND_EXTS: Array[String] = [".png"]
# Real-format-first: a real .ogg beats the placeholder .wav at the same slug.
const AUDIO_EXTS: Array[String] = [".ogg", ".wav"]

# Load each resolved resource once. Static so the whole game (and the tests)
# share one cache; cleared by reset_cache() between tests.
static var _tex_cache: Dictionary = {}
static var _audio_cache: Dictionary = {}
static var _warned_missing: Dictionary = {}


## First existing "<dir><slug><ext>" among `exts`, or "" if none exists.
## Pure path logic (FileAccess existence only, no resource import), so a dropped-in
## file is detected immediately and so the resolver is unit-testable on user://
## without the Godot import step.
static func resolve(dir: String, slug: String, exts: Array) -> String:
	for ext in exts:
		var path: String = dir + slug + ext
		if FileAccess.file_exists(path):
			return path
	return ""


static func sprite_path(slug: String) -> String:
	return resolve(SPRITES_DIR, slug, SPRITE_EXTS)


## A sprite by slug. Returns the committed/real texture when present, otherwise a
## transparent PlaceholderTexture2D so a missing asset can never crash the view.
static func texture(slug: String) -> Texture2D:
	var path := sprite_path(slug)
	var tex := _load_texture(path)
	if tex != null:
		return tex
	# Nothing on disk for this slug (or not imported yet): hand back an empty
	# placeholder rather than null, so Sprite2D.texture is always assignable.
	_warn_once(SPRITES_DIR + slug)
	var ph := PlaceholderTexture2D.new()
	ph.size = Vector2(256, 256)
	return ph


## A background by slug. Returns null when absent (the scenes fall back to a flat
## fill colour, which is the Phase 2 behaviour), so no placeholder box is forced.
static func background(slug: String) -> Texture2D:
	return _load_texture(resolve(BACKGROUNDS_DIR, slug, BACKGROUND_EXTS))


## A voice line by slug (e.g. "order_apple", "thanks"). null == play nothing,
## which is correct until Phase 3 voice lands.
static func voice(slug: String) -> AudioStream:
	return _load_audio(resolve(VOICE_DIR, slug, AUDIO_EXTS))


## An SFX cue by slug (e.g. "pop", "cheer"). null == silent.
static func sfx(slug: String) -> AudioStream:
	return _load_audio(resolve(SFX_DIR, slug, AUDIO_EXTS))


## Drop cached resources (and the one-time-warning set). Tests call this so each
## case starts clean; live play never needs it.
static func reset_cache() -> void:
	_tex_cache.clear()
	_audio_cache.clear()
	_warned_missing.clear()


# --- internals --------------------------------------------------------------
static func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	if not ResourceLoader.exists(path):
		# On disk but not imported yet (a freshly dropped file before the editor
		# re-imports). Treat as absent for this run; the next launch picks it up.
		return null
	var res := ResourceLoader.load(path)
	var tex := res as Texture2D
	if tex != null:
		_tex_cache[path] = tex
	return tex


static func _load_audio(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _audio_cache.has(path):
		return _audio_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path)
	var stream := res as AudioStream
	if stream != null:
		_audio_cache[path] = stream
	return stream


static func _warn_once(key: String) -> void:
	if not _warned_missing.has(key):
		_warned_missing[key] = true
		push_warning("AssetLibrary: no file for '%s' — using a placeholder. Drop a real asset here (see docs/DESIGN.md)." % key)
