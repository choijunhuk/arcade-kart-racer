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


func after_each() -> void:
	if is_instance_valid(_upnp):
		_upnp.queue_free()
	_upnp = null


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
