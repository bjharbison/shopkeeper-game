class_name Recorder
extends InputProvider

## Wraps any InputProvider and writes every Pointer it emits to a JSONL file in
## user:// app storage, one Pointer per line. It is itself an InputProvider:
## poll() returns the wrapped provider's sample and records it as a side effect,
## so the game can run through a recorder transparently.
##
## Privacy note (see docs/DESIGN.md): recording is opt-in. The game only wraps a
## provider in a Recorder when explicitly asked (a future --record flag); nothing
## is written to disk otherwise, and recordings stay in local user:// storage.

var _inner: InputProvider = null
var _path: String = ""
var _file: FileAccess = null
var _recording: bool = false


func _init(inner: InputProvider = null, path: String = "user://session.jsonl") -> void:
	_inner = inner
	_path = path


## The wrapped provider (so a caller can reach a TouchProvider to feed it events).
func inner() -> InputProvider:
	return _inner


func start() -> void:
	if _inner != null:
		_inner.start()
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("Recorder: cannot open %s for writing (err %d)" % [_path, FileAccess.get_open_error()])
		_recording = false
	else:
		_recording = true


func poll() -> InputProvider.Pointer:
	if _inner == null:
		return null
	var p: InputProvider.Pointer = _inner.poll()
	if p != null:
		write_pointer(p)
	return p


## Write one Pointer as a JSONL line. Public so tests can drive it directly.
func write_pointer(p: InputProvider.Pointer) -> void:
	if _recording and _file != null:
		_file.store_line(JSON.stringify(InputProvider.pointer_to_dict(p)))


func is_recording() -> bool:
	return _recording


func stop() -> void:
	if _inner != null:
		_inner.stop()
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
	_recording = false
