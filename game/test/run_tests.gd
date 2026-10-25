extends SceneTree

## Minimal headless test runner for Phase 1.
##
## Run with:  godot --headless --path game --script res://test/run_tests.gd
## Exit code is 0 when every assertion passes, 1 otherwise, so CI can gate on it.
##
## Why not GUT: GUT is the intended framework (see README/DESIGN), but vendoring
## a specific GUT build couples the repo to one Godot/GUT version pair before the
## engine version is even pinned on the Spectre. This self-contained runner needs
## nothing but Godot 4 and exercises the same four behaviors GUT would. Swapping
## in GUT later is a drop-in: these tests map one-to-one onto GUT test methods.

const InputProviderCls := preload("res://input/input_provider.gd")
const TouchProviderCls := preload("res://input/touch_provider.gd")
const ReplayProviderCls := preload("res://input/replay_provider.gd")
const RecorderCls := preload("res://input/recorder.gd")

const FIXTURE_3PT := "res://test/fixtures/replay_3pt.jsonl"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("== Shopkeeper Phase 1 tests ==")
	_test_replay_three_points()
	_test_recorder_round_trip()
	_test_first_finger_wins()
	_test_coords_in_range()
	print("\n== %d passed, %d failed ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % msg)
	else:
		_fail += 1
		printerr("  FAIL: %s" % msg)
		print("  FAIL: %s" % msg)


# --- replay_provider: plays a known 3-point JSONL in order with right down/x/y -
func _test_replay_three_points() -> void:
	print("\n[replay_provider: 3-point JSONL in order]")
	var rp := ReplayProviderCls.new()
	var n := rp.load_file(FIXTURE_3PT)
	_check(n == 3, "loaded exactly 3 samples (got %d)" % n)
	rp.start()
	var expected := [
		{"x": 0.1, "y": 0.2, "down": false},
		{"x": 0.5, "y": 0.5, "down": true},
		{"x": 0.9, "y": 0.8, "down": true},
	]
	for i in expected.size():
		var p: Variant = rp.poll()
		_check(p != null, "sample %d present" % i)
		if p != null:
			_check(is_equal_approx(p.x, expected[i]["x"]), "sample %d x == %s" % [i, expected[i]["x"]])
			_check(is_equal_approx(p.y, expected[i]["y"]), "sample %d y == %s" % [i, expected[i]["y"]])
			_check(p.down == expected[i]["down"], "sample %d down == %s" % [i, expected[i]["down"]])
	_check(rp.poll() == null, "no 4th sample")


# --- recorder round-trip: record N, read back, assert equality -----------------
func _test_recorder_round_trip() -> void:
	print("\n[recorder: round-trips N pointers]")
	var path := "user://test_rec.jsonl"
	var rec := RecorderCls.new(null, path)
	rec.start()
	_check(rec.is_recording(), "recorder opened file for writing")
	var originals: Array = []
	for i in 5:
		var p := InputProviderCls.Pointer.new(float(i) * 0.1, float(i) / 4.0, 1.0 - float(i) / 4.0, i % 2 == 0, true)
		originals.append(p)
		rec.write_pointer(p)
	rec.stop()

	var rp := ReplayProviderCls.new()
	var n := rp.load_file(path)
	_check(n == originals.size(), "read back %d samples (got %d)" % [originals.size(), n])
	rp.start()
	for i in originals.size():
		var got: Variant = rp.poll()
		var o: Variant = originals[i]
		var ok: bool = got != null \
			and is_equal_approx(got.t, o.t) \
			and is_equal_approx(got.x, o.x) \
			and is_equal_approx(got.y, o.y) \
			and got.down == o.down \
			and got.present == o.present
		_check(ok, "sample %d round-trips (t/x/y/down/present)" % i)


# --- touch_provider: first finger wins -----------------------------------------
func _test_first_finger_wins() -> void:
	print("\n[touch_provider: first finger wins]")
	var tp := TouchProviderCls.new(Vector2(1000, 1000))
	tp.start()

	tp.feed_event(_touch(0, Vector2(100, 100), true))
	var p0: Variant = tp.poll()
	_check(p0 != null and p0.down and is_equal_approx(p0.x, 0.1), "first finger drives pointer")

	tp.feed_event(_touch(1, Vector2(900, 900), true))
	_check(tp.poll() == null, "second finger down is ignored")

	tp.feed_event(_drag(1, Vector2(800, 800)))
	_check(tp.poll() == null, "second finger drag is ignored")

	tp.feed_event(_drag(0, Vector2(500, 500)))
	var pd: Variant = tp.poll()
	_check(pd != null and is_equal_approx(pd.x, 0.5), "first finger drag is accepted")

	tp.feed_event(_touch(0, Vector2(500, 500), false))
	var pu: Variant = tp.poll()
	_check(pu != null and not pu.down, "first finger lift emits a release")

	tp.feed_event(_touch(1, Vector2(900, 900), true))
	var p1: Variant = tp.poll()
	_check(p1 != null and p1.down and is_equal_approx(p1.x, 0.9), "after release, the next finger wins")


# --- coordinates stay within 0..1 ----------------------------------------------
func _test_coords_in_range() -> void:
	print("\n[coordinates clamped to 0..1]")
	var tp := TouchProviderCls.new(Vector2(800, 600))
	tp.start()
	var cases := [Vector2(-50, -50), Vector2(1600, 1200), Vector2(400, 300)]
	for i in cases.size():
		tp.feed_event(_touch(0, cases[i], true))
		var p: Variant = tp.poll()
		var ok: bool = p != null and p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0
		_check(ok, "touch case %d normalized into 0..1" % i)
		tp.feed_event(_touch(0, cases[i], false))
		tp.poll()

	var rp := ReplayProviderCls.new()
	rp.load_file(FIXTURE_3PT)
	rp.start()
	var s: Variant = rp.poll()
	var all_in_range := true
	while s != null:
		if s.x < 0.0 or s.x > 1.0 or s.y < 0.0 or s.y > 1.0:
			all_in_range = false
		s = rp.poll()
	_check(all_in_range, "all replay samples are within 0..1")


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	return e


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	return e
