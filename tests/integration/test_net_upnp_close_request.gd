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
	static func _run_removal(port: int, box: NetUpnp.ResultBox) -> void:
		box.result = {"kind": "removal", "port": port, "removed": true}
		box.done = true


func after_each() -> void:
	if is_instance_valid(_upnp):
		_upnp.queue_free()
	_upnp = null
	GameState.quit_override = Callable()
	get_tree().auto_accept_quit = true


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
	_upnp._lease_expires_at = -1.0 # Permanent (NetUpnp._finish()'s own sentinel).
	var quit_calls: Array = [0] # Array, not a plain int: a lambda captures outer locals by value.
	_upnp._quit_waiter.quit_override = func() -> void: quit_calls[0] += 1 # Review RED-1: never let this reach the real engine quit mid-suite.
	get_tree().auto_accept_quit = true
	_upnp._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_upnp._mapped_port, -1, "the permanent mapping must be cleared synchronously before the removal worker starts")
	assert_false(get_tree().auto_accept_quit, "removing a permanent lease must veto the automatic quit")
	assert_true(_upnp._quit_waiter.is_armed(), "the bounded quit wait must be armed for the removal worker")
	assert_not_null(_upnp._thread, "a removal worker must actually have started")
	# Let the (instant, fake) removal worker actually report back and free the
	# node itself. Wall-clock bounded via a real `process_frame` signal, not
	# GUT's `wait_process_frames` (simulated/fixed-step time that can diverge
	# from a genuine background Thread's own scheduling — see
	# test_net_upnp_release.gd's `_UpnpTestWait.wait_for_freed` doc comment,
	# same reasoning here) — and never manually joins the thread itself
	# (double-joining a Thread the engine also joins errors).
	var deadline_ms: int = Time.get_ticks_msec() + 2000
	while is_instance_valid(_upnp) and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
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
