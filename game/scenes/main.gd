extends Node2D

## Phase 1 entry point.
##
## Picks an InputProvider (touch by default; replay via a project setting or a
## CLI arg) and drives ONE draggable placeholder that follows the Pointer while
## it is down. This is not the game loop (that is Phase 2) — it exists only to
## prove the input seam end to end: the same scene is driven identically by a
## finger and by a recorded file.
##
## Provider selection, in order of precedence:
##   1. CLI: --provider=touch|replay  and  --replay=<path>   (after a `--`)
##   2. Project setting: shopkeeper/input/provider
##   3. Default: touch

const DEFAULT_BOX_PX := 220.0

@onready var _placeholder: ColorRect = $Placeholder

var _provider: InputProvider = null
var _provider_kind: String = "touch"
var _replay_path: String = ""
var _box_size: Vector2 = Vector2(DEFAULT_BOX_PX, DEFAULT_BOX_PX)


func _ready() -> void:
	_load_config()
	_resolve_provider_kind()
	_configure_placeholder()
	_provider = _make_provider(_provider_kind)
	if _provider != null:
		_provider.start()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://config.cfg") == OK:
		var s := float(cfg.get_value("placeholder", "box_size_px", DEFAULT_BOX_PX))
		_box_size = Vector2(s, s)


func _resolve_provider_kind() -> void:
	var setting: Variant = ProjectSettings.get_setting("shopkeeper/input/provider", "touch")
	_provider_kind = str(setting)
	# CLI args after a `--` separator override the project setting.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--provider="):
			_provider_kind = arg.get_slice("=", 1)
		elif arg.begins_with("--replay="):
			_replay_path = arg.get_slice("=", 1)


func _configure_placeholder() -> void:
	_placeholder.size = _box_size
	_placeholder.color = _idle_color()
	_center_placeholder_at(Vector2(get_viewport().size) * 0.5)


func _make_provider(kind: String) -> InputProvider:
	match kind:
		"replay":
			if _replay_path.is_empty():
				push_warning("Replay provider requested but no --replay=<path> given; falling back to touch.")
				return TouchProvider.new(Vector2(get_viewport().size))
			return ReplayProvider.new(_replay_path, true)
		_:
			return TouchProvider.new(Vector2(get_viewport().size))


func _input(event: InputEvent) -> void:
	if _provider is TouchProvider:
		(_provider as TouchProvider).feed_event(event)


func _process(_delta: float) -> void:
	if _provider == null:
		return
	var p: InputProvider.Pointer = _provider.poll()
	while p != null:
		_apply_pointer(p)
		p = _provider.poll()


func _apply_pointer(p: InputProvider.Pointer) -> void:
	if p.down:
		var vp := Vector2(get_viewport().size)
		_center_placeholder_at(Vector2(p.x * vp.x, p.y * vp.y))
		_placeholder.color = _grabbed_color()
	else:
		_placeholder.color = _idle_color()


func _center_placeholder_at(point: Vector2) -> void:
	_placeholder.position = point - _placeholder.size * 0.5


func _on_viewport_resized() -> void:
	if _provider is TouchProvider:
		(_provider as TouchProvider).set_viewport_size(Vector2(get_viewport().size))


func _idle_color() -> Color:
	return Color(0.93, 0.55, 0.22)    # warm orange at rest


func _grabbed_color() -> Color:
	return Color(0.30, 0.78, 0.42)    # green while held
