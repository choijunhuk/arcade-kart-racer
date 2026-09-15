extends GutTest

## Review item 5: pure unit coverage for `NetUpnpRenewalBackoff` (doubling,
## cap, reset-after-success) that the integration-level renewal tests
## (test_net_upnp_renewal.gd) only exercise indirectly through a real worker
## thread, plus the permanent-lease path — a mapping that fell back to a
## permanent (725) lease must never start a renewal worker at all. Neither
## case needs a `Thread`, the scene tree, or GameState, so these stay true
## unit tests split out on their own (the 400-line rule, same reason
## test_net_upnp_reachability.gd was split out of test_net_internet.gd).


func test_initial_back_off_is_not_due_until_its_own_delay_elapses() -> void:
	var backoff: NetUpnpRenewalBackoff = NetUpnpRenewalBackoff.new()
	var now: float = 1000.0
	backoff.on_failure(now)
	assert_eq(backoff.next_attempt_at, now + NetUpnpRenewalBackoff.INITIAL_SECONDS, "the first failure must arm exactly INITIAL_SECONDS out")
	assert_false(backoff.is_due(now + NetUpnpRenewalBackoff.INITIAL_SECONDS - 1.0), "must not be due a moment before its own delay elapses")
	assert_true(backoff.is_due(now + NetUpnpRenewalBackoff.INITIAL_SECONDS), "must be due exactly at its own delay")


func test_back_off_doubles_on_each_consecutive_failure() -> void:
	var backoff: NetUpnpRenewalBackoff = NetUpnpRenewalBackoff.new()
	var now: float = 0.0
	backoff.on_failure(now) # INITIAL_SECONDS
	backoff.on_failure(now) # 2x INITIAL_SECONDS
	assert_eq(backoff.next_attempt_at, now + NetUpnpRenewalBackoff.INITIAL_SECONDS * 2.0, "a second consecutive failure must double the wait")
	backoff.on_failure(now) # 4x INITIAL_SECONDS
	assert_eq(backoff.next_attempt_at, now + NetUpnpRenewalBackoff.INITIAL_SECONDS * 4.0, "a third consecutive failure must double it again")


func test_back_off_is_capped_at_max_seconds() -> void:
	var backoff: NetUpnpRenewalBackoff = NetUpnpRenewalBackoff.new()
	var now: float = 0.0
	for _i: int in range(10): # far enough to have long since crossed MAX_SECONDS.
		backoff.on_failure(now)
	assert_eq(backoff.next_attempt_at, now + NetUpnpRenewalBackoff.MAX_SECONDS, "repeated failures must never wait longer than MAX_SECONDS")


func test_success_clears_the_back_off_and_resets_the_retry_ladder() -> void:
	var backoff: NetUpnpRenewalBackoff = NetUpnpRenewalBackoff.new()
	var now: float = 0.0
	backoff.on_failure(now)
	backoff.on_failure(now) # doubled once: next failure would be 4x, not INITIAL_SECONDS.
	backoff.on_success()
	assert_eq(backoff.next_attempt_at, -1.0, "success must clear the back-off outright")
	assert_true(backoff.is_due(now), "no back-off in effect means always due")
	backoff.on_failure(now)
	assert_eq(backoff.next_attempt_at, now + NetUpnpRenewalBackoff.INITIAL_SECONDS, "the retry ladder must reset to INITIAL_SECONDS after a success, not keep doubling from before it")


func test_on_failure_warn_once_only_warns_the_first_time_in_a_run() -> void:
	var backoff: NetUpnpRenewalBackoff = NetUpnpRenewalBackoff.new()
	var now: float = 0.0
	backoff.on_failure_warn_once(now, "first failure")
	assert_push_warning("first failure")
	backoff.on_failure_warn_once(now, "second failure")
	for err: GutTrackedError in get_errors():
		if err.contains_text("second failure"):
			fail_test("a second consecutive failure must not warn again while the back-off from the first is still in effect")
	backoff.on_success()
	backoff.on_failure_warn_once(now, "third failure, after a success")
	assert_push_warning("third failure, after a success")


## Review item 5 / item 3: `_finish()`'s permanent-lease branch sets
## `_lease_expires_at = -1.0`, the same sentinel `is_renewal_due()` treats as
## "nothing to renew" — so a permanent mapping must never start a renewal
## worker, no matter how much time passes. No `Thread` or scene tree needed:
## `_maybe_start_renewal()` short-circuits on `is_renewal_due()` before ever
## touching `_thread`.
func test_a_permanent_mapping_never_starts_a_renewal_worker() -> void:
	var upnp: NetUpnp = autofree(NetUpnp.new())
	upnp._finish({"status": "mapped", "port": 40050, "external_ip": "8.8.8.8", "permanent": true})
	assert_eq(upnp._lease_expires_at, -1.0, "sanity: a permanent mapping must record no expiry")
	upnp._maybe_start_renewal(upnp._now() + 999999.0) # arbitrarily far in the future.
	assert_null(upnp._thread, "a permanent mapping must never start a renewal worker, at any point in time")
