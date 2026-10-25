extends Node2D

## The playable shop: the view and wiring over the pure pieces. It owns a
## ShopModel (the rules), a Zones (the geometry), a Select (the gesture state
## machine) and an InputProvider (the finger/replay), and turns their events into
## sprites, tweens, confetti and sound. All the actual GAME logic lives in those
## pieces so it can be tested headless; this file is deliberately just "draw what
## the model says and animate the transitions".
##
## Everything variable comes from config.cfg via GameConfig — interaction mode,
## hit-box size, drop-zone size, rounds, items on shelf, hints, voice speed —
## nothing here is a hard-coded difficulty number.
##
## Provider selection mirrors Phase 1: CLI `--provider=touch|replay` (+ `--replay=`)
## overrides the `shopkeeper/input/provider` project setting; default is touch.
## Tests inject a provider/config/seed directly before the node enters the tree.

const DESIGN := Vector2(1920, 1080)
const CLOSING_SCENE := "res://scenes/closing.tscn"
const ITEM_TEX_SIZE := 256.0
const ITEM_DISPLAY_PX := 180.0
const CUSTOMER_COUNT := 5

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

var _audio: ShopAudio
var _bg: Sprite2D
var _drop_zone: ColorRect
var _customer: Sprite2D
var _order_label: Label
var _till_label: Label
var _coins_root: Node2D
var _confetti: CPUParticles2D
var _shelf_sprites: Array[Sprite2D] = []

var _held_slot := -1
var _busy := false          ## true during the success celebration (ignores input)
var _coins_placed := 0


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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--provider="):
			_provider_kind = arg.get_slice("=", 1)
		elif arg.begins_with("--replay="):
			_replay_path = arg.get_slice("=", 1)
	if _provider_kind == "replay" and not _replay_path.is_empty():
		return ReplayProvider.new(_replay_path, true)
	return TouchProvider.new(Vector2(get_viewport().size))


func _input(event: InputEvent) -> void:
	if _provider is TouchProvider:
		(_provider as TouchProvider).feed_event(event)


func _on_viewport_resized() -> void:
	if _provider is TouchProvider:
		(_provider as TouchProvider).set_viewport_size(Vector2(get_viewport().size))


# ---------------------------------------------------------------- per-frame pump
func _process(delta: float) -> void:
	if _provider != null:
		var p: InputProvider.Pointer = _provider.poll()
		while p != null:
			if not _busy:
				_select.feed(p)
			p = _provider.poll()
	_animate_idle(delta)


func _animate_idle(_delta: float) -> void:
	# Gentle bob on shelf items that are sitting in their slots.
	var t := Time.get_ticks_msec() / 1000.0
	for i in _shelf_sprites.size():
		if i == _held_slot:
			continue
		var spr := _shelf_sprites[i]
		var home := _slot_home(i)
		spr.position.y = home.y + sin(t * 2.0 + float(i)) * 6.0


# ---------------------------------------------------------------- view building
func _build_view() -> void:
	_bg = Sprite2D.new()
	_bg.centered = false
	var bg_path := "res://assets/backgrounds/shop.png"
	if ResourceLoader.exists(bg_path):
		_bg.texture = load(bg_path)
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
	_audio.play_thanks()
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
	var cust_path := "res://assets/sprites/customer_%d.png" % (idx + 1)
	if ResourceLoader.exists(cust_path):
		_customer.texture = load(cust_path)
		_customer.scale = _fit_scale(_customer.texture, 360.0)
	# Placeholder "voice": show the order as text. TODO(Phase 3): spoken line only.
	_order_label.text = "“%s” please!" % _model.order_item()
	_audio.play_order(_model.order_item())
	_update_hints()


func _refresh_shelf() -> void:
	for i in _shelf_sprites.size():
		var spr := _shelf_sprites[i]
		var path := "res://assets/sprites/item_%s.png" % _model.shelf_item(i)
		if ResourceLoader.exists(path):
			spr.texture = load(path)
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
	var path := "res://assets/sprites/coin.png"
	if ResourceLoader.exists(path):
		coin.texture = load(path)
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
