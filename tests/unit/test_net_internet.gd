extends GutTest

## Phase 16 pure-logic coverage: join codes, rate limiter, relay pairing and
## the dedicated-server auto-start/restart state machine. Handshake
## (version/password) coverage lives alongside NetSession in test_netcode.gd.

func test_join_code_round_trips_ip_and_port() -> void:
	var code: String = NetJoinCode.encode("203.0.113.7", 24565)
	assert_eq(code.length(), NetJoinCode.CODE_LENGTH)
	var decoded: Dictionary = NetJoinCode.decode(code)
	assert_eq(decoded.get("ip"), "203.0.113.7")
	assert_eq(decoded.get("port"), 24565)

func test_join_code_round_trips_edge_addresses() -> void:
	for pair: Array in [["0.0.0.0", 0], ["255.255.255.255", 65535], ["1.2.3.4", 1024]]:
		var code: String = NetJoinCode.encode(pair[0], pair[1])
		var decoded: Dictionary = NetJoinCode.decode(code)
		assert_eq(decoded.get("ip"), pair[0])
		assert_eq(decoded.get("port"), pair[1])

func test_join_code_is_case_and_dash_insensitive_on_decode() -> void:
	var code: String = NetJoinCode.encode("198.51.100.23", 5000)
	var spaced: String = code.substr(0, 5) + "-" + code.substr(5)
	assert_eq(NetJoinCode.decode(spaced.to_lower()), NetJoinCode.decode(code))

func test_join_code_rejects_malformed_and_bad_checksum() -> void:
	assert_eq(NetJoinCode.decode("SHORT"), {})
	assert_eq(NetJoinCode.decode("!!!!!!!!!!"), {})
	var code: String = NetJoinCode.encode("10.0.0.5", 24565)
	var found_rejection: bool = false
	for symbol: String in NetJoinCode.ALPHABET:
		if symbol == code.substr(code.length() - 1, 1):
			continue
		var corrupted: String = code.substr(0, code.length() - 1) + symbol
		if NetJoinCode.decode(corrupted).is_empty():
			found_rejection = true
			break
	assert_true(found_rejection)

func test_join_code_encode_rejects_out_of_range_input() -> void:
	assert_eq(NetJoinCode.encode("999.0.0.1", 1000), "")
	assert_eq(NetJoinCode.encode("1.2.3.4", 70000), "")
	assert_eq(NetJoinCode.encode("not.an.ip.addr", 1000), "")

func test_join_code_looks_like_code_distinguishes_from_ip_text() -> void:
	assert_true(NetJoinCode.looks_like_code(NetJoinCode.encode("10.0.0.1", 24565)))
	assert_false(NetJoinCode.looks_like_code("192.168.1.5"))
	assert_false(NetJoinCode.looks_like_code("192.168.1.5:24565"))

func test_rate_limiter_allows_burst_then_throttles() -> void:
	var limiter: NetRateLimiter = NetRateLimiter.new(3.0, 1.0)
	assert_true(limiter.allow(1, 0.0))
	assert_true(limiter.allow(1, 0.0))
	assert_true(limiter.allow(1, 0.0))
	assert_false(limiter.allow(1, 0.0))
	assert_true(limiter.allow(1, 1.0))
	assert_false(limiter.allow(1, 1.0))

func test_rate_limiter_tracks_keys_independently_and_forgets_removed() -> void:
	var limiter: NetRateLimiter = NetRateLimiter.new(1.0, 1.0)
	assert_true(limiter.allow(1, 0.0))
	assert_true(limiter.allow(2, 0.0))
	assert_false(limiter.allow(1, 0.0))
	limiter.remove(1)
	assert_true(limiter.allow(1, 0.0))

func test_relay_rooms_pairs_two_announcers_and_ignores_third() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	assert_eq(rooms.announce("ABCD1234", "1.1.1.1:1"), "")
	assert_eq(rooms.announce("ABCD1234", "2.2.2.2:2"), "1.1.1.1:1")
	assert_eq(rooms.partner_of("1.1.1.1:1"), "2.2.2.2:2")
	assert_eq(rooms.partner_of("2.2.2.2:2"), "1.1.1.1:1")
	# A third peer announcing the same code starts a new pending slot, not a triple-pairing.
	assert_eq(rooms.announce("ABCD1234", "3.3.3.3:3"), "")
	assert_eq(rooms.partner_of("3.3.3.3:3"), "")

func test_relay_rooms_ignores_duplicate_announce_from_same_peer() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	assert_eq(rooms.announce("ROOM0001", "1.1.1.1:1"), "")
	assert_eq(rooms.announce("ROOM0001", "1.1.1.1:1"), "")
	assert_eq(rooms.partner_of("1.1.1.1:1"), "")

func test_relay_rooms_remove_clears_pairing_and_pending_slot() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOM1", "1.1.1.1:1")
	rooms.announce("ROOM1", "2.2.2.2:2")
	rooms.remove("1.1.1.1:1")
	assert_eq(rooms.partner_of("2.2.2.2:2"), "")
	rooms.announce("ROOM2", "3.3.3.3:3")
	rooms.remove("3.3.3.3:3")
	assert_eq(rooms.announce("ROOM2", "4.4.4.4:4"), "")

func test_server_state_stays_in_lobby_with_no_players() -> void:
	var state: NetServerState = NetServerState.new()
	assert_false(state.update(1.0, 0, 0))
	assert_eq(state.state, NetServerState.State.LOBBY)

func test_server_state_starts_immediately_once_all_ready() -> void:
	var state: NetServerState = NetServerState.new()
	assert_false(state.update(0.1, 1, 0))
	assert_eq(state.state, NetServerState.State.COUNTDOWN)
	assert_true(state.update(0.1, 1, 1))
	assert_eq(state.state, NetServerState.State.RUNNING)

func test_server_state_forces_start_after_20s_with_partial_ready() -> void:
	var state: NetServerState = NetServerState.new()
	state.update(0.0, 2, 0)
	var started: bool = false
	for _tick: int in range(25):
		if state.update(1.0, 2, 1):
			started = true
			break
	assert_true(started)
	assert_eq(state.state, NetServerState.State.RUNNING)

func test_server_state_resets_to_lobby_if_everyone_leaves_during_countdown() -> void:
	var state: NetServerState = NetServerState.new()
	state.update(0.1, 1, 0)
	assert_eq(state.state, NetServerState.State.COUNTDOWN)
	state.update(0.1, 0, 0)
	assert_eq(state.state, NetServerState.State.LOBBY)

func test_server_state_waits_for_a_late_peers_handshake_before_starting() -> void:
	var state: NetServerState = NetServerState.new()
	assert_false(state.update(0.1, 1, 1, 0))
	assert_eq(state.state, NetServerState.State.COUNTDOWN)
	# A second ENet peer arrives before its handshake is verified. The first
	# ready peer must not start a one-kart race while that deadline is active.
	assert_false(state.update(0.1, 1, 1, 1))
	assert_eq(state.state, NetServerState.State.LOBBY)
	assert_false(state.update(0.1, 2, 2, 0))
	assert_true(state.update(0.1, 2, 2, 0))
	assert_eq(state.state, NetServerState.State.RUNNING)

func test_handshake_accepts_matching_version_and_no_password() -> void:
	assert_eq(NetHandshake.reject_reason("0.5.0", "0.5.0", "", ""), "")

func test_handshake_rejects_version_mismatch() -> void:
	var reason: String = NetHandshake.reject_reason("0.4.0", "0.5.0", "", "")
	assert_true(reason.findn("version") >= 0)

func test_handshake_ignores_version_when_host_has_none_set() -> void:
	assert_eq(NetHandshake.reject_reason("anything", "", "", ""), "")

func test_handshake_rejects_wrong_password_hash() -> void:
	var expected: String = "secret".sha256_text()
	assert_eq(NetHandshake.reject_reason("0.5.0", "0.5.0", expected, expected), "")
	var reason: String = NetHandshake.reject_reason("0.5.0", "0.5.0", "wrong".sha256_text(), expected)
	assert_true(reason.findn("password") >= 0)

func test_handshake_ignores_password_when_host_requires_none() -> void:
	assert_eq(NetHandshake.reject_reason("0.5.0", "0.5.0", "anything", ""), "")

func test_server_state_finish_and_restart_returns_to_lobby() -> void:
	var state: NetServerState = NetServerState.new()
	state.update(0.1, 1, 1)
	state.update(0.1, 1, 1)
	assert_eq(state.state, NetServerState.State.RUNNING)
	state.finish_and_restart()
	assert_eq(state.state, NetServerState.State.LOBBY)
	assert_eq(state.countdown_remaining(), NetServerState.COUNTDOWN_SECONDS)

## Server-side NetSession with a scriptable RPC sender id and captured reject
## deliveries, so the real handshake/admission/kick wiring runs in-process.
class GateSession extends NetSession:
	var sender_id: int = 0
	var rejects: Array[Dictionary] = []

	func _sender() -> int:
		return sender_id

	func _deliver_reject(id: int, message: String) -> void:
		rejects.append({"peer": id, "message": message})

	## Runs one server tick's peer servicing without a real physics frame.
	func service_peers() -> void:
		_service_peers()

	func gate() -> NetPeerGate:
		return _gate

	## Mirrors the real client's own challenge-response step (spec item 6):
	## computes the response for whatever nonce the gate currently holds for
	## `id`, so every existing caller keeps passing the plain attempted-
	## password hash exactly as before the challenge-response protocol landed.
	func handshake_from(id: int, version: String, password_attempt_hash: String) -> void:
		sender_id = id
		_handshake(version, NetHandshake.response(gate().nonce_for(id), password_attempt_hash))

	func selection_from(id: int, driver: String, kart: String, ready: bool) -> void:
		sender_id = id
		_selection(driver, kart, ready)

	func input_from(id: int, data: Dictionary) -> void:
		sender_id = id
		_receive_input(data)

func _version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", ""))

func _gate_session() -> GateSession:
	var session: GateSession = GateSession.new()
	add_child_autofree(session)
	return session

## Review finding 5: the previous version of this test fed `NetSession.now()`
## (a real wall-clock read) through a tight loop and inferred throttling from
## timing alone — the same flake class backlog item 5 already fixed
## elsewhere (see test_net_lobby.gd's `_delayed_load_ack` comment). Throttling
## is proven directly against `NetRateLimiter` with explicit `now` values
## instead, sized to `_selection_limiter`'s actual configured capacity/refill
## so it cannot silently drift from the real limiter.
func test_selection_limiter_throttles_over_budget_calls_then_recovers() -> void:
	var reference: NetSession = NetSession.new()
	autofree(reference)
	var limiter: NetRateLimiter = NetRateLimiter.new(reference._selection_limiter.capacity, reference._selection_limiter.refill_per_second)
	for _i: int in range(int(limiter.capacity)):
		assert_true(limiter.allow(20, 0.0))
	assert_false(limiter.allow(20, 0.0), "a call beyond the bucket's capacity in the same instant must be dropped")
	assert_true(limiter.allow(20, 1.0), "a second later the refill must allow exactly one more call")

## Backlog item 6, kept to "one call goes through" per review finding 5:
## `_selection` must still be wired through `_selection_limiter` end to end.
## Sustained throttling itself is `NetRateLimiter`'s own job, proven above
## without any RPC call or timing involved.
func test_selection_rpc_lets_a_single_call_through() -> void:
	var session: GateSession = _gate_session()
	session._peer_connected(20)
	session.handshake_from(20, _version(), "")
	assert_eq(session.players.size(), 1, "the peer must hold a roster row for this test to prove anything")
	var driver_id: String = NetContentCatalog.default_driver_id()
	var kart_id: String = NetContentCatalog.default_kart_id()
	session.selection_from(20, driver_id, kart_id, true)
	assert_true(bool(session.players[0]["ready"]), "a single _selection call within budget must go through, exactly like _receive_input")

func test_peer_gate_blocks_until_handshake_then_allows() -> void:
	var gate: NetPeerGate = NetPeerGate.new()
	gate.track(5, 0.0)
	assert_false(gate.allows(5))
	assert_true(gate.verify(5))
	assert_true(gate.allows(5))
	# A replayed handshake cannot re-admit an already verified peer.
	assert_false(gate.verify(5))
	# A verified peer never trips the handshake deadline.
	assert_true(gate.expired(NetPeerGate.DEADLINE_SECONDS + 1.0).is_empty())

func test_peer_gate_expires_a_silent_peer_and_defers_its_kick() -> void:
	var gate: NetPeerGate = NetPeerGate.new()
	gate.track(6, 0.0)
	assert_true(gate.expired(NetPeerGate.DEADLINE_SECONDS - 0.1).is_empty())
	assert_eq(gate.expired(NetPeerGate.DEADLINE_SECONDS), [6] as Array[int])
	gate.queue_kick(6, 0.0)
	gate.queue_kick(6, 0.0)
	assert_true(gate.take_kicks(0.0).is_empty(), "kick must wait for the grace window")
	assert_eq(gate.take_kicks(NetPeerGate.KICK_GRACE_SECONDS), [6] as Array[int])
	assert_true(gate.take_kicks(NetPeerGate.KICK_GRACE_SECONDS).is_empty())
	gate.remove(6)
	assert_false(gate.allows(6))
	assert_true(gate.expired(1000.0).is_empty())

func test_unverified_peer_gets_no_kart_and_is_kicked_after_the_deadline() -> void:
	var session: GateSession = _gate_session()
	session._peer_connected(7)
	# Playing without a handshake: no roster row/kart, every packet ignored (spec 6).
	session.selection_from(7, NetContentCatalog.default_driver_id(), NetContentCatalog.default_kart_id(), true)
	session.input_from(7, {"frames": [{"tick": 1}]})
	assert_eq(session.players.size(), 0)
	session.service_peers()
	assert_true(session.rejects.is_empty())
	# Backdate the deadline rather than sleeping out the real 3 s.
	session.gate().track(7, NetSession.now() - NetPeerGate.DEADLINE_SECONDS - 0.1)
	session.service_peers()
	assert_eq(session.rejects.size(), 1)
	assert_eq(int(session.rejects[0]["peer"]), 7)
	assert_true(String(session.rejects[0]["message"]).findn("handshake") >= 0)
	assert_eq(session.gate().take_kicks(NetSession.now() + NetPeerGate.KICK_GRACE_SECONDS), [7] as Array[int])

func test_handshake_rejects_wrong_password_and_admits_the_right_one() -> void:
	var session: GateSession = _gate_session()
	session.set_password("secret")
	session._peer_connected(8)
	session.handshake_from(8, _version(), "wrong".sha256_text())
	assert_eq(session.players.size(), 0)
	assert_eq(session.rejects.size(), 1)
	assert_eq(int(session.rejects[0]["peer"]), 8)
	assert_true(String(session.rejects[0]["message"]).findn("password") >= 0)
	session._peer_connected(9)
	session.handshake_from(9, _version(), "secret".sha256_text())
	assert_eq(session.rejects.size(), 1)
	assert_eq(session.players.size(), 1)
	assert_eq(int(session.players[0]["peer"]), 9)
	# Only now does the peer's own traffic count.
	session.selection_from(9, NetContentCatalog.default_driver_id(), NetContentCatalog.default_kart_id(), true)
	assert_true(bool(session.players[0]["ready"]))

func test_handshake_rejects_version_mismatch_before_any_roster_row() -> void:
	var session: GateSession = _gate_session()
	session._peer_connected(11)
	session.handshake_from(11, _version() + "-old", "")
	assert_eq(session.players.size(), 0)
	assert_eq(session.rejects.size(), 1)
	assert_true(String(session.rejects[0]["message"]).findn("version") >= 0)

func test_running_dedicated_server_keeps_a_late_peer_for_the_next_lobby() -> void:
	var session: GateSession = _gate_session()
	session.dedicated = true
	session.started = true
	session._peer_connected(12)
	session.handshake_from(12, _version(), "")
	assert_true(session.rejects.is_empty())
	assert_true(session.gate().allows(12))
	assert_eq(session.players.size(), 0, "a spectator must not enter the active race roster")
	assert_true(session._roster.waiting_has(12))
	session._roster.promote_waiting()
	assert_eq(session.players.size(), 1)
	assert_eq(int(session.players[0]["peer"]), 12)
	assert_false(bool(session.players[0]["ready"]))

func test_reject_delivers_the_reason_before_deferring_the_disconnect() -> void:
	var session: GateSession = _gate_session()
	session._peer_connected(4)
	session.handshake_from(4, _version(), "")
	assert_eq(session.players.size(), 1)
	session._reject_peer(4, "Incorrect session password")
	# Reason out first; the disconnect waits for the next serviced tick so
	# ENet can flush it, instead of the peer seeing "Host disconnected".
	assert_eq(session.rejects.size(), 1)
	assert_eq(String(session.rejects[0]["message"]), "Incorrect session password")
	assert_eq(session.players.size(), 0)
	assert_false(session.gate().allows(4))
	assert_true(session.gate().take_kicks(NetSession.now()).is_empty(), "disconnect waits for the grace window")
	assert_eq(session.gate().take_kicks(NetSession.now() + NetPeerGate.KICK_GRACE_SECONDS), [4] as Array[int])

func test_resend_during_kick_grace_is_ignored() -> void:
	var session: GateSession = _gate_session()
	session.set_password("secret")
	session._peer_connected(13)
	session.handshake_from(13, _version(), "wrong".sha256_text())
	session.handshake_from(13, _version(), "wrong-again".sha256_text())
	session.handshake_from(13, _version() + "-old", "secret".sha256_text())
	session.handshake_from(13, _version(), "secret".sha256_text())
	assert_eq(session.rejects.size(), 1, "resend must not draw a second reject")
	assert_eq(session.players.size(), 0, "correct hash during grace must not admit")
	assert_eq(session.gate().take_kicks(NetSession.now() + NetPeerGate.KICK_GRACE_SECONDS), [13] as Array[int])

func test_dedicated_server_reserves_no_connection_slot_or_roster_row() -> void:
	assert_eq(NetSessionLobby.connection_slots(8, true), 8)
	assert_eq(NetSessionLobby.connection_slots(8, false), 7)
	assert_eq(NetSessionLobby.connection_slots(4, false), 3)
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session._roster.reset_for_host(true, false)
	assert_eq(session.players.size(), 0)
	session._roster.reset_for_host(false, false)
	assert_eq(session.players.size(), 1)
	assert_eq(int(session.players[0]["peer"]), NetSession.SERVER_ID)

func test_relay_rooms_expire_a_silent_peer_and_free_its_pending_room() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOM1", "1.1.1.1:1", 0.0)
	assert_eq(rooms.pending_count(), 1)
	assert_eq(rooms.expire(NetRelayRooms.PEER_IDLE_SECONDS + 1.0), ["1.1.1.1:1"] as Array[String])
	assert_eq(rooms.pending_count(), 0)
	assert_eq(rooms.announce("ROOM1", "2.2.2.2:2", 100.0), "")

func test_relay_rooms_keep_a_pairing_alive_while_it_still_sends() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOM2", "1.1.1.1:1", 0.0)
	rooms.announce("ROOM2", "2.2.2.2:2", 0.0)
	rooms.touch("1.1.1.1:1", 20.0)
	rooms.touch("2.2.2.2:2", 20.0)
	assert_true(rooms.expire(40.0).is_empty())
	assert_eq(rooms.partner_of("1.1.1.1:1"), "2.2.2.2:2")
	assert_eq(rooms.expire(20.0 + NetRelayRooms.PEER_IDLE_SECONDS + 1.0).size(), 2)
	assert_eq(rooms.partner_of("1.1.1.1:1"), "")
	assert_eq(rooms.partner_of("2.2.2.2:2"), "")

func test_relay_rooms_expire_a_half_open_room_no_partner_ever_joins() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOM3", "1.1.1.1:1", 0.0)
	# The peer keeps sending, so only the room timeout can retire it.
	for step: int in range(1, 8):
		rooms.touch("1.1.1.1:1", float(step) * 10.0)
		rooms.expire(float(step) * 10.0)
	assert_eq(rooms.pending_count(), 0)
	assert_eq(rooms.partner_of("1.1.1.1:1"), "")

func test_relay_rooms_cap_pending_rooms_and_evict_the_oldest() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	for index: int in range(NetRelayRooms.MAX_PENDING_ROOMS):
		rooms.announce("ROOM%d" % index, "10.0.0.1:%d" % index, float(index))
	assert_eq(rooms.pending_count(), NetRelayRooms.MAX_PENDING_ROOMS)
	rooms.announce("OVERFLOW", "10.0.0.2:1", 10000.0)
	assert_eq(rooms.pending_count(), NetRelayRooms.MAX_PENDING_ROOMS)
	# The oldest half-open room is the one that went.
	assert_eq(rooms.partner_of("10.0.0.1:0"), "")
	assert_eq(rooms.announce("ROOM0", "10.0.0.3:1", 10001.0), "")
