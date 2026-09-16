extends GutTest

## Phase 18i items 2 and 3: in-app QUIT must go through the same
## NOTIFICATION_WM_CLOSE_REQUEST path a real window-close does (item 2:
## GameState.request_quit()), and that path must itself remove a still-held
## PERMANENT UPnP lease before quitting instead of abandoning it on the
## router forever (item 3: NetUpnp._notification()'s new branch). A new file
## rather than adding to tests/integration/test_net_upnp_release.gd — already
## tight against the 400-line budget — but mirrors its own `_notification()`
## test technique.

var _upnp: NetUpnp

## Reports back immediately instead of running a real 3s UPnP discovery, so
## the permanent-lease test below proves a removal worker actually started
## without any real network I/O — the same technique as
## test_net_upnp_release.gd's own `FakeRemovalUpnp`, duplicated here to keep
## this file self-contained.
class FakeRemovalUpnp extends NetUpnp:
	## Ports the fake "removed", so a test can prove the removal ran at all.
	static var removed_ports: Array[int] = []
	static func _run_removal(port: int, box: NetUpnp.ResultBox) -> void:
		removed_ports.append(port)
		box.result = {"kind": "removal", "port": port, "removed": true}
		box.done = true


## A discovery worker blocked on a Semaphore until the test releases it —
## "still inside discover() when the close request lands" — that then
## reports a PERMANENT lease; removal is instant, as above. Bounded wait,
## so a failed assertion can never park the worker forever (see
## test_net_upnp_release.gd's `_UpnpTestWait.wait_bounded`). Extends NetUpnp
## directly and repeats the removal body: `Callable(get_script(), name)`
## (net_upnp.gd's `_worker_callable`) does not resolve a static method
## inherited from another inner class, so it cannot extend `FakeRemovalUpnp`.
class FakeBlockingPermanentMapUpnp extends NetUpnp:
	static var release_semaphore: Semaphore
	static func _run(port: int, box: NetUpnp.ResultBox) -> void:
		var deadline_ms: int = Time.get_ticks_msec() + 2000
		while not release_semaphore.try_wait() and Time.get_ticks_msec() < deadline_ms:
			OS.delay_msec(5)
		box.result = {"kind": "mapping", "status": "mapped", "port": port, "external_ip": "203.0.113.5", "permanent": true}
		box.done = true
	static func _run_removal(port: int, box: NetUpnp.ResultBox) -> void:
		FakeRemovalUpnp.removed_ports.append(port)
		box.result = {"kind": "removal", "port": port, "removed": true}
		box.done = true


func after_each() -> void:
	if is_instance_valid(_upnp):
		_upnp.queue_free()
	_upnp = null
	GameState.quit_override = Callable()
	get_tree().auto_accept_quit = true
	FakeRemovalUpnp.removed_ports = []
	if FakeBlockingPermanentMapUpnp.release_semaphore != null:
		FakeBlockingPermanentMapUpnp.release_semaphore.post() # Safety net: never leave a worker parked.


## Bounded, wall-clock wait for the node to free itself (a real `process_frame`
## signal, not GUT's simulated frames — see test_net_upnp_release.gd's
## `_UpnpTestWait.wait_for_freed` doc comment); never joins the thread itself.
func _wait_for_freed() -> void:
	var deadline_ms: int = Time.get_ticks_msec() + 2000
	while is_instance_valid(_upnp) and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame


## A live NetUpnp discovery/mapping worker anywhere in the tree must veto
## request_quit()'s own quit, exactly as it already does for a real
## window-close click.
func test_request_quit_defers_while_a_net_upnp_worker_is_still_live() -> void:
	_upnp = NetUpnp.new()
	GameState.add_child(_upnp)
	_upnp._quit_waiter.quit_override = func() -> void: pass # Never trigger the real engine quit from this test.
	_upnp._box = NetUpnp.ResultBox.new() # Simulates a still-running worker (done defaults to false).
	get_tree().auto_accept_quit = true
	var quit_calls: Array = [0] # Array, not a plain int: a lambda captures outer locals by value.
	GameState.quit_override = func() -> void: quit_calls[0] += 1
	GameState.request_quit()
	assert_false(get_tree().auto_accept_quit, "a live NetUpnp worker must veto request_quit()'s own quit")
	assert_eq(quit_calls[0], 0, "request_quit() must not quit while a worker is still live")
	_upnp._box = null # Let after_each's queue_free() take the fast synchronous path.


## With nothing to defer for, request_quit() must quit exactly like pressing
## QUIT always used to.
func test_request_quit_quits_immediately_with_no_live_worker() -> void:
	get_tree().auto_accept_quit = true
	var quit_calls: Array = [0]
	GameState.quit_override = func() -> void: quit_calls[0] += 1
	GameState.request_quit()
	assert_true(get_tree().auto_accept_quit, "nothing vetoed the quit, so the automatic-quit flag must stay untouched")
	assert_eq(quit_calls[0], 1, "request_quit() must quit immediately when nothing defers it")


## Item 3: a still-held PERMANENT lease (never expires/renews on its own)
## must be removed for real on a close request — not just abandoned like a
## finite one — so `auto_accept_quit` is vetoed and a removal worker starts.
func test_close_request_removes_a_permanent_mapping_before_quitting() -> void:
	_upnp = FakeRemovalUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40100
	_upnp._lease_permanent = true # As NetUpnp._finish() records a permanent result.
	var quit_calls: Array = [0] # Array, not a plain int: a lambda captures outer locals by value.
	_upnp._quit_waiter.quit_override = func() -> void: quit_calls[0] += 1 # Review RED-1: never let this reach the real engine quit mid-suite.
	get_tree().auto_accept_quit = true
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_upnp._mapped_port, -1, "the permanent mapping must be cleared synchronously before the removal worker starts")
	assert_false(get_tree().auto_accept_quit, "removing a permanent lease must veto the automatic quit")
	assert_true(_upnp._quit_waiter.is_armed(), "the bounded quit wait must be armed for the removal worker")
	assert_not_null(_upnp._thread, "a removal worker must actually have started")
	# Let the (instant, fake) removal worker actually report back and free the
	# node itself (never manually joining the thread — double-joining a
	# Thread the engine also joins errors).
	await _wait_for_freed()
	assert_false(is_instance_valid(_upnp), "the removal worker finishing must free the node, same as a normal release_and_free()")
	assert_eq(quit_calls[0], 1, "the injected quit hook must fire exactly once the removal worker reports back")
	_upnp = null


## The other half: a FINITE lease is left exactly as before — it expires on
## the router within its own hour, so a close request must not delay
## quitting for it at all.
func test_close_request_leaves_a_finite_mapping_alone() -> void:
	_upnp = FakeRemovalUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40101
	_upnp._lease_expires_at = _upnp._now() + 3600.0 # Finite, not yet expired.
	get_tree().auto_accept_quit = true
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_upnp._mapped_port, 40101, "a finite lease must be left alone, not cleared")
	assert_true(get_tree().auto_accept_quit, "a finite lease must not delay quitting")
	assert_false(_upnp._quit_waiter.is_armed(), "nothing to wait for with a finite lease")
	assert_null(_upnp._thread, "no removal worker for a finite lease")


## Review YELLOW: `_finish()` records `result["permanent"]` in an explicit
## `_lease_permanent`, instead of the close path inferring permanence from
## `_lease_expires_at < 0.0` — which is also what "no mapping held" reads as.
func test_finish_records_the_permanent_flag_explicitly() -> void:
	_upnp = NetUpnp.new()
	GameState.add_child(_upnp)
	_upnp._finish({"kind": "mapping", "status": "mapped", "port": 40105, "external_ip": "8.8.8.8", "permanent": true})
	assert_true(_upnp._lease_permanent, "a permanent result must set _lease_permanent")
	assert_eq(_upnp._quit_waiter.permanent_mapping_port_to_remove_on_close(_upnp._mapped_port, _upnp._lease_permanent), 40105)
	_upnp._finish({"kind": "mapping", "status": "mapped", "port": 40106, "external_ip": "8.8.8.8", "permanent": false})
	assert_false(_upnp._lease_permanent, "a finite result must clear it again")
	assert_eq(_upnp._quit_waiter.permanent_mapping_port_to_remove_on_close(_upnp._mapped_port, _upnp._lease_permanent), -1)


## Review YELLOW: a worker that has FINISHED but whose result is not yet
## consumed (`_box != null and _box.done`) used to fall through both
## `_notification()` branches — the quit went ahead and, if that result was
## a permanent lease, abandoned it. The close request must now defer, let
## `_process()` consume the result, and only then start the removal.
func test_close_request_during_the_finished_but_unconsumed_window_still_removes_a_permanent_lease() -> void:
	_upnp = FakeRemovalUpnp.new()
	GameState.add_child(_upnp)
	var box: NetUpnp.ResultBox = NetUpnp.ResultBox.new() # Finished, never started (same seam as test_net_upnp_release.gd).
	box.result = {"kind": "mapping", "status": "mapped", "port": 40107, "external_ip": "203.0.113.5", "permanent": true}
	box.done = true
	_upnp._box = box
	var quit_calls: Array = [0]
	_upnp._quit_waiter.quit_override = func() -> void: quit_calls[0] += 1
	get_tree().auto_accept_quit = true
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(get_tree().auto_accept_quit, "a finished-but-unconsumed result must still veto the automatic quit")
	assert_true(_upnp._quit_waiter.is_armed())
	_upnp._process(0.0) # Consumes the box: lands the permanent lease, which must start the removal instead of quitting.
	assert_eq(quit_calls[0], 0, "consuming a result that lands a permanent lease must not fire the quit before its removal ran")
	assert_true(_upnp._quit_waiter.is_armed(), "the wait must be re-armed for the removal worker")
	assert_eq(_upnp._mapped_port, -1, "the permanent mapping must be handed to the removal worker")
	assert_not_null(_upnp._thread, "a removal worker must have started")
	await _wait_for_freed()
	assert_false(is_instance_valid(_upnp), "the removal finishing must free the node")
	assert_eq(quit_calls[0], 1, "the quit must fire exactly once, after the removal reported back")
	assert_eq(FakeRemovalUpnp.removed_ports, [40107] as Array[int], "the permanent lease must actually have been removed")
	_upnp = null


## Review YELLOW: discovery still running when the close request lands, and
## its result (consumed during the close wait) is a permanent lease — the
## removal must start before the waiter fires, on a re-armed wait.
func test_discovery_landing_a_permanent_lease_during_the_close_wait_removes_it_before_quitting() -> void:
	FakeBlockingPermanentMapUpnp.release_semaphore = Semaphore.new()
	_upnp = FakeBlockingPermanentMapUpnp.new()
	GameState.add_child(_upnp)
	_upnp.map_port(40108)
	assert_not_null(_upnp._thread, "sanity: the discovery worker must be running (blocked on the semaphore)")
	var quit_calls: Array = [0]
	_upnp._quit_waiter.quit_override = func() -> void: quit_calls[0] += 1
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(get_tree().auto_accept_quit)
	_upnp._process(0.0)
	assert_eq(quit_calls[0], 0, "still discovering: nothing fires yet")
	FakeBlockingPermanentMapUpnp.release_semaphore.post() # Discovery now reports a permanent lease.
	await _wait_for_freed()
	assert_false(is_instance_valid(_upnp), "the close-time removal must run and free the node")
	assert_eq(FakeRemovalUpnp.removed_ports, [40108] as Array[int], "the permanent lease landed mid-close must be removed, not abandoned")
	assert_eq(quit_calls[0], 1, "the quit must fire exactly once, after that removal")
	_upnp = null


## Review YELLOW: once this session's discovery already came back `no_igd`,
## the close-time removal is skipped — its own discovery would only burn
## the timeout again, an exit delay a hostile LAN could otherwise force.
func test_close_request_skips_the_removal_once_discovery_failed_this_session() -> void:
	_upnp = FakeRemovalUpnp.new()
	GameState.add_child(_upnp)
	_upnp._finish({"kind": "mapping", "status": "no_igd"})
	assert_true(_upnp._igd_discovery_failed, "a no_igd result must be remembered")
	_upnp._mapped_port = 40109
	_upnp._lease_permanent = true
	get_tree().auto_accept_quit = true
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_true(get_tree().auto_accept_quit, "no removal, so the automatic quit must stay armed")
	assert_false(_upnp._quit_waiter.is_armed())
	assert_null(_upnp._thread, "no removal worker after a failed discovery")
	assert_eq(FakeRemovalUpnp.removed_ports, [] as Array[int])
