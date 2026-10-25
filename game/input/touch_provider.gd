class_name TouchProvider
extends InputProvider

## Turns touch (and mouse, via emulate_touch_from_mouse) into normalized Pointer
## samples.
##
## FIRST FINGER WINS: once a finger is down it owns the pointer. A second touch
## is ignored until the owning finger lifts. A 4-year-old rests a palm or a
## second hand on the screen constantly; this rule keeps that from yanking the
## cursor around.
##
## Events are pushed in via feed_event() (main.gd forwards _input events). poll()
## returns the most recent sample once, then null until the next event — so the
## provider has no dependency on being inside the SceneTree and is unit-testable
## headless by feeding synthetic events.

var _start_ms: int = 0
var _viewport_size: Vector2 = Vector2(1920, 1080)
var _active_index: int = -1               ## finger index that owns the pointer, -1 = none
var _latest: InputProvider.Pointer = null
var _dirty: bool = false


func _init(viewport_size: Vector2 = Vector2(1920, 1080)) -> void:
	set_viewport_size(viewport_size)


func set_viewport_size(size: Vector2) -> void:
	if size.x > 0.0 and size.y > 0.0:
		_viewport_size = size


func start() -> void:
	_start_ms = Time.get_ticks_msec()
	_active_index = -1
	_latest = null
	_dirty = false


## Feed a raw input event. Accepts InputEventScreenTouch / InputEventScreenDrag
## (mouse events become these when emulate_touch_from_mouse is on).
func feed_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		_handle_touch(te.index, te.position, te.pressed)
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		_handle_drag(de.index, de.position)


func _handle_touch(index: int, position: Vector2, pressed: bool) -> void:
	if pressed:
		if _active_index == -1:
			_active_index = index          # first finger wins
			_emit(position, true)
		# a second finger while one is already down: ignored
	else:
		if index == _active_index:
			_emit(position, false)         # owner lifted
			_active_index = -1


func _handle_drag(index: int, position: Vector2) -> void:
	if index == _active_index:
		_emit(position, true)


func _emit(position: Vector2, down: bool) -> void:
	var nx := clampf(position.x / _viewport_size.x, 0.0, 1.0)
	var ny := clampf(position.y / _viewport_size.y, 0.0, 1.0)
	var t := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	_latest = InputProvider.Pointer.new(t, nx, ny, down, true)
	_dirty = true


func poll() -> InputProvider.Pointer:
	if _dirty:
		_dirty = false
		return _latest
	return null


func stop() -> void:
	_active_index = -1
	_dirty = false
