extends GutTest

## Real, dual-ended ENet connection coverage for peer-timeout widening
## (finding 1) and forced kicks (finding 2). Split out of
## tests/integration/test_net_lobby.gd for the 400-line rule, the same way
## test_net_upnp_reachability.gd was split out of test_net_internet.gd.
##
## A single `SceneTree` has exactly one active `MultiplayerAPI`/peer, so a
## test cannot run two real, fully-wired `NetSession`s at once — the tests
## below instead pair one real `NetSession` (the side under test) against a
## bare, manually-polled `ENetMultiplayerPeer` standing in for the other end.

const _TIMEOUT_TEST_MAX_FRAMES: int = 300

## Binds an ephemeral UDP port and reads it back so these real-connection
## tests cannot collide on a hardcoded port during a parallel gate run
## (finding 6). The probe socket is closed immediately, handing the free
## port number to the caller's own ENet listener/client.
func _free_test_port() -> int:
	var probe: UDPServer = UDPServer.new()
	assert_eq(probe.listen(0), OK)
	var port: int = probe.get_local_port()
	probe.stop()
	return port

## Connects `raw_client` to `server` and returns its ENet peer id once the
## server sees a real, live connection (or -1 on timeout).
func _connect_raw_client(raw_client: ENetMultiplayerPeer, server: NetSession) -> int:
	var client_id: int = raw_client.get_unique_id()
	for _i: int in range(_TIMEOUT_TEST_MAX_FRAMES):
		raw_client.poll()
		await wait_process_frames(1)
		if server.multiplayer.get_peers().has(client_id):
			return client_id
	return -1

## Finding 1 (audit): an unauthenticated peer (ENet-connected but never past
## `NetPeerGate`) must not be on the widened-timeout path yet — only
## `_admit_peer` widens it now, not `_peer_connected`. `ENetPacketPeer`
## exposes no getter for its configured timeout, so this proves the peer
## stays alive and unverified rather than checking the timeout value itself.
func test_unadmitted_peer_stays_unverified_and_does_not_widen_its_timeout() -> void:
	var port: int = _free_test_port()
	var server: NetSession = NetSession.new()
	add_child_autofree(server)
	assert_eq(server.host(port), OK)
	var raw_client: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(raw_client.create_client("127.0.0.1", port, NetTuning.CHANNEL_COUNT), OK)
	var client_id: int = await _connect_raw_client(raw_client, server)
	assert_true(client_id > 0, "the raw client must actually reach the real server for this test to prove anything")
	assert_false(server._gate.allows(client_id), "a raw ENet connect alone must not pass the handshake gate")
	assert_true(server._gate.is_pending(client_id), "the peer must still be waiting on its handshake deadline")
	var server_side_peer: ENetPacketPeer = server.peer.get_peer(client_id)
	assert_not_null(server_side_peer, "the server must have an ENet peer for the connected client")
	assert_true(server_side_peer.is_active(), "staying unadmitted must not itself disconnect the peer")
	raw_client.close()

## Finding 1 (audit): `_admit_peer` (not `_peer_connected`) is what widens the
## server-side timeout, and only reaches a real peer once admission actually
## succeeds.
func test_admit_peer_widens_the_timeout_for_a_real_connected_peer() -> void:
	var port: int = _free_test_port()
	var server: NetSession = NetSession.new()
	add_child_autofree(server)
	assert_eq(server.host(port), OK)
	var raw_client: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(raw_client.create_client("127.0.0.1", port, NetTuning.CHANNEL_COUNT), OK)
	var client_id: int = await _connect_raw_client(raw_client, server)
	assert_true(client_id > 0, "the raw client must actually reach the real server for this test to prove anything")
	server._admit_peer(client_id)
	assert_eq(server.players.size(), 2, "admission must have added a roster row alongside the host's own")
	var server_side_peer: ENetPacketPeer = server.peer.get_peer(client_id)
	assert_not_null(server_side_peer, "the server must have an ENet peer for the admitted client")
	assert_true(server_side_peer.is_active(), "widening the timeout on admission must not itself disconnect the peer")
	raw_client.close()

## Finding 1 (audit): `net_session.gd`'s `_connected` must widen the timeout
## for this process's own real link to the server the moment it connects.
func test_peer_timeout_widening_runs_on_the_client_side_of_a_real_connection() -> void:
	var port: int = _free_test_port()
	var raw_server: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(raw_server.create_server(port, 32, NetTuning.CHANNEL_COUNT), OK)
	var client: NetSession = NetSession.new()
	add_child_autofree(client)
	assert_eq(client.join("127.0.0.1", port), OK)
	var connected: bool = false
	for _i: int in range(_TIMEOUT_TEST_MAX_FRAMES):
		raw_server.poll()
		await wait_process_frames(1)
		if client.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			break
	assert_true(connected, "the real client must actually reach the raw server for this test to prove anything")
	var client_side_peer: ENetPacketPeer = client.peer.get_peer(NetSession.SERVER_ID)
	assert_not_null(client_side_peer, "the client must have an ENet peer for the server")
	assert_true(client_side_peer.is_active(), "widening the timeout must not itself disconnect the client's peer")
	raw_server.close()

## Finding 2 (audit): a rejected/handshake-timed-out peer must be force-
## disconnected (`ENetMultiplayerPeer.disconnect_peer(id, true)`), not the
## graceful `multiplayer.disconnect_peer(id)` which waits on the peer's own
## ack. Runs the real `_reject_peer` -> queued-kick -> `service_peers` path
## (verifying the peer first so the real 3s handshake deadline can't also
## fire and race this test's own kick); the raw client is deliberately never
## polled again afterward. Checked via the low-level `ENetPacketPeer`: a
## forced disconnect resets that immediately, but (engine behavior confirmed
## empirically) does not itself update the high-level `multiplayer.get_peers()`
## bookkeeping, which only reacts to a real DISCONNECT event — something the
## "force now" disconnect never generates. The graceful path would instead
## leave this low-level peer active for the full widened timeout, waiting on
## an ack that never comes.
func test_kicked_peer_is_force_disconnected_without_needing_its_own_ack() -> void:
	var port: int = _free_test_port()
	var server: NetSession = NetSession.new()
	add_child_autofree(server)
	assert_eq(server.host(port), OK)
	var raw_client: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	assert_eq(raw_client.create_client("127.0.0.1", port, NetTuning.CHANNEL_COUNT), OK)
	var client_id: int = await _connect_raw_client(raw_client, server)
	assert_true(client_id > 0, "the raw client must actually reach the real server for this test to prove anything")
	# Fetched once, before the kick: `get_peer()` itself logs an engine error
	# for an id ENet no longer knows about, so it must not be re-queried after
	# the disconnect below — `is_active()` on this same cached reference is
	# the safe way to observe the drop.
	var enet_peer: ENetPacketPeer = server.peer.get_peer(client_id)
	assert_not_null(enet_peer, "the server must have an ENet peer for the connected client")
	server._gate.verify(client_id) # not the handshake deadline this test is after
	server._reject_peer(client_id, "test kick")
	var dropped: bool = false
	for _i: int in range(_TIMEOUT_TEST_MAX_FRAMES):
		await wait_physics_frames(1)
		if not enet_peer.is_active():
			dropped = true
			break
	assert_true(dropped, "a forced disconnect must not wait on the kicked peer's own ack")

func after_each() -> void:
	# The real-connection tests above leave a real ENetMultiplayerPeer
	# assigned as the tree's shared multiplayer peer (autofree only closes
	# the NetSession's own `peer`, not `multiplayer.multiplayer_peer` itself),
	# and `NetSession.host()`/`join()` set `GameState.is_networked` — reset
	# both so they cannot leak into later suites sharing this gate process
	# (finding 6).
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	GameState.is_networked = false
	GameState.net_session = null
