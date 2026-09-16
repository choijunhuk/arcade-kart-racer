extends GutTest

## Review YELLOW: `NetUpnpQuitWaiter.poll()` fired the (deferred) quit but,
## unlike `fire_on_exit()`, never restored `SceneTree.auto_accept_quit` —
## the flag the arming close request cleared. Once the fire is intercepted
## (the `quit_override` test seam, or a build that cancels a quit) nothing
## would ever set it back, so every later window close stayed vetoed.
## Pure `RefCounted` unit coverage of both `poll()` branches; the real
## engine `quit()` is never reached (every test sets `quit_override`).

var _waiter: NetUpnpQuitWaiter
var _quit_calls: Array = [0] # Array, not a plain int: a lambda captures outer locals by value.


func before_each() -> void:
	_waiter = NetUpnpQuitWaiter.new()
	_quit_calls = [0]
	_waiter.quit_override = func() -> void: _quit_calls[0] += 1


func after_each() -> void:
	get_tree().auto_accept_quit = true # Restore the real, shared SceneTree's flag for the rest of the suite.


func test_poll_restores_auto_accept_quit_before_firing_on_worker_done() -> void:
	_waiter.arm(100.0, 3.0, 0.25)
	get_tree().auto_accept_quit = false # As the arming close request does.
	_waiter.poll(100.5, true, get_tree())
	assert_true(get_tree().auto_accept_quit, "poll() must restore auto_accept_quit when it fires, like fire_on_exit() does")
	assert_eq(_quit_calls[0], 1, "the quit hook must fire exactly once")
	assert_false(_waiter.is_armed(), "firing must disarm the wait")


func test_poll_restores_auto_accept_quit_before_firing_on_deadline() -> void:
	_waiter.arm(100.0, 3.0, 0.25)
	get_tree().auto_accept_quit = false
	_waiter.poll(103.25, false, get_tree())
	assert_true(get_tree().auto_accept_quit, "the deadline branch must restore auto_accept_quit too")
	assert_eq(_quit_calls[0], 1)
	assert_false(_waiter.is_armed())


func test_poll_leaves_the_flag_alone_while_still_waiting_or_unarmed() -> void:
	get_tree().auto_accept_quit = false
	_waiter.poll(100.0, false, get_tree()) # Unarmed: a no-op.
	_waiter.arm(100.0, 3.0, 0.25)
	_waiter.poll(101.0, false, get_tree()) # Armed, worker live, deadline not reached.
	assert_false(get_tree().auto_accept_quit, "only an actual fire restores the flag; a pending wait must keep the veto")
	assert_eq(_quit_calls[0], 0)
	assert_true(_waiter.is_armed())
