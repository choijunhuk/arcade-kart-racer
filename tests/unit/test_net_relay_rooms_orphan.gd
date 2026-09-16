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
	rooms.expire(45.0) # Removes the silent A; requeues B pending under ROOM2 (clock seeded from B's own last touch, t=20).
	assert_eq(rooms.pending_count(), 1, "sanity: B must be pending, waiting for a re-pair")
	# B keeps sending (touch refreshes its own peer_seen so it never times out
	# that way), but nobody re-announces ROOM2 — once the pending slot itself
	# outlives ROOM_IDLE_SECONDS(60), B must be swept at t=110 rather than
	# left pending forever.
	rooms.touch("2.2.2.2:2", 109.0)
	var swept: Array[String] = rooms.expire(110.0)
	assert_eq(swept, ["2.2.2.2:2"] as Array[String], "the abandoned peer must be swept once its pending slot times out")
	assert_eq(rooms.pending_count(), 0)
	assert_eq(rooms.partner_of("2.2.2.2:2"), "")

## Review YELLOW: the requeue must never drop the abandoned partner when the
## same room code already has another peer waiting (a third peer — e.g. the
## host reconnecting from a new port — announced it before the departure).
## The survivor is re-announced on its own behalf, so it pairs with that
## waiter exactly as a fresh HELLO would, and every later departure keeps
## tracking whoever is left.
func test_three_peers_same_code_pairs_the_abandoned_partner_with_the_waiting_third_peer() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOM3", "1.1.1.1:1", 0.0) # A
	rooms.announce("ROOM3", "2.2.2.2:2", 0.0) # B, pairs with A
	assert_eq(rooms.announce("ROOM3", "3.3.3.3:3", 30.0), "", "C must wait in ROOM3's pending slot while A/B are paired")
	rooms.touch("2.2.2.2:2", 40.0) # B stays active; A goes silent from t=0.
	assert_eq(rooms.expire(45.0), ["1.1.1.1:1"] as Array[String], "only the silent A must expire")
	assert_eq(rooms.partner_of("2.2.2.2:2"), "3.3.3.3:3", "the abandoned B must pair with the already-waiting C")
	assert_eq(rooms.partner_of("3.3.3.3:3"), "2.2.2.2:2")
	assert_eq(rooms.pending_count(), 0, "pairing B with C must consume C's pending slot")
	# C now goes silent while B keeps sending: C expires and B is requeued
	# (seeded from its own last touch at t=40) instead of orphaned again.
	assert_eq(rooms.expire(65.0), ["3.3.3.3:3"] as Array[String], "only the silent C must expire")
	assert_eq(rooms.partner_of("2.2.2.2:2"), "")
	assert_eq(rooms.pending_count(), 1, "B must be pending again, never dropped")
	rooms.touch("2.2.2.2:2", 100.0)
	assert_eq(rooms.expire(101.0), ["2.2.2.2:2"] as Array[String], "B's pending slot (since t=40) must time out at t>100 even though B itself kept sending")
	assert_eq(rooms.pending_count(), 0)


## The requeued pending slot inherits the partner's OWN idle clock, not a
## fresh ROOM_IDLE_SECONDS window starting at the moment its partner left.
func test_requeue_seeds_the_pending_clock_from_the_partners_own_last_seen_time() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOM4", "1.1.1.1:1", 0.0) # A
	rooms.announce("ROOM4", "2.2.2.2:2", 0.0) # B, pairs with A
	rooms.touch("2.2.2.2:2", 20.0)
	assert_eq(rooms.expire(45.0), ["1.1.1.1:1"] as Array[String])
	rooms.touch("2.2.2.2:2", 80.0) # B itself is not peer-idle...
	# ...but its pending slot, seeded from t=20, is now past ROOM_IDLE_SECONDS
	# (60) even though only 36s have passed since the t=45 requeue.
	assert_eq(rooms.expire(81.0), ["2.2.2.2:2"] as Array[String], "the pending clock must be seeded from B's own last-seen time, not the requeue time")


## The requeue is a real insert into the pending table, so it must respect
## MAX_PENDING_ROOMS by evicting the oldest half-open room first (the same
## path a fresh announce takes), never growing the table past the cap.
func test_requeue_still_holds_the_pending_cap_by_evicting_the_oldest_room() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOMX", "1.1.1.1:1", 0.0) # A
	rooms.announce("ROOMX", "2.2.2.2:2", 0.0) # B, pairs with A
	for index: int in range(NetRelayRooms.MAX_PENDING_ROOMS):
		rooms.announce("P%d" % index, "10.0.0.1:%d" % index, 1.0 + float(index))
	assert_eq(rooms.pending_count(), NetRelayRooms.MAX_PENDING_ROOMS, "sanity: the pending table is full")
	rooms.touch("2.2.2.2:2", 200.0)
	rooms.remove("1.1.1.1:1", 200.0) # A leaves; B must be requeued without breaking the cap.
	assert_eq(rooms.pending_count(), NetRelayRooms.MAX_PENDING_ROOMS, "the requeue must evict the oldest pending room instead of exceeding the cap")
	assert_eq(rooms.announce("ROOMX", "4.4.4.4:4", 201.0), "2.2.2.2:2", "the requeued B must still be re-pairable under its own code")
	# The oldest half-open room (P0) is the one that went: announcing it again
	# opens a fresh slot instead of pairing with its evicted peer.
	assert_eq(rooms.announce("P0", "10.0.0.3:1", 202.0), "")
	assert_eq(rooms.partner_of("10.0.0.1:0"), "")
