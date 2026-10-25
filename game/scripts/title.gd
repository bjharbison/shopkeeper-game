extends Node2D

## Title screen. Shows the shop name (the one bit of on-screen text v1 allows)
## and waits for a tap to open the shop. Deliberately tiny; builds its view in
## code so there are no scene node-path dependencies.
##
## TODO(Phase 3): real painted title art + a spoken "Let's play shop!" line.

const DESIGN := Vector2(1920, 1080)
const SHOP_SCENE := "res://scenes/shop.tscn"
const BG_PATH := "res://assets/backgrounds/shop.png"

var _started := false


func _ready() -> void:
	var bg := Sprite2D.new()
	bg.centered = false
	if ResourceLoader.exists(BG_PATH):
		bg.texture = load(BG_PATH)
	add_child(bg)

	var title := Label.new()
	title.text = "Shopkeeper"
	title.add_theme_font_size_override("font_size", 160)
	title.add_theme_color_override("font_color", Color(0.25, 0.18, 0.12))
	title.size = DESIGN
	title.position = Vector2(0, DESIGN.y * 0.28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var hint := Label.new()
	hint.text = "tap to play"
	hint.add_theme_font_size_override("font_size", 64)
	hint.add_theme_color_override("font_color", Color(0.3, 0.25, 0.2))
	hint.size = DESIGN
	hint.position = Vector2(0, DESIGN.y * 0.6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	var go := false
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		go = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		go = true
	elif event is InputEventKey and (event as InputEventKey).pressed:
		go = true
	if go and not _started:
		_started = true
		get_tree().change_scene_to_file(SHOP_SCENE)
