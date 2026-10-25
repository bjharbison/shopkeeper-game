class_name ShopAudio
extends Node

## Sound hooks for the shop. This phase wires the plumbing — two audio buses
## (SFX, Voice), pooled players, and a named cue for every game event — but the
## sounds themselves are PLACEHOLDERS (short generated beeps, or silence if the
## files are absent). Phase 3 drops real Kokoro voice lines and SFX in beside
## these calls without the game code changing.
##
## Usage: add as a child node, call config(), then play("pop") etc. Every event
## in shop.gd already calls the right cue, so Phase 3 is purely an asset swap.

const _SFX_DIR := "res://assets/sfx/"
const _VOICE_DIR := "res://assets/voice/"
const _SFX_BUS := "SFX"
const _VOICE_BUS := "Voice"

## Game event → sfx filename stem (expects <stem>.wav in assets/sfx/).
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
var _streams: Dictionary = {}          # path -> AudioStream (loaded once)
var _missing_warned: Dictionary = {}   # path -> true (warn once, then stay quiet)


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


## Play a game-event SFX cue by name (see _CUES). No-op (with a one-time warning)
## if the placeholder file isn't present, so the game never errors over audio.
func play(cue: String) -> void:
	if not _CUES.has(cue):
		push_warning("ShopAudio: unknown cue '%s'" % cue)
		return
	var stream := _load(_SFX_DIR + _CUES[cue] + ".wav")
	if stream == null:
		return
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = stream
	player.play()


## Speak a customer's order. Placeholder for now.
## TODO(Phase 3): replace with the pre-rendered Kokoro line per item/character
## (assets/voice/order_<item>.wav), one voice per customer, loudness-normalized.
func play_order(item_id: String) -> void:
	var stream := _load(_VOICE_DIR + "order_" + item_id + ".wav")
	if stream == null:
		return   # silent until Phase 3 voice lines land
	_voice_player.stream = stream
	_voice_player.pitch_scale = _voice_speed
	_voice_player.play()


## TODO(Phase 3): a cheery "thank you!" / name-baked line ("thanks, Rose!").
func play_thanks() -> void:
	var stream := _load(_VOICE_DIR + "thanks.wav")
	if stream == null:
		return
	_voice_player.stream = stream
	_voice_player.play()


func _load(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		if not _missing_warned.has(path):
			_missing_warned[path] = true
			push_warning("ShopAudio: placeholder audio missing (%s) — running silent. Phase 3 adds it." % path)
		return null
	var res := ResourceLoader.load(path)
	var stream := res as AudioStream
	_streams[path] = stream
	return stream


func _bus_exists(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) != -1
