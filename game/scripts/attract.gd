class_name Attract
extends RefCounted

## The attract / "nobody's playing" pause, as pure state so it can be tested with
## no window. After `idle_timeout` seconds with no activity the game drifts into
## attract mode (the shop keeps bobbing and the shopkeeper waves, but no round is
## driven); the first touch resumes instantly. A camera/pose provider later sets
## `present=false` when the room is empty, which trips attract immediately — this
## is the `present`-driven behaviour the DESIGN doc describes, here keyed off the
## Pointer.present flag so touch and camera share one code path.
##
## shop.gd owns an Attract: it calls notice_activity() whenever a Pointer arrives
## (and notice_absent() when present is false), tick(delta) every frame, and reads
## is_attracting() to show/hide the overlay and to gate input.

var idle_timeout: float = 20.0      ## seconds of no activity before attract kicks in

var _idle: float = 0.0
var _attracting: bool = false


func _init(p_idle_timeout: float = 20.0) -> void:
	idle_timeout = maxf(0.5, p_idle_timeout)


## A real interaction happened (a touch sample arrived): reset the idle clock and,
## if we were attracting, resume play. Returns true when it causes a resume, so
## the caller can swallow that first wake-up sample instead of treating it as a
## grab.
func notice_activity() -> bool:
	_idle = 0.0
	if _attracting:
		_attracting = false
		return true
	return false


## The player is gone (camera: present=false). Attract immediately.
func notice_absent() -> void:
	_attracting = true
	_idle = idle_timeout


## Advance the idle clock by delta. Returns the current attracting state.
func tick(delta: float) -> bool:
	if not _attracting:
		_idle += maxf(0.0, delta)
		if _idle >= idle_timeout:
			_attracting = true
	return _attracting


func is_attracting() -> bool:
	return _attracting


## 0..1 progress toward attract (for a subtle fade-in if a view wants it).
func idle_fraction() -> float:
	if _attracting:
		return 1.0
	return clampf(_idle / idle_timeout, 0.0, 1.0)
