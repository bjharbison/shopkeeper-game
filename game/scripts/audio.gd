class_name ShopAudio
extends Node

## Sound for the shop: two audio buses (SFX, Voice), a small pool of players, and
## a named cue per game event. Every sound is fetched BY SLUG through AssetLibrary,
## so Phase 3's real SFX/voice drop in with zero code change — a real `pop.ogg`
## simply wins over the placeholder `pop.wav`, a `order_apple.ogg` is spoken where
## there was silence (see docs/DESIGN.md "Asset naming contract").
##
## Nothing here hard-codes a path or crashes over a missing file: an absent cue is
## simply silent (AssetLibrary returns null). The Phase 2 placeholder beeps live
## in assets/sfx/*.wav until the Mac pass; voice is silent until order_*/thanks
## files land.
##
## Usage: add as a child node, call config(), then play("pop"),
## play_order(item_id, customer_no), play_thanks(customer_no). shop.gd already
## calls the right cue on every event, so Phase 3 is purely an asset swap.

const _SFX_BUS := "SFX"
const _VOICE_BUS := "Voice"

## Game event → sfx slug (AssetLibrary resolves <slug>.ogg, then <slug>.wav).
const _CUES := {
	"pop": "pop",         # item lifts off the shelf
	"boing": "boing",     # item floats back to its slot
	"cheer": "cheer",     # correct delivery
	"giggle": "giggle",   # wrong item — customer giggles and asks again
	"coin": "coin",       # coin bounces onto the counter
	"till": "till",       # till counter ticks up
}

const _SFX_VOICES := 6   # small pool so overlapping cues don't cut each other off

var _voice_speed: float = 1.0
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _voice_player: AudioStreamPlayer


func config(cfg: GameConfig) -> void:
	if cfg != null:
		_voice_speed = cfg.voice_speed
		if _voice_player != null:
			_voice_player.pitch_scale = _voice_speed


func _ready() -> void:
	for i in _SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = _SFX_BUS if _bus_exists(_SFX_BUS) else "Master"
		add_child(p)
		_sfx_players.append(p)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = _VOICE_BUS if _bus_exists(_VOICE_BUS) else "Master"
	_voice_player.pitch_scale = _voice_speed
	add_child(_voice_player)


## Play a game-event SFX cue by name (see _CUES). No-op if no file is present yet.
func play(cue: String) -> void:
	if not _CUES.has(cue):
		push_warning("ShopAudio: unknown cue '%s'" % cue)
		return
	var stream := AssetLibrary.sfx(_CUES[cue])
	if stream == null:
		return
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = stream
	player.play()


## Speak a customer's order. Prefers a per-customer line if one exists
## (order_<item>_c<n>), else the shared line (order_<item>). Silent until Phase 3
## voice lands — each customer gets its own Kokoro voice there (see DESIGN).
func play_order(item_id: String, customer_no: int = -1) -> void:
	_speak(_voice_slugs("order_" + item_id, customer_no))


## A thank-you after a correct delivery. Per-customer (thanks_c<n>) if present,
## else the shared thanks. A name-baked variant ("thanks, Rose!") can ship as a
## customer-specific file with no code change.
func play_thanks(customer_no: int = -1) -> void:
	_speak(_voice_slugs("thanks", customer_no))


# --- internals --------------------------------------------------------------
func _voice_slugs(base: String, customer_no: int) -> Array[String]:
	# Most specific first: a per-customer file beats the shared one.
	if customer_no >= 1:
		return ["%s_c%d" % [base, customer_no], base]
	return [base]


func _speak(slugs: Array[String]) -> void:
	for slug in slugs:
		var stream := AssetLibrary.voice(slug)
		if stream != null:
			_voice_player.stream = stream
			_voice_player.pitch_scale = _voice_speed
			_voice_player.play()
			return
	# Nothing recorded yet for any candidate slug → stay silent (correct pre-Phase-3).


func _bus_exists(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) != -1
