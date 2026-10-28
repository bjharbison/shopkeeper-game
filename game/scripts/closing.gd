extends Node2D

## "Closing time" screen: the only ending. A sunset, a thank-you, the number of
## coins earned, and a big REPLAY target to go back to the title and play again.
## No win/lose — just a warm wrap-up after the fixed number of rounds (see
## docs/DESIGN.md: no fail state). The hidden parent-exit corner-hold works here
## too, so a grown-up can quit instead of replaying.
##
## TODO(Phase 3): painted sunset, all the customers waving, a spoken thank-you.

const DESIGN := Vector2(1920, 1080)
const TITLE_SCENE := "res://scenes/title.tscn"

const TARGET_CENTER := Vector2(DESIGN.x * 0.5, DESIGN.y * 0.80)
const TARGET_RADIUS := 130.0

var _done := false
var _corner: CornerHold

var _last_x := 0.0
var _last_y := 0.0
var _last_down := false


func _ready() -> void:
	var bg := Sprite2D.new()
	bg.centered = false
	var bg_tex := AssetLibrary.background("shop_sunset")
	if bg_tex != null:
		bg.texture = bg_tex
	add_child(bg)

	_big_label("Closing time!", 150, 0.20, Color(0.3, 0.17, 0.12))
	_big_label("Thanks for helping at the shop!", 70, 0.40, Color(0.33, 0.22, 0.17))
	_big_label("%d coins earned" % SessionState.last_till, 80, 0.55, Color(0.5, 0.36, 0.1))

	var cfg := GameConfig.new().load_from("res://config.cfg")
	_corner = CornerHold.new(cfg.parent_exit_hold_seconds)


func _process(delta: float) -> void:
	queue_redraw()
	if _corner != null and _corner.update(_last_x, _last_y, _last_down, delta):
		get_tree().quit()


func _draw() -> void:
	# A big pulsing REPLAY target: a disc with two circling arrows (a loop glyph).
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 1.0 + sin(t * 2.4) * 0.05
	var r := TARGET_RADIUS * pulse
	draw_circle(TARGET_CENTER, r + 14.0, Color(1.0, 1.0, 1.0, 0.35))
	draw_circle(TARGET_CENTER, r, Color(0.95, 0.6, 0.25, 0.95))
	# A replay loop: an arc most of the way round, with an arrowhead.
	draw_arc(TARGET_CENTER, r * 0.55, deg_to_rad(-40), deg_to_rad(250), 40, Color(1, 1, 1, 0.98), r * 0.14)
	var head := TARGET_CENTER + Vector2(r * 0.55, 0).rotated(deg_to_rad(-40))
	var head_tri := PackedVector2Array([
		head + Vector2(-r * 0.16, -r * 0.02),
		head + Vector2(r * 0.08, -r * 0.22),
		head + Vector2(r * 0.14, r * 0.06),
	])
	draw_colored_polygon(head_tri, Color(1, 1, 1, 0.98))


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
	if go and not _done and not _in_exit_corner(_last_x, _last_y):
		_done = true
		get_tree().change_scene_to_file(TITLE_SCENE)


func _big_label(text: String, font_size: int, y_frac: float, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.size = DESIGN
	l.position = Vector2(0, DESIGN.y * y_frac)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)


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
