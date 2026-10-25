class_name ReplayProvider
extends InputProvider

## Plays back a JSONL recording (one Pointer per line) deterministically.
##
## Two modes:
##   deterministic (default, use_clock = false) — poll() returns the next sample
##     every call, ignoring the wall clock. Tests get exactly the recorded
##     sequence, in order, with no timing flakiness.
##   clocked (use_clock = true) — poll() returns a sample only once its timestamp
##     has elapsed since start(). Used by main.gd to play a recording back at
##     real speed for a live demo.

var _path: String = ""
var _samples: Array = []           ## Array[InputProvider.Pointer]
var _cursor: int = 0
var _start_ms: int = 0
var _use_clock: bool = false


func _init(path: String = "", use_clock: bool = false) -> void:
	_path = path
	_use_clock = use_clock


## Load samples from a JSONL file. Returns the number of samples loaded.
func load_file(path: String) -> int:
	_path = path
	_samples.clear()
	_cursor = 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ReplayProvider: cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
		return 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			_samples.append(InputProvider.pointer_from_dict(parsed))
	f.close()
	return _samples.size()


## Load samples from in-memory JSONL lines (handy for tests without disk I/O).
func load_lines(lines: PackedStringArray) -> int:
	_samples.clear()
	_cursor = 0
	for line in lines:
		var s := line.strip_edges()
		if s.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(s)
		if typeof(parsed) == TYPE_DICTIONARY:
			_samples.append(InputProvider.pointer_from_dict(parsed))
	return _samples.size()


func start() -> void:
	_cursor = 0
	_start_ms = Time.get_ticks_msec()
	if _path != "" and _samples.is_empty():
		load_file(_path)


func poll() -> InputProvider.Pointer:
	if _cursor >= _samples.size():
		return null
	if _use_clock:
		var elapsed := float(Time.get_ticks_msec() - _start_ms) / 1000.0
		var nxt: InputProvider.Pointer = _samples[_cursor]
		if nxt.t > elapsed:
			return null
		_cursor += 1
		return nxt
	var p: InputProvider.Pointer = _samples[_cursor]
	_cursor += 1
	return p


func count() -> int:
	return _samples.size()


func stop() -> void:
	_cursor = 0
