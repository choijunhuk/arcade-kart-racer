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

var _upnp: NetUpnp


## Real `_run_removal` blocks on a 3s router discovery timeout; this fake
## reports back immediately so the test proves the removal worker started
## without waiting on real network I/O — this file's sibling tests already
## avoid that (see test_net_lobby.gd's own UPnP coverage).
class FakeRemovalUpnp extends NetUpnp:
	func _run_removal(port: int) -> void:
		call_deferred("_finish_removal", port, true)


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
	await wait_for_signal(_upnp.tree_exited, 1.0, "release_and_free() must free the node once the removal worker reports back")


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
