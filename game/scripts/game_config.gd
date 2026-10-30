class_name GameConfig
extends RefCounted

## Typed, defaulted reader for config.cfg (see that file for what each knob does).
##
## Everything the game varies by difficulty lives in config.cfg, never in code.
## This class is the one place that turns that file into typed values, so no
## other script touches raw ConfigFile keys or carries a magic number. It is a
## plain RefCounted: load it, read the fields. Tests build one with set_overrides()
## instead of a file, which is how "config knobs actually change behavior" is
## checked headless.

# --- [interaction] ---
var interaction_mode: String = "drag"   ## "drag" | "tap_tap"
var hit_box_size: float = 0.22           ## item pick target, fraction of width
var drop_zone_size: float = 0.33         ## customer drop zone, fraction of width

# --- [session] ---
var rounds_per_session: int = 10
var items_on_shelf: int = 6
var hint_glow: bool = true
var hint_rounds: int = 3
var shuffle_every: int = 3

# --- [voice] ---
var voice_speed: float = 1.0

# --- [session] (attract / exit) ---
var attract_idle_seconds: float = 20.0      ## idle seconds before the attract pause
var parent_exit_hold_seconds: float = 3.0   ## top-right-corner hold to quit (hidden)

const _VALID_MODES := ["drag", "tap_tap"]


## Load from a ConfigFile path (res:// or user://). Unknown/missing keys keep the
## defaults above, so a partial or absent file still yields a playable config.
## Returns self for chaining.
func load_from(path: String = "res://config.cfg") -> GameConfig:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("GameConfig: could not load %s; using defaults." % path)
		return self

	interaction_mode = _as_mode(cfg.get_value("interaction", "interaction_mode", interaction_mode))
	hit_box_size = clampf(float(cfg.get_value("interaction", "hit_box_size", hit_box_size)), 0.02, 1.0)
	drop_zone_size = clampf(float(cfg.get_value("interaction", "drop_zone_size", drop_zone_size)), 0.05, 1.0)

	rounds_per_session = maxi(1, int(cfg.get_value("session", "rounds_per_session", rounds_per_session)))
	items_on_shelf = clampi(int(cfg.get_value("session", "items_on_shelf", items_on_shelf)), 2, 8)
	hint_glow = _as_bool(cfg.get_value("session", "hint_glow", hint_glow))
	hint_rounds = maxi(0, int(cfg.get_value("session", "hint_rounds", hint_rounds)))
	shuffle_every = maxi(0, int(cfg.get_value("session", "shuffle_every", shuffle_every)))
	attract_idle_seconds = clampf(float(cfg.get_value("session", "attract_idle_seconds", attract_idle_seconds)), 3.0, 600.0)
	parent_exit_hold_seconds = clampf(float(cfg.get_value("session", "parent_exit_hold_seconds", parent_exit_hold_seconds)), 1.0, 10.0)

	voice_speed = clampf(float(cfg.get_value("voice", "voice_speed", voice_speed)), 0.25, 4.0)
	return self


## Apply a dictionary of overrides (section-agnostic, keyed by field name). Used
## by tests to prove a single knob changes behavior without writing a file.
func set_overrides(overrides: Dictionary) -> GameConfig:
	for key in overrides:
		match key:
			"interaction_mode": interaction_mode = _as_mode(overrides[key])
			"hit_box_size": hit_box_size = float(overrides[key])
			"drop_zone_size": drop_zone_size = float(overrides[key])
			"rounds_per_session": rounds_per_session = int(overrides[key])
			"items_on_shelf": items_on_shelf = int(overrides[key])
			"hint_glow": hint_glow = _as_bool(overrides[key])
			"hint_rounds": hint_rounds = int(overrides[key])
			"shuffle_every": shuffle_every = int(overrides[key])
			"attract_idle_seconds": attract_idle_seconds = float(overrides[key])
			"parent_exit_hold_seconds": parent_exit_hold_seconds = float(overrides[key])
			"voice_speed": voice_speed = float(overrides[key])
			_: push_warning("GameConfig: unknown override '%s'" % key)
	return self


func _as_mode(v: Variant) -> String:
	var s := str(v).to_lower().strip_edges()
	return s if s in _VALID_MODES else "drag"


## Accepts on/off, true/false, yes/no, 1/0, and real bools.
func _as_bool(v: Variant) -> bool:
	if v is bool:
		return v
	var s := str(v).to_lower().strip_edges()
	return s in ["on", "true", "yes", "1"]
