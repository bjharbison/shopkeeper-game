class_name Select
extends RefCounted

## The drag-and-drop (and tap-then-tap) state machine. It turns the raw Pointer
## stream into shop-level intent — "she grabbed slot 2", "she let go over the
## customer", "she dropped it on nothing" — and knows nothing about whether an
## item is the RIGHT one. shop.gd owns correctness; select.gd owns gesture.
##
## It consumes Pointer samples via feed(), so it is driven identically by a live
## finger (TouchProvider) and by a recording (ReplayProvider) — which is how the
## headless tests play a whole round without a screen. The "first finger wins"
## rule is not re-implemented here: it already lives in TouchProvider, so the
## stream select sees is already single-pointer.
##
## Two interaction modes, chosen by config (interaction_mode):
##   "drag"    — press an item, drag, release. Release in the customer zone
##               delivers; release anywhere else sends it back to its slot.
##   "tap_tap" — tap an item to pick it up, then tap the customer to deliver
##               (tap another item to switch; tap empty space to put it back).
##
## Signals carry slot indices; shop.gd maps those to items and reacts.

signal item_grabbed(slot_index: int)              ## lifted off the shelf
signal item_moved(pos: Vector2)                   ## held item should follow (0..1)
signal item_released(slot_index: int, delivered: bool)  ## let go; delivered = over customer

const _DRAG := "drag"
const _TAP := "tap_tap"

var _zones: Zones
var _mode: String = _DRAG

var _held: int = -1
var _was_down: bool = false
var _tap_down_pos: Vector2 = Vector2.ZERO


func _init(zones: Zones, mode: String = "drag") -> void:
	_zones = zones
	_mode = _TAP if mode == _TAP else _DRAG


func mode() -> String:
	return _mode


## -1 when nothing is held.
func held_slot() -> int:
	return _held


## Clear any held item without signalling (shop calls this between rounds).
func reset() -> void:
	_held = -1
	_was_down = false


## Feed one Pointer sample. Safe to call every frame with the latest sample.
func feed(p: InputProvider.Pointer) -> void:
	if p == null:
		return
	var pos := Vector2(p.x, p.y)
	if _mode == _DRAG:
		_feed_drag(pos, p.down)
	else:
		_feed_tap(pos, p.down)
	_was_down = p.down


func _feed_drag(pos: Vector2, down: bool) -> void:
	if down and not _was_down:
		_try_grab(pos)                         # press edge → grab
	elif down and _was_down:
		if _held >= 0:
			item_moved.emit(pos)               # drag → follow
	elif (not down) and _was_down:
		if _held >= 0:
			_release_at(pos)                   # release edge → deliver or return


func _feed_tap(pos: Vector2, down: bool) -> void:
	if down and not _was_down:
		_tap_down_pos = pos                    # remember where the tap started
	elif (not down) and _was_down:
		_handle_tap(_tap_down_pos)             # a completed tap
	elif down and _held >= 0:
		item_moved.emit(pos)                   # held item trails the finger between taps


func _handle_tap(pos: Vector2) -> void:
	if _held < 0:
		_try_grab(pos)
		return
	if _zones.in_customer_zone(pos):
		_release_at(pos)                       # second tap on customer → deliver
		return
	var j := _zones.item_at(pos)
	if j >= 0 and j != _held:
		# Tapped a different item: put the current one back, pick up the new one.
		var old := _held
		_held = -1
		item_released.emit(old, false)
		_grab(j, pos)
	else:
		# Tapped the same item again, or empty space: put it back.
		var s := _held
		_held = -1
		item_released.emit(s, false)


func _try_grab(pos: Vector2) -> void:
	if _held >= 0:
		return
	var i := _zones.item_at(pos)
	if i >= 0:
		_grab(i, pos)


func _grab(i: int, pos: Vector2) -> void:
	_held = i
	item_grabbed.emit(i)
	item_moved.emit(pos)


func _release_at(pos: Vector2) -> void:
	var delivered := _zones.in_customer_zone(pos)
	var slot := _held
	_held = -1
	item_released.emit(slot, delivered)
