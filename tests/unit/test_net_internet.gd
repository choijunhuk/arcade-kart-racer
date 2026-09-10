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
