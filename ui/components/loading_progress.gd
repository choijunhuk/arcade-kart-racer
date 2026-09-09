class_name LoadingProgress
extends RefCounted

enum State { IDLE, LOADING, READY, FAILED }
var state: State = State.IDLE
var progress: float = 0.0

## Starts a fresh request, resetting stale progress.
func begin() -> void:
	state = State.LOADING
	progress = 0.0

## Accepts monotonic progress; terminal states cannot regress.
func update(status: int, ratio: float) -> void:
	if state != State.LOADING:
		return
	progress = maxf(progress, clampf(ratio, 0.0, 1.0))
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		state = State.READY
		progress = 1.0
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		state = State.FAILED
