class_name InputProvider
extends RefCounted

## Abstract input source for Shopkeeper.
##
## A provider answers one question each frame: where is the tracked pointer, in
## screen-independent (0..1) coordinates, and is it pressed? Concrete providers
## turn a real input into that stream: a finger/mouse now (TouchProvider), a
## recorded file for deterministic tests (ReplayProvider), and a UDP pose stream
## on a future camera console (not in this phase). The game layer only ever sees
## Pointer; it never knows which provider produced it. This is the whole
## portability seam: swap the provider, keep the game.
##
## Coordinates are ALWAYS normalized (0..1), never pixels, so the same scene
## lays out identically on the Spectre, a tablet, or a TV.

## One input sample. Plain data holder — kept free of self-typed methods so it
## parses cleanly as an inner class. Serialization lives on InputProvider below.
class Pointer:
	var t: float = 0.0        ## seconds since the provider started
	var x: float = 0.0        ## 0.0 (left) .. 1.0 (right), normalized
	var y: float = 0.0        ## 0.0 (top) .. 1.0 (bottom), normalized
	var down: bool = false    ## is the pointer pressed / touching
	var present: bool = true  ## is anyone there at all (drives a later attract loop)

	func _init(p_t: float = 0.0, p_x: float = 0.0, p_y: float = 0.0, p_down: bool = false, p_present: bool = true) -> void:
		t = p_t
		x = p_x
		y = p_y
		down = p_down
		present = p_present


## Virtual lifecycle. Subclasses override these three.
func start() -> void:
	pass


## Returns the latest Pointer, or null if there is nothing new this frame.
func poll() -> Pointer:
	return null


func stop() -> void:
	pass


## Serialize one Pointer to a JSONL-friendly dictionary.
static func pointer_to_dict(p: Pointer) -> Dictionary:
	return {
		"t": p.t,
		"x": p.x,
		"y": p.y,
		"down": p.down,
		"present": p.present,
	}


## Build a Pointer from a parsed JSONL dictionary. Missing keys get sane defaults.
static func pointer_from_dict(d: Dictionary) -> Pointer:
	return Pointer.new(
		float(d.get("t", 0.0)),
		float(d.get("x", 0.0)),
		float(d.get("y", 0.0)),
		bool(d.get("down", false)),
		bool(d.get("present", true))
	)
