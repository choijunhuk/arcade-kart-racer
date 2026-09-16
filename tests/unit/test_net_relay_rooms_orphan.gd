extends GutTest

## Backlog item 3: NetRelayRooms.remove() used to leave a departed peer's
## still-active partner in permanent limbo — unpartnered, not pending, but
## never swept either as long as it kept sending (touch() kept refreshing
## its own peer_seen indefinitely, so PEER_IDLE_SECONDS never caught it).
## remove() now re-queues that partner into the same room's pending slot
## instead, so an asymmetric timeout (one side silent, the other still
## sending) either re-pairs the survivor under a fresh announce of the same
## code, or lets it get swept once the room itself sits pending too long.

func test_asymmetric_timeout_lets_the_abandoned_partner_re_pair_under_the_same_code() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOM1", "1.1.1.1:1", 0.0) # A
	rooms.announce("ROOM1", "2.2.2.2:2", 0.0) # B, pairs with A
	assert_eq(rooms.partner_of("2.2.2.2:2"), "1.1.1.1:1")
	rooms.touch("2.2.2.2:2", 20.0) # B stays active; A goes silent from t=0.
	# At t=45: A's own 45s gap exceeds PEER_IDLE_SECONDS(30); B's 25s gap
	# (since its own last touch at t=20) does not — an asymmetric timeout.
	var expired: Array[String] = rooms.expire(45.0)
	assert_eq(expired, ["1.1.1.1:1"] as Array[String], "only the silent peer A must expire")
	assert_eq(rooms.partner_of("2.2.2.2:2"), "", "B must be unpartnered once A is gone")
	assert_eq(rooms.pending_count(), 1, "B must be queued back into a pending slot instead of left a permanent orphan")
	# A fresh peer announcing the same room code (well within ROOM_IDLE_SECONDS
	# of B's t=45 requeue) re-pairs with the orphaned B.
	assert_eq(rooms.announce("ROOM1", "3.3.3.3:3", 50.0), "2.2.2.2:2")
	assert_eq(rooms.partner_of("2.2.2.2:2"), "3.3.3.3:3")

func test_asymmetric_timeout_sweeps_the_abandoned_partner_if_nothing_re_pairs_in_time() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOM2", "1.1.1.1:1", 0.0) # A
	rooms.announce("ROOM2", "2.2.2.2:2", 0.0) # B, pairs with A
	rooms.touch("2.2.2.2:2", 20.0)
	rooms.expire(45.0) # Removes the silent A; requeues B pending under ROOM2 at t=45.
	assert_eq(rooms.pending_count(), 1, "sanity: B must be pending, waiting for a re-pair")
	# B keeps sending (touch refreshes its own peer_seen so it never times out
	# that way), but nobody re-announces ROOM2 — once the pending slot itself
	# outlives ROOM_IDLE_SECONDS(60) from t=45, B must be swept at t=110
	# rather than left pending forever.
	rooms.touch("2.2.2.2:2", 109.0)
	var swept: Array[String] = rooms.expire(110.0)
	assert_eq(swept, ["2.2.2.2:2"] as Array[String], "the abandoned peer must be swept once its pending slot times out")
	assert_eq(rooms.pending_count(), 0)
	assert_eq(rooms.partner_of("2.2.2.2:2"), "")
