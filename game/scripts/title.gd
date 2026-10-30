extends Node2D

## Title screen. Shows the shop name (the one bit of on-screen text v1 allows) and
## a big, obvious START target a 4-year-old can't miss — a pulsing circle with a
## play triangle, centred low. A tap anywhere opens the shop (forgiving), but the
## target is where the eye goes. Builds its view in code so there are no scene
## node-path dependencies.
##
## The hidden parent-exit gesture (hold the top-right corner ~3s) also works here,
## so a grown-up can quit from the title without entering a round.
##
## TODO(Phase 3): real painted title art + a spoken "Let's play shop!" line.

const DESIGN := Vector2(1920, 1080)
const SHOP_SCENE := "res://scenes/shop.tscn"

const TARGET_CENTER := Vector2(DESIGN.x * 0.5, DESIGN.y * 0.64)
const TARGET_RADIUS := 190.0

var _started := false
var _corner: CornerHold

# Latest pointer, for the sustained corner-hold exit.
var _last_x := 0.0
var _last_y := 0.0
var _last_down := false


func _ready() -> void:
	var bg := Sprite2D.new()
	bg.centered = false
	var bg_tex := AssetLibrary.background("shop")
	if bg_tex != null:
		bg.texture = bg_tex
	add_child(bg)

	var title := Label.new()
	title.text = "Shopkeeper"
	title.add_theme_font_size_override("font_size", 160)
	title.add_theme_color_override("font_color", Color(0.25, 0.18, 0.12))
	title.size = DESIGN
	title.position = Vector2(0, DESIGN.y * 0.16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var cfg := GameConfig.new().load_from("res://config.cfg")
	_corner = CornerHold.new(cfg.parent_exit_hold_seconds)


func _process(delta: float) -> void:
	queue_redraw()   # keep the target pulsing
	if _corner != null and _corner.update(_last_x, _last_y, _last_down, delta):
		get_tree().quit()


func _draw() -> void:
	# A big pulsing start target: an outer ring, a filled disc, and a play triangle.
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 1.0 + sin(t * 2.4) * 0.05
	var r := TARGET_RADIUS * pulse
	draw_circle(TARGET_CENTER, r + 16.0, Color(1.0, 1.0, 1.0, 0.35))
	draw_circle(TARGET_CENTER, r, Color(0.33, 0.78, 0.42, 0.95))
	# Play triangle, nudged right so it looks centred.
	var s := r * 0.5
	var c := TARGET_CENTER + Vector2(s * 0.18, 0)
	var tri := PackedVector2Array([
		c + Vector2(-s * 0.5, -s * 0.7),
		c + Vector2(-s * 0.5, s * 0.7),
		c + Vector2(s * 0.75, 0),
	])
	draw_colored_polygon(tri, Color(1, 1, 1, 0.98))


func _input(event: InputEvent) -> void:
	_track_pointer(event)


func _unhandled_input(event: InputEvent) -> void:
	var go := false
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		go = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		go = true
	elif event is InputEventKey and (event as InputEventKey).pressed:
		go = true
	# A press in the parent-exit corner must NOT also start the game — let the hold
	# resolve. (A quick tap there still falls through to start, which is fine.)
	if go and not _started and not _in_exit_corner(_last_x, _last_y):
		_started = true
		get_tree().change_scene_to_file(SHOP_SCENE)


func _track_pointer(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		_set_last(te.position, te.pressed)
	elif event is InputEventScreenDrag:
		_set_last((event as InputEventScreenDrag).position, true)


func _set_last(pos: Vector2, down: bool) -> void:
	var vp := Vector2(get_viewport().size)
	if vp.x > 0 and vp.y > 0:
		_last_x = clampf(pos.x / vp.x, 0.0, 1.0)
		_last_y = clampf(pos.y / vp.y, 0.0, 1.0)
	_last_down = down


func _in_exit_corner(x: float, y: float) -> bool:
	return _corner != null and x >= _corner.corner_x_min and y <= _corner.corner_y_max
