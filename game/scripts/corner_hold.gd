class_name CornerHold
extends RefCounted

## The parent-exit gesture, as pure state. A grown-up presses and HOLDS the
## extreme top-right corner for ~3 seconds to quit the game; a 4-year-old playing
## normally never does. It is deliberately invisible — nothing on screen ever
## hints at it (see docs/DESIGN.md: no on-screen text, no menus) — so it can't be
## triggered by accident or discovered as a toy.
##
## Why the top-right corner and not somewhere central: the shelf lives across the
## top ~55% but its hit boxes start at y≈0.10, and items never sit in the extreme
## x≥0.90 / y≤0.08 wedge. So this region is dead space above the shelf — a
## deliberate adult reach, not anywhere a game item can be grabbed. The hold must
## be SUSTAINED and CONTINUOUS: lifting the finger or sliding out of the corner
## resets the timer, so a passing touch can't accumulate toward it.
##
## shop.gd (and the title/closing screens) feed the latest pointer into update()
## every frame; update() returns true on the single frame the hold completes, and
## the caller quits.

var corner_x_min: float = 0.90   ## right edge wedge (fraction of width)
var corner_y_max: float = 0.08   ## top edge wedge (fraction of height)
var hold_seconds: float = 3.0

var _held: float = 0.0
var _completed: bool = false


func _init(p_hold_seconds: float = 3.0) -> void:
	hold_seconds = maxf(0.2, p_hold_seconds)


## Feed the current pointer state for this frame. Returns true EXACTLY on the
## frame the sustained corner hold reaches hold_seconds (once per hold; it won't
## re-fire until the finger lifts and a fresh hold begins).
func update(x: float, y: float, down: bool, delta: float) -> bool:
	if down and _in_corner(x, y):
		if _completed:
			return false                  # already fired this hold; wait for release
		_held += maxf(0.0, delta)
		if _held >= hold_seconds:
			_completed = true
			return true
	else:
		# Finger lifted, or moved out of the corner: reset. This is what makes a
		# brush-past or a near-corner grab-and-go NOT count.
		_held = 0.0
		_completed = false
	return false


func _in_corner(x: float, y: float) -> bool:
	return x >= corner_x_min and y <= corner_y_max


## 0..1 progress of the current hold (unused by the game — handy for tests/debug).
func progress() -> float:
	return clampf(_held / hold_seconds, 0.0, 1.0)
