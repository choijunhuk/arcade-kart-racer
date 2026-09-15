extends GutTest

## Backlog item 4: `net_upnp.gd`'s `release_and_free()` gates the removal
## worker on an explicit `_quitting` flag instead of inferring app teardown
## from tree state (review finding 3 — see net_upnp.gd for the full
## rationale). Split out from test_net_lobby.gd's own UPnP coverage (the
## 400-line rule, same reason test_net_upnp_reachability.gd was split out of
## test_net_internet.gd):
## `test_upnp_mapping_releases_itself_once_the_session_closes` there never
## calls `map_port()`, so `_mapped_port` stays -1 and always takes the fast
## synchronous free path — finding 3's fix had no coverage. Sets
## `_mapped_port`/`_quitting` directly, as `_finish()`/a real close request
## would, instead of running real UPnP network discovery or a real app quit.
##
## Also covers the redesigned worker/result-box handoff (PR #36 cross-model
## review, item 1): worker bodies are `static` and write into a `RefCounted`
## box instead of calling back into this node, so a node freed mid-discovery
## never gets touched off the main thread.

var _upnp: NetUpnp


## Real `_run_removal` blocks on a 3s router discovery timeout; this fake
## reports back immediately so the test proves the removal worker started
## without waiting on real network I/O — this file's sibling tests already
## avoid that (see test_net_lobby.gd's own UPnP coverage). Static, matching
## the real worker's signature: resolved via `Callable(get_script(), ...)`
## (net_upnp.gd's `_worker_callable`), which dispatches through this
## override the same way it would through an instance-method override.
class FakeRemovalUpnp extends NetUpnp:
	static func _run_removal(port: int, box: NetUpnp.ResultBox) -> void:
		box.result = {"kind": "removal", "port": port, "removed": true}
		box.done = true


## Blocks its worker on a `Semaphore` until the test releases it, so a test
## can free the node WHILE the worker is still genuinely running and only
## then let the worker finish — proving `_exit_tree()` detaches instead of
## joining, and that the worker completing afterward never touches the now-
## freed node (it can't: the static body only ever sees `port`/`box`).
## `static var` so the worker (which cannot read instance state) can reach
## it; each test that uses this fake assigns a fresh Semaphore first.
class FakeBlockingUpnp extends NetUpnp:
	static var release_semaphore: Semaphore
	static func _run_removal(port: int, box: NetUpnp.ResultBox) -> void:
		release_semaphore.wait()
		box.result = {"kind": "removal", "port": port, "removed": true}
		box.done = true


## Same semaphore-block trick as `FakeBlockingUpnp`, but for the discovery
## (`map_port()`) worker instead of the removal one — the WM_CLOSE_REQUEST
## tests below need "a live worker still inside discover()", not a removal.
class FakeBlockingMapUpnp extends NetUpnp:
	static var release_semaphore: Semaphore
	static func _run(port: int, box: NetUpnp.ResultBox) -> void:
		release_semaphore.wait()
		box.result = {"kind": "mapping", "status": "mapped", "port": port, "external_ip": "203.0.113.5", "permanent": false}
		box.done = true


func after_each() -> void:
	if is_instance_valid(_upnp):
		_upnp.queue_free()
	_upnp = null
	# Safety net for the WM_CLOSE_REQUEST tests below: restore the real,
	# shared SceneTree's flag even if an assertion failed before its own
	# explicit restore line ran.
	get_tree().auto_accept_quit = true


## Normal session end (BACK/LEAVE RACE/END SESSION, `_quitting` unset): a
## live mapping must still go through the release worker, not just the fast
## synchronous free path.
func test_release_starts_the_removal_worker_on_a_normal_session_end() -> void:
	_upnp = FakeRemovalUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40000
	_upnp.release_and_free()
	assert_eq(_upnp._mapped_port, -1, "a live mapping must be cleared synchronously before the removal worker starts")
	# GUT's wait_for_signal returns false (without failing the test) on its
	# own timeout, so the removal never actually completing would otherwise
	# pass silently — assert the result explicitly.
	var freed_in_time: bool = await wait_for_signal(_upnp.tree_exited, 1.0)
	assert_true(freed_in_time, "release_and_free() must free the node once the removal worker reports back, within the timeout")


## Review finding 3: `release_and_free()`/`map_port()` used to gate on
## `_thread.is_alive()`, which reads false the instant a worker *returns* —
## even before `_process()` has consumed its result and applied
## `_mapped_port`. A release arriving in that exact window used to see
## `_thread.is_alive() == false` and `_mapped_port` still -1, and take the
## fast synchronous free path, abandoning a mapping the router had just
## created. Gating on `_box != null` instead covers "worker running OR its
## result is not yet consumed" — proven here without any real threading: a
## finished-but-unconsumed box with `_thread` left null (already
## demonstrating the old gate would have read "not alive") must still defer.
func test_release_while_a_finished_but_unconsumed_mapping_result_waits_for_it() -> void:
	_upnp = FakeRemovalUpnp.new()
	GameState.add_child(_upnp)
	var box: NetUpnp.ResultBox = NetUpnp.ResultBox.new()
	box.result = {"kind": "mapping", "status": "mapped", "port": 40003, "external_ip": "8.8.8.8"}
	box.done = true
	_upnp._box = box
	_upnp.release_and_free()
	assert_true(_upnp._release_pending, "release while the box is unconsumed must defer instead of abandoning the just-created mapping")
	assert_true(is_instance_valid(_upnp), "must not free synchronously while a mapping result is still unconsumed")
	_upnp._process(0.0) # Consumes the box, applies _mapped_port, then acts on the deferred release.
	var freed_in_time: bool = await wait_for_signal(_upnp.tree_exited, 1.0)
	assert_true(freed_in_time, "the deferred release must still free the node once the mapping result is consumed and the removal worker reports back")


## Quitting: the network round trip must be skipped outright (no worker
## thread started) and the abandoned port logged, instead of a normal
## session end's removal worker.
func test_release_on_quit_frees_with_no_worker_and_warns_the_abandoned_port() -> void:
	_upnp = NetUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40001
	_upnp._quitting = true
	_upnp.release_and_free()
	assert_null(_upnp._thread, "quitting must skip the network round trip: no removal worker thread")
	assert_push_warning("40001")
	await wait_process_frames(1)
	assert_false(is_instance_valid(_upnp), "quitting must still free the node")


## Review finding 3: `_quitting` is asserted directly via the node's own
## `_notification()`, not inferred from tree-exiting order.
func test_wm_close_request_notification_sets_quitting() -> void:
	_upnp = NetUpnp.new()
	GameState.add_child(_upnp)
	assert_false(_upnp._quitting, "sanity: _quitting starts false")
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_true(_upnp._quitting, "NOTIFICATION_WM_CLOSE_REQUEST must set _quitting")


## Review finding 4: a live worker at the moment of the OS close request
## must veto the automatic quit and arm a bounded wait instead, then fire
## exactly once the worker reports back. Uses `NetUpnpQuitWaiter`'s
## injectable `quit_override` (never the real `get_tree().quit()` — that
## would kill the whole test run) with a semaphore-blocked worker, the same
## proven technique `FakeBlockingUpnp` uses below for removal.
func test_wm_close_request_with_a_live_worker_defers_quit_then_fires_once_when_it_finishes() -> void:
	FakeBlockingMapUpnp.release_semaphore = Semaphore.new()
	_upnp = FakeBlockingMapUpnp.new()
	GameState.add_child(_upnp)
	_upnp.map_port(40020)
	assert_not_null(_upnp._thread, "sanity: the discovery worker must have started and still be blocked on the semaphore")
	# A single-element Array, not a plain int (GDScript lambdas capture outer
	# locals by value — mutating a captured int would be invisible out here;
	# see `test_net_lobby.gd`'s own `broadcasts[0] += 1` for the same idiom).
	var quit_calls: Array = [0]
	_upnp._quit_waiter.quit_override = func() -> void: quit_calls[0] += 1
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(_upnp.get_tree().auto_accept_quit, "a live worker must veto the automatic quit so the bounded wait can run first")
	assert_true(_upnp._quit_waiter.is_armed(), "a live worker must arm the bounded wait")
	_upnp._process(0.0)
	_upnp._process(0.0)
	assert_eq(quit_calls[0], 0, "quit must not fire while the worker is still blocked and the deadline has not elapsed")
	FakeBlockingMapUpnp.release_semaphore.post()
	var deadline_ms: int = Time.get_ticks_msec() + 2000
	while quit_calls[0] == 0 and Time.get_ticks_msec() < deadline_ms:
		await wait_process_frames(1)
	assert_eq(quit_calls[0], 1, "the injected quit hook must fire exactly once the worker reports back")
	assert_false(_upnp._quit_waiter.is_armed(), "firing must disarm the wait")
	_upnp.get_tree().auto_accept_quit = true # Restore the real, shared SceneTree's flag for the rest of the suite.


## The mirror image: no worker ever reports back, so the bounded deadline —
## not the worker — must be what fires the quit hook. Forcing the deadline
## into the past (whitebox on `NetUpnpQuitWaiter.deadline_at`) exercises
## exactly the `now >= deadline_at` branch `poll()` checks, without a real
## multi-second sleep.
func test_wm_close_request_quit_deadline_fires_if_the_worker_never_finishes() -> void:
	FakeBlockingMapUpnp.release_semaphore = Semaphore.new()
	_upnp = FakeBlockingMapUpnp.new()
	GameState.add_child(_upnp)
	_upnp.map_port(40021)
	var quit_calls: Array = [0] # See the sibling test above for why not a plain int.
	_upnp._quit_waiter.quit_override = func() -> void: quit_calls[0] += 1
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_true(_upnp._quit_waiter.is_armed(), "sanity: a live worker must arm the wait")
	# 0.0, not `_now() - 1.0`: this early in a single-file test run `_now()`
	# (ticks since engine start) can itself be under a second, and
	# `NetUpnpQuitWaiter.deadline_at` treats any negative value as unarmed —
	# 0.0 is unambiguously "already overdue" without risking that sentinel.
	_upnp._quit_waiter.deadline_at = 0.0
	_upnp._process(0.0)
	assert_eq(quit_calls[0], 1, "the deadline elapsing must fire the quit hook even though the worker never reported back")
	assert_false(_upnp._quit_waiter.is_armed(), "firing must disarm the wait")
	_upnp.get_tree().auto_accept_quit = true # Restore the real, shared SceneTree's flag for the rest of the suite.
	# Let the still-blocked worker finish so its thread doesn't dangle past
	# this test — it can never touch this node either way (static body,
	# RefCounted box), but a thread parked on a Semaphore forever would leak.
	FakeBlockingMapUpnp.release_semaphore.post()
	await wait_process_frames(2)


## No live worker: nothing to defer, so neither the wait nor our own quit
## hook engage at all — the engine's own automatic quit (untouched
## `auto_accept_quit`) is what actually quits immediately in the real app.
func test_wm_close_request_with_no_live_worker_quits_immediately() -> void:
	_upnp = NetUpnp.new()
	GameState.add_child(_upnp)
	var quit_calls: Array = [0] # See the earlier test above for why not a plain int.
	_upnp._quit_waiter.quit_override = func() -> void: quit_calls[0] += 1
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(_upnp._quit_waiter.is_armed(), "no live worker means nothing to wait for")
	assert_true(_upnp.get_tree().auto_accept_quit, "no live worker means the automatic quit must stay armed")
	_upnp._process(0.0)
	assert_eq(quit_calls[0], 0, "no live worker means our own quit hook must never fire — the engine's automatic quit handles it")


## Review finding 1 (the redesigned worker): freeing this node while its
## removal worker is still genuinely running must return `_exit_tree()`
## immediately (detach, never join — the ~11s freeze bug this node's design
## exists to avoid) and must never touch the node once it is freed, even
## once that worker later finishes and writes to its result box.
func test_exit_tree_with_a_live_worker_returns_promptly_without_joining() -> void:
	FakeBlockingUpnp.release_semaphore = Semaphore.new()
	_upnp = FakeBlockingUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40002
	_upnp.release_and_free()
	assert_not_null(_upnp._thread, "sanity: the removal worker must have started and still be blocked on the semaphore")
	var started_ms: int = Time.get_ticks_msec()
	_upnp.queue_free()
	await wait_process_frames(2)
	var elapsed_ms: int = Time.get_ticks_msec() - started_ms
	assert_lt(elapsed_ms, 1000, "_exit_tree() must detach, not join, a still-running worker")
	assert_false(is_instance_valid(_upnp), "the node must free even while its worker is still blocked")
	FakeBlockingUpnp.release_semaphore.post() # Let the blocked worker finish now the node is already gone.
	await wait_process_frames(2) # Give the worker's write-then-return a moment to land.
	var touched_freed_node_errors: Array = []
	for err: GutTrackedError in get_errors():
		if err.is_engine_error():
			err.handled = true
			# Godot's own Thread destructor logs this when a still-running
			# thread is dropped without wait_to_finish() — exactly what
			# `_exit_tree()` intentionally does (its own doc comment: "safely
			# detaches an unfinished thread instead of crashing"), not a sign
			# the freed node was touched.
			if not err.contains_text("thread object"):
				touched_freed_node_errors.append(err)
	assert_eq(touched_freed_node_errors.size(), 0, "the worker finishing after the node is freed must never touch the freed node")
