class_name NetUpnpQuitWaiter
extends RefCounted

## Bounds `NOTIFICATION_WM_CLOSE_REQUEST`'s wait on a live worker thread
## before calling quit anyway (review finding 4), and gives tests an
## injectable seam so a test never has to trigger the real engine
## `SceneTree.quit()` mid-suite.
##
## Split out of `net_upnp.gd` itself to keep it under the project's
## 400-line rule.

## `NetUpnp._now()` timestamp the wait gives up at. -1.0 means unarmed —
## the normal state, and what stays true when there was no live worker to
## wait on in the first place.
var deadline_at: float = -1.0
## Test seam: when valid, `poll()` calls this instead of the real
## `SceneTree.quit()`. Left invalid (the default) in production, so
## production always quits for real.
var quit_override: Callable = Callable()


## Arms a bounded wait ending `timeout_seconds + margin_seconds` from `now`.
## Callers must gate this on "a live worker exists" themselves (see
## `NetUpnp._notification()`) — arming unconditionally would defer quit for
## a worker that was never actually running.
func arm(now: float, timeout_seconds: float, margin_seconds: float) -> void:
	deadline_at = now + timeout_seconds + margin_seconds


func is_armed() -> bool:
	return deadline_at >= 0.0


## Polls the wait: fires exactly once `worker_done` is true or `now` has
## reached the deadline, then disarms so a later call this same tick (or
## the next tick) is a no-op. A no-op while unarmed, so `NetUpnp._process()`
## can call this every tick unconditionally. `worker_done` must reflect a
## live worker's own box (`box != null and box.done`), never merely "there
## is no box" — an absent box is not evidence the worker this wait was
## armed for has finished, only that nothing is being watched right now.
func poll(now: float, worker_done: bool, tree: SceneTree) -> void:
	if not is_armed():
		return
	if not (worker_done or now >= deadline_at):
		return
	deadline_at = -1.0
	if quit_override.is_valid():
		quit_override.call()
	else:
		tree.quit()
