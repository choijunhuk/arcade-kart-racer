extends GutTest

## Review YELLOW: `NetRelayRooms._evict_oldest_pending()` cleans the table's
## own bookkeeping via `remove()`, after which the evicted peer never shows
## up in `expire()`'s returned stale list — so `NetRelayServer` never closed
## its `PacketPeerUDP`, and a HELLO flood past MAX_PENDING_ROOMS leaked one
## live socket per eviction. Eviction now reports its victims through
## `take_evicted()` and the server closes them on both paths that can evict:
## a fresh HELLO (`_handle_first_packet`) and an expiry-driven requeue (`_sweep`).

const RELAY_PORT: int = 40877

var _server: NetRelayServer


func after_each() -> void:
	if is_instance_valid(_server):
		_server.stop()
		if not _server.is_inside_tree(): # In-tree instances are `add_child_autofree`'d.
			_server.free()
	_server = null


## Fills the pending table to its cap with fake peers, each backed by an
## unbound (harmless to close) PacketPeerUDP in the server's socket table,
## with last-seen clocks anchored 10s after `base` (oldest first) so none
## of them is peer-idle at the sweep times the tests below use.
func _fill_pending(base: float) -> void:
	for index: int in range(NetRelayRooms.MAX_PENDING_ROOMS):
		var key: String = "10.0.0.1:%d" % index
		_server._rooms.announce("P%d" % index, key, base + 10.0 + float(index) * 0.001)
		_server._peers[key] = PacketPeerUDP.new()


func test_rooms_report_the_evicted_peer_exactly_once() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	for index: int in range(NetRelayRooms.MAX_PENDING_ROOMS):
		rooms.announce("ROOM%d" % index, "10.0.0.1:%d" % index, float(index))
	assert_eq(rooms.take_evicted(), [] as Array[String], "nothing is evicted while the table is merely full")
	rooms.announce("OVERFLOW", "10.0.0.2:1", 10000.0)
	assert_eq(rooms.take_evicted(), ["10.0.0.1:0"] as Array[String], "the oldest half-open room's peer must be reported")
	assert_eq(rooms.take_evicted(), [] as Array[String], "take_evicted() must clear what it returns")


func test_rooms_report_the_peer_evicted_by_a_requeue() -> void:
	var rooms: NetRelayRooms = NetRelayRooms.new()
	rooms.announce("ROOMX", "1.1.1.1:1", 0.0)
	rooms.announce("ROOMX", "2.2.2.2:2", 0.0)
	for index: int in range(NetRelayRooms.MAX_PENDING_ROOMS):
		rooms.announce("P%d" % index, "10.0.0.1:%d" % index, 1.0 + float(index))
	rooms.remove("1.1.1.1:1", 200.0) # Requeues B, which evicts P0's peer.
	assert_eq(rooms.take_evicted(), ["10.0.0.1:0"] as Array[String])


## The sweep path: expiring one half of a pairing requeues the survivor,
## which evicts the oldest pending peer — the server must close and drop
## that peer's socket alongside the expired one's.
func test_sweep_closes_the_socket_of_a_peer_evicted_by_a_requeue() -> void:
	_server = NetRelayServer.new()
	var base: float = 1000.0
	_server._rooms.announce("ROOMX", "1.1.1.1:1", base)
	_server._rooms.announce("ROOMX", "2.2.2.2:2", base)
	_server._peers["1.1.1.1:1"] = PacketPeerUDP.new()
	_server._peers["2.2.2.2:2"] = PacketPeerUDP.new()
	_fill_pending(base)
	_server._rooms.touch("2.2.2.2:2", base + 20.0)
	_server._sweep(base + 35.0) # A (silent since base) is past PEER_IDLE_SECONDS; the fakes (base+10) and B are not. B is requeued.
	assert_false(_server._peers.has("1.1.1.1:1"), "the expired peer's socket must be dropped (as before)")
	assert_true(_server._peers.has("2.2.2.2:2"), "the requeued survivor keeps its socket")
	assert_false(_server._peers.has("10.0.0.1:0"), "the peer evicted to make room for the requeue must have its socket dropped too")
	assert_eq(_server._peers.size(), NetRelayRooms.MAX_PENDING_ROOMS, "exactly one socket per tracked peer: B plus the surviving pending peers")
	assert_eq(_server._rooms.pending_count(), NetRelayRooms.MAX_PENDING_ROOMS)


## The HELLO path, over a real loopback UDP socket: a fresh HELLO past the
## cap evicts the oldest pending peer, whose socket must go with it.
func test_hello_past_the_cap_closes_the_evicted_peers_socket() -> void:
	_server = NetRelayServer.new()
	add_child_autofree(_server)
	assert_eq(_server.start(RELAY_PORT), OK, "sanity: the relay must be able to listen on the loopback test port")
	_fill_pending(NetSession.now())
	var client: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(client.connect_to_host("127.0.0.1", RELAY_PORT), OK)
	assert_eq(client.put_packet((NetRelayServer.HELLO_PREFIX + "NEWROOM").to_utf8_buffer()), OK)
	var deadline_ms: int = Time.get_ticks_msec() + 2000
	while _server._peers.has("10.0.0.1:0") and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
	assert_false(_server._peers.has("10.0.0.1:0"), "the evicted oldest pending peer's socket must be closed and dropped")
	assert_eq(_server._rooms.pending_count(), NetRelayRooms.MAX_PENDING_ROOMS, "the new HELLO took the evicted slot")
	assert_eq(_server._peers.size(), NetRelayRooms.MAX_PENDING_ROOMS, "one socket per pending peer, the real HELLO sender included")
	client.close()
