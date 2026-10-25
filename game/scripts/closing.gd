extends Node2D

## "Closing time" screen: the only ending. A sunset, a thank-you, the number of
## coins earned, and a tap to go back to the title. No win/lose — just a warm
## wrap-up after the fixed number of rounds (see docs/DESIGN.md: no fail state).
##
## TODO(Phase 3): painted sunset, all the customers waving, a spoken thank-you.

const DESIGN := Vector2(1920, 1080)
const TITLE_SCENE := "res://scenes/title.tscn"
const BG_PATH := "res://assets/backgrounds/shop_sunset.png"

var _done := false


func _ready() -> void:
	var bg := Sprite2D.new()
	bg.centered = false
	if ResourceLoader.exists(BG_PATH):
		bg.texture = load(BG_PATH)
	add_child(bg)

	_big_label("Closing time!", 150, 0.22, Color(0.3, 0.17, 0.12))
	_big_label("Thanks for helping at the shop!", 70, 0.45, Color(0.33, 0.22, 0.17))
	_big_label("%d coins earned" % SessionState.last_till, 80, 0.62, Color(0.5, 0.36, 0.1))
	_big_label("tap to play again", 56, 0.82, Color(0.33, 0.27, 0.22))


func _big_label(text: String, font_size: int, y_frac: float, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.size = DESIGN
	l.position = Vector2(0, DESIGN.y * y_frac)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)


func _unhandled_input(event: InputEvent) -> void:
	var go := false
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		go = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		go = true
	elif event is InputEventKey and (event as InputEventKey).pressed:
		go = true
	if go and not _done:
		_done = true
		get_tree().change_scene_to_file(TITLE_SCENE)
