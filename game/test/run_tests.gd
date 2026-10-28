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

# Phase 2 game-loop pieces.
const GameConfigCls := preload("res://scripts/game_config.gd")
const ZonesCls := preload("res://scripts/zones.gd")
const SelectCls := preload("res://scripts/select.gd")
const ShopModelCls := preload("res://scripts/shop_model.gd")

# Phase 3 pieces.
const AssetLibraryCls := preload("res://scripts/assets.gd")
const AttractCls := preload("res://scripts/attract.gd")
const CornerHoldCls := preload("res://scripts/corner_hold.gd")

const FIXTURE_3PT := "res://test/fixtures/replay_3pt.jsonl"
const SEED := 20261025

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("== Shopkeeper Phase 1 tests ==")
	_test_replay_three_points()
	_test_recorder_round_trip()
	_test_first_finger_wins()
	_test_coords_in_range()

	print("\n== Shopkeeper Phase 2 tests ==")
	_test_full_round_via_replay()
	_test_wrong_item_not_penalized()
	_test_release_outside_returns()
	_test_ten_round_playthrough()
	_test_config_interaction_mode()
	_test_config_hit_box_size()
	_test_config_file_parses()

	print("\n== Shopkeeper Phase 3 tests ==")
	_test_asset_present_and_fallback()
	_test_asset_format_priority()
	_test_attract_pause_and_resume()
	_test_corner_hold_exit()

	await _test_scenes_instantiate()   # needs a real frame for _ready to fire

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


# ======================= Phase 2: game loop ===================================
# These drive the real pieces (Zones, Select, ShopModel) exactly as the shop
# scene does, but with no window — gesture samples arrive through ReplayProvider,
# which is the point of the input seam. Pointer coordinates are computed from the
# live layout so the tests can't drift out of sync with Zones.

# Build a Select of the given mode over `zones`, replay `samples` through it (each
# sample is [x, y, down]) via ReplayProvider, and return what it emitted:
#   { "grabbed": [slot...], "released": [{slot, delivered}...], "moves": int }
func _run_gesture(zones, mode: String, samples: Array) -> Dictionary:
	var sel = SelectCls.new(zones, mode)
	var out := {"grabbed": [], "released": [], "moves": 0}
	sel.item_grabbed.connect(func(i): out["grabbed"].append(i))
	sel.item_released.connect(func(i, d): out["released"].append({"slot": i, "delivered": d}))
	sel.item_moved.connect(func(_p): out["moves"] += 1)

	var lines := PackedStringArray()
	var t := 0.0
	for s in samples:
		lines.append(JSON.stringify({"t": t, "x": s[0], "y": s[1], "down": s[2], "present": true}))
		t += 0.05
	var rp = ReplayProviderCls.new()
	rp.load_lines(lines)
	rp.start()
	var p = rp.poll()
	while p != null:
		sel.feed(p)
		p = rp.poll()
	return out


# A drag round: press the item, drag to the customer, release there.
func _drag_round_samples(item_center: Vector2, customer: Vector2) -> Array:
	var mid := item_center.lerp(customer, 0.5)
	return [
		[item_center.x, item_center.y, true],
		[mid.x, mid.y, true],
		[customer.x, customer.y, true],
		[customer.x, customer.y, false],
	]


func _customer_point(zones) -> Vector2:
	var dz = zones.customer_zone()
	return Vector2(dz.position.x + dz.size.x * 0.5, 0.5)


func _test_full_round_via_replay() -> void:
	print("\n[full round via replay: correct item delivered, till +1]")
	var cfg = GameConfigCls.new()   # defaults: drag mode
	var zones = ZonesCls.new(cfg.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var model = ShopModelCls.new(cfg, SEED)
	model.start()
	zones.configure(model.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var order = model.order_slot()

	var res := _run_gesture(zones, "drag",
		_drag_round_samples(zones.slot_center(order), _customer_point(zones)))

	_check(res["grabbed"] == [order], "grabbed the order item (slot %d)" % order)
	_check(res["released"].size() == 1 and res["released"][0]["delivered"],
		"released over the customer (delivered)")
	_check(res["released"][0]["slot"] == order, "released the item that was grabbed")

	var result := model.deliver(order)
	_check(result == "correct", "model scores it correct")
	_check(model.till == 1, "till incremented to 1 (got %d)" % model.till)
	_check(model.round_index == 1, "advanced to next round")


func _test_wrong_item_not_penalized() -> void:
	print("\n[wrong item: not delivered to till, no penalty, customer repeats]")
	var cfg = GameConfigCls.new()
	var zones = ZonesCls.new(cfg.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var model = ShopModelCls.new(cfg, SEED)
	model.start()
	zones.configure(model.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var order = model.order_slot()
	var wrong = (order + 1) % model.items_on_shelf

	var res := _run_gesture(zones, "drag",
		_drag_round_samples(zones.slot_center(wrong), _customer_point(zones)))
	_check(res["grabbed"] == [wrong], "grabbed a wrong item (slot %d)" % wrong)
	_check(res["released"][0]["delivered"], "was dropped on the customer")

	var result := model.deliver(wrong)
	_check(result == "wrong", "model scores it wrong")
	_check(model.till == 0, "till stays 0 (no penalty, got %d)" % model.till)
	_check(model.round_index == 0, "round does NOT advance")
	_check(model.order_slot() == order, "same customer keeps the same order")
	_check(model.wrong_attempts() == 1, "wrong attempt counted (drives brighter glow)")


func _test_release_outside_returns() -> void:
	print("\n[release outside any zone: item returns, nothing delivered]")
	var cfg = GameConfigCls.new()
	var zones = ZonesCls.new(cfg.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var model = ShopModelCls.new(cfg, SEED)
	model.start()
	zones.configure(model.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var order = model.order_slot()
	var c = zones.slot_center(order)
	# Grab the item, then release back on the shelf (outside the customer zone).
	var samples := [
		[c.x, c.y, true],
		[c.x, c.y, true],
		[c.x, c.y, false],
	]
	var res := _run_gesture(zones, "drag", samples)
	_check(res["grabbed"] == [order], "grabbed the item")
	_check(res["released"].size() == 1 and not res["released"][0]["delivered"],
		"released outside customer zone (NOT delivered)")
	_check(not zones.in_customer_zone(c), "the release point is indeed outside the drop zone")


func _test_ten_round_playthrough() -> void:
	print("\n[ten-round replay: plays through to closing time]")
	var cfg = GameConfigCls.new()   # rounds_per_session = 10
	var zones = ZonesCls.new(cfg.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var model = ShopModelCls.new(cfg, SEED)
	model.start()
	zones.configure(model.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)

	var safety := 0
	while not model.is_closing() and safety < 100:
		var order = model.order_slot()
		var res := _run_gesture(zones, "drag",
			_drag_round_samples(zones.slot_center(order), _customer_point(zones)))
		var ok: bool = res["released"].size() == 1 and res["released"][0]["delivered"] \
			and res["released"][0]["slot"] == order
		if not ok:
			break
		model.deliver(order)
		safety += 1

	_check(model.is_closing(), "reached closing time")
	_check(model.till == cfg.rounds_per_session, "till == %d after playthrough (got %d)"
		% [cfg.rounds_per_session, model.till])
	_check(safety == cfg.rounds_per_session, "took exactly %d rounds (got %d)"
		% [cfg.rounds_per_session, safety])


func _test_config_interaction_mode() -> void:
	print("\n[config: interaction_mode routes drag vs tap_tap differently]")
	var cfg = GameConfigCls.new()
	var zones = ZonesCls.new(cfg.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var model = ShopModelCls.new(cfg, SEED)
	model.start()
	zones.configure(model.items_on_shelf, cfg.hit_box_size, cfg.drop_zone_size)
	var order = model.order_slot()
	var item_c = zones.slot_center(order)
	var cust = _customer_point(zones)

	# One continuous drag (press item, drag to customer, release) ...
	var drag_samples := _drag_round_samples(item_c, cust)

	# ... in DRAG mode: delivers in one gesture.
	var drag_res := _run_gesture(zones, "drag", drag_samples)
	_check(drag_res["released"].size() == 1 and drag_res["released"][0]["delivered"],
		"drag mode: one drag delivers")

	# ... in TAP_TAP mode: the same single gesture only PICKS UP (no delivery);
	# delivery needs a second, separate tap on the customer.
	var tap_res := _run_gesture(zones, "tap_tap", drag_samples)
	_check(tap_res["grabbed"] == [order], "tap_tap mode: first tap picks the item up")
	_check(tap_res["released"].size() == 0, "tap_tap mode: a drag does NOT deliver")

	var two_taps := [
		[item_c.x, item_c.y, true], [item_c.x, item_c.y, false],   # tap item
		[cust.x, cust.y, true], [cust.x, cust.y, false],           # tap customer
	]
	var tap_res2 := _run_gesture(zones, "tap_tap", two_taps)
	_check(tap_res2["released"].size() == 1 and tap_res2["released"][0]["delivered"],
		"tap_tap mode: item-tap then customer-tap delivers")


func _test_config_hit_box_size() -> void:
	print("\n[config: larger hit_box_size widens the pickable area]")
	# One slot, so there are no neighbors to muddy the test.
	var small = ZonesCls.new(1, 0.10, 0.33)
	var big = ZonesCls.new(1, 0.30, 0.33)
	var c = small.slot_center(0)
	var off: Vector2 = c + Vector2(0.08, 0.08)   # ~0.08 away on each axis
	_check(small.item_at(off) == -1, "small hit box: off-center point misses the item")
	_check(big.item_at(off) == 0, "large hit box: same point now hits the item")


func _test_config_file_parses() -> void:
	print("\n[config: res://config.cfg parses, and overrides are actually read]")
	# Regression guard: ConfigFile rejects bare string values, which silently
	# drops the WHOLE file back to defaults. Prove the shipped file parses.
	var cf := ConfigFile.new()
	_check(cf.load("res://config.cfg") == OK, "config.cfg parses cleanly (no bad values)")

	# Prove load_from genuinely reads a file rather than returning defaults: write
	# a config with non-default values to user:// and read them back.
	var tmp := "user://test_config.cfg"
	var w := ConfigFile.new()
	w.set_value("interaction", "interaction_mode", "tap_tap")
	w.set_value("interaction", "hit_box_size", 0.44)
	w.set_value("session", "rounds_per_session", 3)
	w.set_value("session", "hint_glow", "off")
	w.save(tmp)
	var cfg = GameConfigCls.new().load_from(tmp)
	_check(cfg.interaction_mode == "tap_tap", "read interaction_mode from file")
	_check(is_equal_approx(cfg.hit_box_size, 0.44), "read hit_box_size from file")
	_check(cfg.rounds_per_session == 3, "read rounds_per_session from file")
	_check(cfg.hint_glow == false, "read hint_glow=off as false")


# ======================= Phase 3: packaging / polish =========================

# --- asset-swap seam: present asset used; missing slug falls back, no crash ----
func _test_asset_present_and_fallback() -> void:
	print("\n[assets: present slug is used; missing slug falls back to a placeholder]")
	AssetLibraryCls.reset_cache()

	# A committed placeholder exists for this slug → it is resolved and loaded.
	_check(AssetLibraryCls.sprite_path("item_apple") == "res://assets/sprites/item_apple.png",
		"resolves item_apple to its real file")
	var tex = AssetLibraryCls.texture("item_apple")
	_check(tex != null and tex is Texture2D, "present sprite loads as a Texture2D")
	_check(not (tex is PlaceholderTexture2D), "present sprite is the real asset, not the placeholder")

	# A slug with no file resolves to "" and hands back a non-null placeholder,
	# so the view can always assign Sprite2D.texture without crashing.
	_check(AssetLibraryCls.sprite_path("no_such_slug_xyz") == "", "missing slug resolves to empty path")
	var fb = AssetLibraryCls.texture("no_such_slug_xyz")
	_check(fb != null and fb is PlaceholderTexture2D, "missing sprite falls back to a PlaceholderTexture2D (no crash)")

	# A present SFX placeholder (wav) is used; a missing one is silent (null).
	_check(AssetLibraryCls.sfx("pop") != null, "present SFX placeholder (pop.wav) loads")
	_check(AssetLibraryCls.voice("no_such_voice_xyz") == null, "missing voice is silent (null), not an error")


# --- format priority: a real .ogg wins over a placeholder .wav at the same slug -
func _test_asset_format_priority() -> void:
	print("\n[assets: .ogg (real) is preferred over .wav (placeholder) for the same slug]")
	var dir := "user://asset_prio_test/"
	DirAccess.make_dir_recursive_absolute(dir)
	_write_empty(dir + "x.wav")
	_write_empty(dir + "x.ogg")
	var both := AssetLibraryCls.resolve(dir, "x", AssetLibraryCls.AUDIO_EXTS)
	_check(both.ends_with("x.ogg"), "with both present, .ogg (the real format) is chosen")

	DirAccess.remove_absolute(dir + "x.ogg")
	var wav_only := AssetLibraryCls.resolve(dir, "x", AssetLibraryCls.AUDIO_EXTS)
	_check(wav_only.ends_with("x.wav"), "with the .ogg gone, it falls back to the .wav placeholder")

	_check(AssetLibraryCls.resolve(dir, "nope", AssetLibraryCls.AUDIO_EXTS) == "",
		"a slug with no file resolves to empty")
	# tidy up
	DirAccess.remove_absolute(dir + "x.wav")
	DirAccess.remove_absolute(dir)


func _write_empty(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("x")
		f.close()


# --- attract pause: trips after the idle timeout, resumes on activity ----------
func _test_attract_pause_and_resume() -> void:
	print("\n[attract: idle for the timeout pauses; a touch resumes; absent trips instantly]")
	var a = AttractCls.new(1.0)   # 1 second idle timeout
	_check(not a.is_attracting(), "starts in active play")
	_check(not a.tick(0.5), "still playing after 0.5s idle")
	_check(a.tick(0.6), "attract trips once total idle crosses the timeout (1.1s)")
	_check(a.is_attracting(), "now attracting")

	var resumed: bool = a.notice_activity()
	_check(resumed, "a touch while attracting reports a resume (to swallow that sample)")
	_check(not a.is_attracting(), "resumed back to play")
	_check(not a.tick(0.5), "idle clock reset on resume (0.5s < 1.0s)")

	# present=false (camera: nobody there) attracts immediately, before any timeout.
	var b = AttractCls.new(20.0)
	b.notice_absent()
	_check(b.tick(0.0), "present=false trips attract immediately, regardless of timeout")


# --- parent-exit: fires only on a sustained corner hold, never on normal play --
func _test_corner_hold_exit() -> void:
	print("\n[parent-exit: a sustained top-right corner hold fires; normal play does not]")
	# Sustained hold in the extreme corner completes once it reaches the duration.
	var c = CornerHoldCls.new(1.0)
	_check(not c.update(0.97, 0.03, true, 0.5), "0.5s corner hold: not yet")
	_check(c.update(0.97, 0.03, true, 0.6), "crossing 1.0s of corner hold fires")

	# Normal play never reaches it: a long press in the middle of the screen...
	var c2 = CornerHoldCls.new(1.0)
	_check(not c2.update(0.5, 0.5, true, 2.0), "a 2s hold in mid-screen does NOT fire")
	# ...nor a long press on a shelf item (right side but below the corner wedge).
	_check(not c2.update(0.93, 0.30, true, 2.0), "a 2s hold on a shelf item does NOT fire")

	# Sliding out of the corner resets the timer (so a brush-past can't accumulate).
	var c3 = CornerHoldCls.new(1.0)
	_check(not c3.update(0.97, 0.03, true, 0.8), "0.8s in the corner")
	_check(not c3.update(0.5, 0.5, true, 0.8), "moved out: resets, does not fire")
	_check(not c3.update(0.97, 0.03, true, 0.3), "back in corner: only 0.3s accrued, not yet")
	_check(c3.update(0.97, 0.03, true, 0.8), "fires once the fresh hold reaches 1.0s")

	# Lifting the finger resets too.
	var c4 = CornerHoldCls.new(1.0)
	_check(not c4.update(0.97, 0.03, true, 0.9), "0.9s held")
	_check(not c4.update(0.97, 0.03, false, 0.9), "finger lifted: resets")
	_check(not c4.update(0.97, 0.03, true, 0.9), "fresh hold at 0.9s has not fired yet")


func _test_scenes_instantiate() -> void:
	print("\n[scenes: title/shop/closing build without script errors]")
	var insts := []
	for path in ["res://scenes/title.tscn", "res://scenes/shop.tscn", "res://scenes/closing.tscn"]:
		var ps := load(path)
		_check(ps != null, "%s loads as a PackedScene" % path)
		if ps == null:
			continue
		var inst = ps.instantiate()
		_check(inst != null, "%s instantiates" % path)
		get_root().add_child(inst)   # enters tree; _ready runs on the next frame
		insts.append({"path": path, "node": inst})

	# In a SceneTree script, _ready is deferred to the next processed frame.
	await process_frame

	for entry in insts:
		var inst = entry["node"]
		_check(inst.is_node_ready() and inst.get_child_count() > 0,
			"%s built its view on _ready (%d children)" % [entry["path"], inst.get_child_count()])
		get_root().remove_child(inst)
		inst.free()
