class_name Zones
extends RefCounted

## The shop's geometry, entirely in normalized 0..1 space (never pixels), so the
## layout is identical on the Spectre, a tablet, or a TV. zones.gd knows WHERE
## things are and answers "what is under this pointer?"; it holds no sprites and
## no game state, which is what lets the headless tests exercise it directly.
##
## Layout (0,0 = top-left, 1,1 = bottom-right):
##   - Customer drop zone: the whole left strip, width = drop_zone_size. The
##     customer stands here; dropping an item anywhere in this strip delivers it.
##   - Shelf: a grid of item slots filling the region to the right of the drop
##     zone, across the top ~55% of the screen.
##   - Counter: a band along the bottom center (coins bounce here, till sits here).
##
## A slot's HIT BOX is a square of side hit_box_size (fraction of width) centered
## on the slot, independent of how big the item sprite is drawn — so a 4-year-old
## gets a forgiving target that a config knob can widen.

var slot_count: int = 6
var hit_box_size: float = 0.22       ## fraction of screen width (square side)
var drop_zone_size: float = 0.33     ## fraction of screen width (left strip)

var _slot_centers: PackedVector2Array = PackedVector2Array()

# Shelf region (fractions). Left edge is placed just right of the drop zone.
const _SHELF_TOP := 0.10
const _SHELF_BOTTOM := 0.55
const _SHELF_RIGHT := 0.96
const _SHELF_GAP_FROM_DROP := 0.03   ## breathing room between drop zone and shelf
const _MAX_COLS := 4


func _init(p_slot_count: int = 6, p_hit_box_size: float = 0.22, p_drop_zone_size: float = 0.33) -> void:
	configure(p_slot_count, p_hit_box_size, p_drop_zone_size)


## Recompute the layout. Call again if a knob changes.
func configure(p_slot_count: int, p_hit_box_size: float, p_drop_zone_size: float) -> void:
	slot_count = maxi(1, p_slot_count)
	hit_box_size = clampf(p_hit_box_size, 0.02, 1.0)
	drop_zone_size = clampf(p_drop_zone_size, 0.05, 0.95)
	_rebuild_slots()


func _rebuild_slots() -> void:
	_slot_centers = PackedVector2Array()
	var cols := mini(slot_count, _MAX_COLS)
	var rows := int(ceil(float(slot_count) / float(cols)))

	var shelf_left := drop_zone_size + _SHELF_GAP_FROM_DROP
	var shelf_w: float = maxf(0.001, _SHELF_RIGHT - shelf_left)
	var shelf_h: float = _SHELF_BOTTOM - _SHELF_TOP

	# Centers are placed at column/row midpoints so items are evenly inset from
	# the shelf edges rather than crammed against them.
	for i in slot_count:
		var r := i / cols
		var c := i % cols
		# Last (possibly short) row is centered under the full-width rows.
		var items_in_row := cols
		if r == rows - 1:
			var rem := slot_count - r * cols
			if rem > 0:
				items_in_row = rem
		var cx := shelf_left + shelf_w * (float(c) + 0.5) / float(items_in_row)
		var cy: float = _SHELF_TOP + shelf_h * (float(r) + 0.5) / float(rows) if rows > 1 else _SHELF_TOP + shelf_h * 0.5
		_slot_centers.append(Vector2(cx, cy))


## Center of slot i in 0..1 coordinates.
func slot_center(i: int) -> Vector2:
	if i < 0 or i >= _slot_centers.size():
		return Vector2(-1, -1)
	return _slot_centers[i]


func slot_centers() -> PackedVector2Array:
	return _slot_centers


## The hit-box rect (0..1) for slot i: a square of side hit_box_size centered on
## the slot. Note the side is a fraction of WIDTH applied to both axes, so on a
## 16:9 screen the box is a little taller than wide in pixels — fine for picking.
func slot_rect(i: int) -> Rect2:
	var c := slot_center(i)
	if c.x < 0.0:
		return Rect2(-1, -1, 0, 0)
	var h := hit_box_size * 0.5
	return Rect2(c.x - h, c.y - h, hit_box_size, hit_box_size)


## The customer drop zone: the whole left strip.
func customer_zone() -> Rect2:
	return Rect2(0.0, 0.0, drop_zone_size, 1.0)


## The counter band along the bottom center (right of the drop zone).
func counter_rect() -> Rect2:
	var left := drop_zone_size + _SHELF_GAP_FROM_DROP
	return Rect2(left, 0.82, _SHELF_RIGHT - left, 0.16)


func in_customer_zone(pos: Vector2) -> bool:
	return customer_zone().has_point(pos)


## Which slot's hit box is under pos? Returns the slot index, or -1 for none.
## With big overlapping hit boxes, the NEAREST slot center among those whose box
## contains pos wins, so a drop between two items resolves to the closer one.
func item_at(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in _slot_centers.size():
		if slot_rect(i).has_point(pos):
			var d := _slot_centers[i].distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = i
	return best
