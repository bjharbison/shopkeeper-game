extends Node2D

## The playable shop: the view and wiring over the pure pieces. It owns a
## ShopModel (the rules), a Zones (the geometry), a Select (the gesture state
## machine), an InputProvider (the finger/replay), an Attract (the idle pause)
## and a CornerHold (the parent-exit gesture), and turns their events into
## sprites, tweens, confetti and sound. All the actual GAME logic lives in those
## pieces so it can be tested headless; this file is deliberately just "draw what
## the model says and animate the transitions".
##
## Everything variable comes from config.cfg via GameConfig — interaction mode,
## hit-box size, drop-zone size, rounds, items on shelf, hints, voice speed,
## attract idle timeout, parent-exit hold — nothing here is a hard-coded number.
##
## Assets are fetched BY SLUG through AssetLibrary, so Phase 3's real art/voice
## is a drop-in (see docs/DESIGN.md "Asset naming contract").
##
## Provider selection mirrors Phase 1: CLI `--provider=touch|replay` (+ `--replay=`),
## plus `--record[=res://..|user://..]` to capture a tuning session. Default is
## touch. Tests inject a provider/config/seed directly before the node enters the
## tree.

const DESIGN := Vector2(1920, 1080)
const CLOSING_SCENE := "res://scenes/closing.tscn"
const ITEM_TEX_SIZE := 256.0
const ITEM_DISPLAY_PX := 180.0
const CUSTOMER_COUNT := 5
const DEFAULT_RECORD_PATH := "user://tuning_session.jsonl"

# --- injected-before-_ready hooks (tests set these; live play leaves them null) ---
var _provider_override: InputProvider = null
var _config_override: GameConfig = null
var _model_seed: int = 0

var _config: GameConfig
var _zones: Zones
var _model: ShopModel
var _select: Select
var _provider: InputProvider
var _provider_kind := "touch"
var _replay_path := ""
var _record_path := ""

var _attract: Attract
var _corner: CornerHold

var _audio: ShopAudio
var _bg: Sprite2D
var _drop_zone: ColorRect
var _customer: Sprite2D
var _order_label: Label
var _till_label: Label
var _coins_root: Node2D
var _confetti: CPUParticles2D
var _shelf_sprites: Array[Sprite2D] = []

# Attract-mode overlay (dim + a waving shopkeeper); hidden during play.
var _attract_overlay: Node2D
var _attract_dim: ColorRect
var _attract_keeper: Sprite2D
var _keeper_home: Vector2 = Vector2.ZERO

var _held_slot := -1
var _busy := false          ## true during the success celebration (ignores input)
var _coins_placed := 0
var _customer_no := 1       ## 1..CUSTOMER_COUNT — which customer is at the counter

# Latest known pointer, kept so the parent-exit hold can accumulate across frames
# where a perfectly still finger emits no new events.
var _last_x := 0.0
var _last_y := 0.0
var _last_down := false


# ---- test injection (call before add_child) ----
func set_provider_override(p: InputProvider) -> void: _provider_override = p
func set_config_override(c: GameConfig) -> void: _config_override = c
func set_model_seed(s: int) -> void: _model_seed = s


func _ready() -> void:
	_config = _config_override if _config_override != null else GameConfig.new().load_from("res://config.cfg")
	_zones = Zones.new(_config.items_on_shelf, _config.hit_box_size, _config.drop_zone_size)
	_model = ShopModel.new(_config, _model_seed)
	_model.start()
	# Zones clamps items_on_shelf identically to the model; keep them in lockstep.
	_zones.configure(_model.items_on_shelf, _config.hit_box_size, _config.drop_zone_size)

	_select = Select.new(_zones, _config.interaction_mode)
	_select.item_grabbed.connect(_on_item_grabbed)
	_select.item_moved.connect(_on_item_moved)
	_select.item_released.connect(_on_item_released)

	_attract = Attract.new(_config.attract_idle_seconds)
	_corner = CornerHold.new(_config.parent_exit_hold_seconds)

	_audio = ShopAudio.new()
	add_child(_audio)
	_audio.config(_config)

	_build_view()
	_present_customer()

	_provider = _provider_override if _provider_override != null else _make_provider()
	if _provider != null:
		_provider.start()
	get_viewport().size_changed.connect(_on_viewport_resized)


# ---------------------------------------------------------------- provider setup
func _make_provider() -> InputProvider:
	_provider_kind = str(ProjectSettings.get_setting("shopkeeper/input/provider", "touch"))
	var want_record := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--provider="):
			_provider_kind = arg.get_slice("=", 1)
		elif arg.begins_with("--replay="):
			_replay_path = arg.get_slice("=", 1)
		elif arg == "--record":
			want_record = true
		elif arg.begins_with("--record="):
			want_record = true
			_record_path = arg.get_slice("=", 1)

	var base: InputProvider
	if _provider_kind == "replay" and not _replay_path.is_empty():
		base = ReplayProvider.new(_replay_path, true)
	else:
		base = TouchProvider.new(Vector2(get_viewport().size))

	# Opt-in recording: wrap the chosen provider in a Recorder (writes JSONL to
	# user:// for later --provider=replay tuning). Never on by default (privacy).
	if want_record:
		if _record_path.is_empty():
			_record_path = DEFAULT_RECORD_PATH
		print("Shopkeeper: recording this session to %s" % _record_path)
		return Recorder.new(base, _record_path)
	return base


func _input(event: InputEvent) -> void:
	# The touch provider may be wrapped in a Recorder; reach through to it.
	var tp := _touch_provider()
	if tp != null:
		tp.feed_event(event)


func _touch_provider() -> TouchProvider:
	if _provider is TouchProvider:
		return _provider as TouchProvider
	if _provider is Recorder and (_provider as Recorder).inner() is TouchProvider:
		return (_provider as Recorder).inner() as TouchProvider
	return null


func _on_viewport_resized() -> void:
	var tp := _touch_provider()
	if tp != null:
		tp.set_viewport_size(Vector2(get_viewport().size))


func _exit_tree() -> void:
	# Flush a Recorder's file (and let any provider release resources) when the
	# scene changes or the game quits.
	if _provider != null:
		_provider.stop()


# ---------------------------------------------------------------- per-frame pump
func _process(delta: float) -> void:
	_pump_provider(delta)
	_animate_idle(delta)
	_update_attract(delta)


func _pump_provider(delta: float) -> void:
	if _provider != null:
		var p: InputProvider.Pointer = _provider.poll()
		var latest: InputProvider.Pointer = null
		while p != null:
			latest = p
			if not p.present:
				_attract.notice_absent()           # camera: room empty → attract now
			else:
				var resumed := _attract.notice_activity()
				# Feed the gesture machine only during live play: not while the
				# success celebration runs, not while attracting, and not on the
				# single sample that just woke us from attract.
				if not _busy and not _attract.is_attracting() and not resumed:
					_select.feed(p)
			p = _provider.poll()
		if latest != null:
			_last_x = latest.x
			_last_y = latest.y
			_last_down = latest.down

	# Parent-exit gesture: a sustained hold in the dead top-right corner. Checked
	# every frame off the last known pointer so a still finger still accumulates.
	# Works from attract mode too (a grown-up can quit the paused screen).
	if _corner.update(_last_x, _last_y, _last_down, delta):
		get_tree().quit()


func _animate_idle(_delta: float) -> void:
	# Gentle bob on shelf items that are sitting in their slots.
	var t := Time.get_ticks_msec() / 1000.0
	for i in _shelf_sprites.size():
		if i == _held_slot:
			continue
		var spr := _shelf_sprites[i]
		var home := _slot_home(i)
		spr.position.y = home.y + sin(t * 2.0 + float(i)) * 6.0


func _update_attract(delta: float) -> void:
	var attracting := _attract.tick(delta)
	if _attract_overlay == null:
		return
	_attract_overlay.visible = attracting
	if attracting:
		# Shopkeeper waves: a gentle bob plus a rocking rotation.
		var t := Time.get_ticks_msec() / 1000.0
		if _attract_keeper != null:
			_attract_keeper.position.y = _keeper_home.y + sin(t * 2.0) * 16.0
			_attract_keeper.rotation = sin(t * 3.2) * 0.22


# ---------------------------------------------------------------- view building
func _build_view() -> void:
	_bg = Sprite2D.new()
	_bg.centered = false
	var bg_tex := AssetLibrary.background("shop")
	if bg_tex != null:
		_bg.texture = bg_tex
	add_child(_bg)

	# Customer drop zone: the whole left strip, softly tinted; brightens on approach.
	var dz := _zones.customer_zone()
	_drop_zone = ColorRect.new()
	_drop_zone.position = Vector2(dz.position.x * DESIGN.x, dz.position.y * DESIGN.y)
	_drop_zone.size = Vector2(dz.size.x * DESIGN.x, dz.size.y * DESIGN.y)
	_drop_zone.color = _dz_color_base()
	_drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drop_zone)

	_customer = Sprite2D.new()
	_customer.position = _customer_pos()
	add_child(_customer)

	_coins_root = Node2D.new()
	add_child(_coins_root)

	_confetti = CPUParticles2D.new()
	_confetti.one_shot = true
	_confetti.emitting = false
	_confetti.amount = 48
	_confetti.lifetime = 1.1
	_confetti.explosiveness = 0.9
	_confetti.direction = Vector2(0, -1)
	_confetti.spread = 180.0
	_confetti.gravity = Vector2(0, 600)
	_confetti.initial_velocity_min = 250.0
	_confetti.initial_velocity_max = 520.0
	_confetti.scale_amount_min = 3.0
	_confetti.scale_amount_max = 6.0
	_confetti.position = _customer_pos()
	add_child(_confetti)

	# Shelf item sprites (one per slot), textured from the model.
	for i in _model.items_on_shelf:
		var spr := Sprite2D.new()
		spr.position = _slot_home(i)
		spr.scale = _item_scale()
		add_child(spr)
		_shelf_sprites.append(spr)
	_refresh_shelf()

	_order_label = Label.new()
	_order_label.add_theme_font_size_override("font_size", 72)
	_order_label.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))
	_order_label.size = Vector2(DESIGN.x, 120)
	_order_label.position = Vector2(0, 24)
	_order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_order_label)

	_till_label = Label.new()
	_till_label.add_theme_font_size_override("font_size", 56)
	_till_label.add_theme_color_override("font_color", Color(0.45, 0.33, 0.08))
	_till_label.position = Vector2(DESIGN.x * 0.78, DESIGN.y * 0.86)
	add_child(_till_label)
	_update_till()

	_build_attract_overlay()


func _build_attract_overlay() -> void:
	_attract_overlay = Node2D.new()
	_attract_overlay.z_index = 100
	_attract_overlay.visible = false
	add_child(_attract_overlay)

	# Soft dim over the whole shop (no text — the waving shopkeeper is the invite,
	# keeping DESIGN's "no on-screen text" rule).
	_attract_dim = ColorRect.new()
	_attract_dim.position = Vector2.ZERO
	_attract_dim.size = DESIGN
	_attract_dim.color = Color(0.0, 0.0, 0.0, 0.32)
	_attract_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attract_overlay.add_child(_attract_dim)

	_attract_keeper = Sprite2D.new()
	var keeper_tex := AssetLibrary.texture("shopkeeper")
	if keeper_tex != null:
		_attract_keeper.texture = keeper_tex
		_attract_keeper.scale = _fit_scale(keeper_tex, 520.0)
	_keeper_home = Vector2(DESIGN.x * 0.5, DESIGN.y * 0.62)
	_attract_keeper.position = _keeper_home
	_attract_overlay.add_child(_attract_keeper)


# ---------------------------------------------------------------- select signals
func _on_item_grabbed(slot: int) -> void:
	_held_slot = slot
	var spr := _shelf_sprites[slot]
	spr.z_index = 10
	_pop(spr)
	_audio.play("pop")


func _on_item_moved(pos: Vector2) -> void:
	if _held_slot < 0:
		return
	_shelf_sprites[_held_slot].position = pos * DESIGN
	_update_drop_highlight(pos)


func _on_item_released(slot: int, delivered: bool) -> void:
	_set_drop_highlight(false, false)
	if slot < 0 or slot >= _shelf_sprites.size():
		_held_slot = -1
		return
	if delivered:
		var result := _model.deliver(slot)
		if result == "correct":
			_busy = true
			_celebrate(slot)
		else:
			_reject(slot)       # wrong item handed over: giggle, return, brighten hint
	else:
		_return_to_slot(slot, true)   # released on nothing: boing home
	_held_slot = -1


# ---------------------------------------------------------------- transitions
func _celebrate(slot: int) -> void:
	var spr := _shelf_sprites[slot]
	spr.z_index = 10
	_audio.play("cheer")
	_audio.play_thanks(_customer_no)
	_confetti.position = _customer_pos()
	_confetti.restart()
	_confetti.emitting = true
	var t := create_tween()
	t.tween_property(spr, "position", _customer_pos(), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(spr, "scale", _item_scale() * 0.6, 0.35)
	t.tween_callback(_on_delivered_landed.bind(slot))


func _on_delivered_landed(slot: int) -> void:
	_audio.play("coin")
	_audio.play("till")
	_spawn_coin()
	_update_till()
	if _model.is_closing():
		SessionState.last_till = _model.till
		get_tree().change_scene_to_file(CLOSING_SCENE)
		return
	# Give the little one a beat to enjoy the coin, then bring the next customer.
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	_shelf_sprites[slot].z_index = 0
	_refresh_shelf()
	_present_customer()
	_busy = false


func _reject(slot: int) -> void:
	_audio.play("giggle")
	_return_to_slot(slot, false)
	_update_hints()   # wrong_attempts > 0 now → the right item glows brighter


func _return_to_slot(slot: int, play_boing: bool) -> void:
	var spr := _shelf_sprites[slot]
	var t := create_tween()
	t.tween_property(spr, "position", _slot_home(slot), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(spr, "scale", _item_scale(), 0.4)
	t.tween_callback(func() -> void: spr.z_index = 0)
	if play_boing:
		_audio.play("boing")


# ---------------------------------------------------------------- customer / shelf
func _present_customer() -> void:
	var idx := _model.round_index % CUSTOMER_COUNT
	_customer_no = idx + 1
	var cust_tex := AssetLibrary.texture("customer_%d" % _customer_no)
	if cust_tex != null:
		_customer.texture = cust_tex
		_customer.scale = _fit_scale(cust_tex, 360.0)
	# Placeholder "voice": show the order as text. TODO(Phase 3): spoken line only.
	_order_label.text = "“%s” please!" % _model.order_item()
	_audio.play_order(_model.order_item(), _customer_no)
	_update_hints()


func _refresh_shelf() -> void:
	for i in _shelf_sprites.size():
		var spr := _shelf_sprites[i]
		var tex := AssetLibrary.texture("item_%s" % _model.shelf_item(i))
		if tex != null:
			spr.texture = tex
		spr.position = _slot_home(i)
		spr.scale = _item_scale()
		spr.z_index = 0
		spr.modulate = Color.WHITE
	_update_hints()


func _update_hints() -> void:
	for i in _shelf_sprites.size():
		if i != _held_slot:
			_shelf_sprites[i].modulate = Color.WHITE
	var os := _model.order_slot()
	if os < 0 or os >= _shelf_sprites.size():
		return
	var strong := _model.wrong_attempts() > 0
	if strong or _model.should_hint():
		_shelf_sprites[os].modulate = Color(1.6, 1.45, 0.5) if strong else Color(1.3, 1.25, 0.85)


# ---------------------------------------------------------------- small helpers
func _slot_home(i: int) -> Vector2:
	return _zones.slot_center(i) * DESIGN


func _customer_pos() -> Vector2:
	var dz := _zones.customer_zone()
	return Vector2((dz.position.x + dz.size.x * 0.5) * DESIGN.x, DESIGN.y * 0.55)


func _item_scale() -> Vector2:
	var s := ITEM_DISPLAY_PX / ITEM_TEX_SIZE
	return Vector2(s, s)


func _fit_scale(tex: Texture2D, target_h: float) -> Vector2:
	if tex == null or tex.get_height() == 0:
		return Vector2.ONE
	var s := target_h / float(tex.get_height())
	return Vector2(s, s)


func _pop(spr: Sprite2D) -> void:
	var base := _item_scale()
	var t := create_tween()
	t.tween_property(spr, "scale", Vector2(base.x * 1.28, base.y * 0.78), 0.08)
	t.tween_property(spr, "scale", Vector2(base.x * 0.9, base.y * 1.12), 0.08)
	t.tween_property(spr, "scale", base, 0.08)


func _spawn_coin() -> void:
	var coin := Sprite2D.new()
	var tex := AssetLibrary.texture("coin")
	if tex != null:
		coin.texture = tex
	var counter := _zones.counter_rect()
	var slot_w := counter.size.x / 10.0
	var cx := (counter.position.x + slot_w * (0.5 + float(_coins_placed % 10))) * DESIGN.x
	var cy := (counter.position.y + counter.size.y * 0.5) * DESIGN.y
	coin.position = Vector2(cx, cy - 220.0)
	_coins_root.add_child(coin)
	_coins_placed += 1
	var t := create_tween()
	t.tween_property(coin, "position", Vector2(cx, cy), 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _update_till() -> void:
	if _till_label != null:
		_till_label.text = "¤ %d" % _model.till   # ¤ generic currency, no reading needed


func _update_drop_highlight(pos: Vector2) -> void:
	var over := pos.x <= _config.drop_zone_size
	var near := pos.x <= _config.drop_zone_size + 0.12
	_set_drop_highlight(over, near)


func _set_drop_highlight(over: bool, near: bool) -> void:
	if _drop_zone == null:
		return
	if over:
		_drop_zone.color = Color(0.4, 0.85, 0.5, 0.45)
	elif near:
		_drop_zone.color = Color(0.4, 0.8, 0.55, 0.28)
	else:
		_drop_zone.color = _dz_color_base()


func _dz_color_base() -> Color:
	return Color(0.95, 0.9, 0.6, 0.12)
