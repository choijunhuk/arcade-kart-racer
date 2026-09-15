extends GutTest

## Backlog item 2's renewal back-off (review finding 1): `_maybe_start_renewal()`
## must not retry a rejected renewal on the very next `_process` tick — see
## `NetUpnpRenewalBackoff`'s own doc comment for why re-arming the lease's
## own expiry on failure (the previous approach) was a no-op. Split out from
## test_net_upnp_release.gd for the 400-line rule, same reason
## test_net_upnp_reachability.gd was split out of test_net_internet.gd.
##
## More renewal coverage (starts-when-due, success extends the lease,
## release-pending mid-renewal) lives here too once the rest of this
## backlog item's fixes land — see this file's own history.

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
