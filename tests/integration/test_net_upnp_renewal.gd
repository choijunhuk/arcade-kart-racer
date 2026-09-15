extends GutTest

## Backlog item 2's renewal back-off (review finding 1): `_maybe_start_renewal()`
## must not retry a rejected renewal on the very next `_process` tick — see
## `NetUpnpRenewalBackoff`'s own doc comment for why re-arming the lease's
## own expiry on failure (the previous approach) was a no-op. Split out from
## test_net_upnp_release.gd for the 400-line rule, same reason
## test_net_upnp_reachability.gd was split out of test_net_internet.gd.
##
## Also covers the rest of the renewal life cycle (review item 5):
## starts-when-due, a success extending the lease and clearing the
## back-off, and `release_and_free()` arriving mid-renewal still removing
## the mapping once that renewal's result is consumed.

var _upnp: NetUpnp


## Static, matching the real worker's signature (mirrors
## test_net_upnp_release.gd's own FakeRemovalUpnp: resolved via
## `Callable(get_script(), ...)`, so this override dispatches the same way a
## real instance-method override would). `static var` lets each test
## configure what the fake "renewal" reports back without any real network
## discovery.
class FakeRenewalUpnp extends NetUpnp:
	static var next_result: Dictionary = {}
	static func _run_renewal(port: int, box: NetUpnp.ResultBox) -> void:
		var result: Dictionary = next_result.duplicate()
		result["kind"] = "renewal"
		result["port"] = port
		box.result = result
		box.done = true


## Blocks the renewal worker on a `Semaphore` until the test releases it, so
## a `release_and_free()` can arrive while the renewal is still genuinely
## in flight (mirrors `test_net_upnp_release.gd`'s own `FakeBlockingUpnp`).
## Also fakes the follow-up removal worker immediately, so the deferred
## release this drives can actually finish and free the node.
class FakeBlockingRenewalUpnp extends NetUpnp:
	static var release_semaphore: Semaphore
	static func _run_renewal(port: int, box: NetUpnp.ResultBox) -> void:
		release_semaphore.wait()
		box.result = {"kind": "renewal", "status": "mapped", "port": port, "external_ip": "8.8.8.8"}
		box.done = true
	static func _run_removal(port: int, box: NetUpnp.ResultBox) -> void:
		box.result = {"kind": "removal", "port": port, "removed": true}
		box.done = true


func after_each() -> void:
	if is_instance_valid(_upnp):
		_upnp.queue_free()
	_upnp = null


## Regression test for review finding 1: the margins used to cancel out, so
## a rejected renewal retried on literally the next tick. Drives
## `_finish_renewal()` directly (as a real failed renewal worker would
## trigger it), then attempts renewal 1s later — still within the back-off
## window, so no worker may start — and again after the back-off elapses,
## where it must.
func test_failed_renewal_backs_off_instead_of_retrying_next_tick() -> void:
	_upnp = FakeRenewalUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40010
	# Already due, without going negative: `_now()` is ticks-since-engine-
	# start, so an offset of -1000s this early in a test run would trip
	# `is_renewal_due()`'s own "expires_at < 0.0 means no lease is held"
	# sentinel — a different, unrelated short-circuit than the one this test
	# means to exercise.
	_upnp._lease_expires_at = _upnp._now()
	_upnp._finish_renewal({"kind": "renewal", "status": "failed"})
	assert_push_warning("40010")
	var now: float = _upnp._now()
	_upnp._maybe_start_renewal(now + 1.0)
	assert_null(_upnp._thread, "a renewal retry within the back-off window must not start a worker")
	FakeRenewalUpnp.next_result = {"status": "mapped", "port": 40010, "external_ip": "8.8.8.8"}
	_upnp._maybe_start_renewal(now + 61.0)
	assert_not_null(_upnp._thread, "a renewal retry past the back-off window must start a worker")
	await wait_process_frames(2)
	assert_null(_upnp._thread, "the fake renewal worker must have finished and been joined")


## Review item 5: a lease not yet inside `RENEW_MARGIN_SECONDS` of expiry
## must not start a renewal worker; one that is must.
func test_renewal_does_not_start_before_due_but_starts_once_due() -> void:
	_upnp = FakeRenewalUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40012
	var now: float = _upnp._now()
	_upnp._lease_expires_at = now + NetUpnp.RENEW_MARGIN_SECONDS + 100.0 # well outside the renewal margin.
	_upnp._maybe_start_renewal(now)
	assert_null(_upnp._thread, "a lease not yet inside the renewal margin must not start a renewal worker")
	_upnp._lease_expires_at = now + 1.0 # now inside the margin: due.
	_upnp._maybe_start_renewal(now)
	assert_not_null(_upnp._thread, "a lease inside the renewal margin must start a renewal worker")
	FakeRenewalUpnp.next_result = {"status": "mapped", "port": 40012, "external_ip": "8.8.8.8"}
	await wait_process_frames(2)
	assert_null(_upnp._thread, "the fake renewal worker must have finished and been joined")


## Review item 5: a successful renewal must push the lease's expiry back out
## by a fresh `LEASE_DURATION_SECONDS` and clear any back-off left over from
## an earlier failure.
func test_successful_renewal_extends_the_lease_and_clears_backoff() -> void:
	_upnp = NetUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40013
	_upnp._renewal_backoff.on_failure(_upnp._now()) # sanity: a prior failure's back-off must clear on success.
	var before: float = _upnp._now()
	_upnp._finish_renewal({"kind": "renewal", "status": "mapped", "port": 40013, "external_ip": "8.8.8.8"})
	var expected_expiry: float = before + float(NetUpnp.LEASE_DURATION_SECONDS)
	assert_almost_eq(_upnp._lease_expires_at, expected_expiry, 1.0, "a successful renewal must extend the lease by a fresh LEASE_DURATION_SECONDS")
	assert_eq(_upnp._renewal_backoff.next_attempt_at, -1.0, "a successful renewal must clear any prior back-off")


## Review item 5: `release_and_free()` arriving while a renewal is still
## genuinely in flight must defer (same `_box != null` gate `map_port()`
## uses), then actually remove the mapping once that renewal's result is
## consumed — not just clear `_release_pending` and stop.
func test_release_pending_during_an_in_flight_renewal_still_removes_once_consumed() -> void:
	FakeBlockingRenewalUpnp.release_semaphore = Semaphore.new()
	_upnp = FakeBlockingRenewalUpnp.new()
	GameState.add_child(_upnp)
	_upnp._mapped_port = 40014
	_upnp._lease_expires_at = _upnp._now()
	_upnp._maybe_start_renewal(_upnp._now())
	assert_not_null(_upnp._thread, "sanity: the renewal worker must have started and still be blocked on the semaphore")
	_upnp.release_and_free()
	assert_true(_upnp._release_pending, "release while a renewal is in flight must defer instead of touching state out from under the worker")
	assert_true(is_instance_valid(_upnp), "must not free synchronously while the renewal result is still unconsumed")
	FakeBlockingRenewalUpnp.release_semaphore.post()
	var freed_in_time: bool = await wait_for_signal(_upnp.tree_exited, 1.0)
	assert_true(freed_in_time, "the deferred release must still free the node once the renewal result lands and the follow-up removal worker reports back")
