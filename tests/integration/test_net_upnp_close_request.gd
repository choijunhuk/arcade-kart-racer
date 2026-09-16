extends GutTest

## Phase 18i item 2: in-app QUIT must go through the same
## NOTIFICATION_WM_CLOSE_REQUEST path a real window-close does
## (GameState.request_quit()), so a live NetUpnp worker defers it exactly as
## it already does for a real close, instead of bypassing that deferral
## entirely. A new file rather than adding to
## tests/integration/test_net_upnp_release.gd — already tight against the
## 400-line budget — but mirrors its own `_notification()` test technique.

var _upnp: NetUpnp

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
