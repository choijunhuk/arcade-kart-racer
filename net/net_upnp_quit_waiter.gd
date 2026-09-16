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


## Backlog item 3: a PERMANENT lease (`lease_expires_at < 0.0`, the same
## sentinel `NetUpnp._finish()` uses for "never expires") never clears itself
## the way a finite one does within its hour, so a normal close would abandon
## it on the router forever. Returns the port `NetUpnp._notification()` must
## remove before quitting, or -1 when there is nothing to do (no mapping, or
## a finite one left to expire on its own with no close-time delay).
func permanent_mapping_port_to_remove_on_close(mapped_port: int, lease_expires_at: float) -> int:
	return mapped_port if mapped_port >= 0 and lease_expires_at < 0.0 else -1


## Polls the wait: fires exactly once `worker_done` is true or `now` has
## reached the deadline, then disarms so a later call this same tick (or
## the next tick) is a no-op. A no-op while unarmed, so `NetUpnp._process()`
## can call this every tick unconditionally. `worker_done` must reflect a
## live worker's own box (`box != null and box.done`), never merely "there
## is no box" — an absent box is not evidence the worker this wait was
## armed for has finished, only that nothing is being watched right now.
## Callers must pass `worker_done = true` at the exact moment they are about
## to consume a finished box (review item 1) — never derived from `box.done`
## alone before `Thread.is_alive()` has confirmed the worker actually
## returned, or this could fire (and disarm) a tick before the result is
## really safe to read.
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


## Called from `NetUpnp._exit_tree()` when this node is being freed while the
## wait is still armed (review item 1): the box-consuming branch of
## `_process()` always calls `poll()` with `worker_done = true` first, so
## normally there is nothing left armed by the time a result frees the node
## — but any *other* free path (a direct `queue_free()`, a scene change,
## `release_and_free()`'s quitting branch) can still land here with the wait
## armed and the deadline not yet reached. Left unfired, `auto_accept_quit`
## would stay false forever with nothing left to ever call `quit()` again,
## silently blocking every later window close. Restores `auto_accept_quit`
## before quitting so a cancelled quit (if the override intercepts it) still
## leaves the tree in its normal state.
func fire_on_exit(tree: SceneTree) -> void:
	if not is_armed():
		return
	deadline_at = -1.0
	# Restored unconditionally, even under `quit_override` (tests use it to
	# assert exactly this without triggering a real engine quit) — the flag
	# itself, not just what fires afterward, is what a later close request
	# depends on.
	tree.auto_accept_quit = true
	if quit_override.is_valid():
		quit_override.call()
	else:
		tree.quit()
