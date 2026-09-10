class_name NetRelayServer
extends Node

## Thin, protocol-agnostic UDP forwarder for double-NAT hosts (spec item 4):
## "run on any free VPS/home PC with a public port". Two peers each send a
## HELLO carrying a shared room code; once paired, every later raw datagram
## from one is forwarded to the other untouched. The relay never parses
## ENet/game payloads, only its own HELLO handshake. Pairing logic itself
## lives in NetRelayRooms (pure, unit-tested); this Node owns the sockets.

const HELLO_PREFIX: String = "TCRELAY1:"
## How often idle peers/rooms are swept; the timeouts themselves live in
## NetRelayRooms.
const SWEEP_SECONDS: float = 5.0

var _server: UDPServer = UDPServer.new()
var _rooms: NetRelayRooms = NetRelayRooms.new()
var _peers: Dictionary[String, PacketPeerUDP] = {}
var _next_sweep: float = 0.0
var port: int = -1


## Starts listening for both peers' HELLO handshakes on `listen_port`.
func start(listen_port: int) -> Error:
	var error: Error = _server.listen(listen_port, "*")
	if error == OK:
		port = listen_port
		print("RELAY_STATE listening=true port=%d" % listen_port)
	else:
		print("RELAY_STATE listening=false error=%s" % error_string(error))
	return error


func _process(_delta: float) -> void:
	if port < 0:
		return
	_server.poll()
	var now: float = NetSession.now()
	while _server.is_connection_available():
		_handle_first_packet(_server.take_connection(), now)
	for key: String in _peers.keys():
		var socket: PacketPeerUDP = _peers[key]
		while socket.get_available_packet_count() > 0:
			_rooms.touch(key, now)
			_forward(key, socket.get_packet())
	if now >= _next_sweep:
		_next_sweep = now + SWEEP_SECONDS
		_sweep(now)


## Releases the sockets of peers the pairing table has timed out, so a HELLO
## flood cannot grow the relay's socket/room tables without bound (spec item 4).
func _sweep(now: float) -> void:
	for key: String in _rooms.expire(now):
		if _peers.has(key):
			(_peers[key] as PacketPeerUDP).close()
			_peers.erase(key)


## Stops listening and releases every paired socket.
func stop() -> void:
	_server.stop()
	for socket: PacketPeerUDP in _peers.values():
		socket.close()
	_peers.clear()
	_rooms = NetRelayRooms.new()
	_next_sweep = 0.0
	port = -1


func _handle_first_packet(connection: PacketPeerUDP, now: float) -> void:
	if connection.get_available_packet_count() <= 0:
		return
	var text: String = connection.get_packet().get_string_from_utf8()
	if not text.begins_with(HELLO_PREFIX):
		return
	var room_code: String = text.substr(HELLO_PREFIX.length())
	var key: String = "%s:%d" % [connection.get_packet_ip(), connection.get_packet_port()]
	_peers[key] = connection
	var partner_key: String = _rooms.announce(room_code, key, now)
	if partner_key != "":
		print("RELAY_STATE paired=true room=%s" % room_code)


func _forward(from_key: String, data: PackedByteArray) -> void:
	var partner_key: String = _rooms.partner_of(from_key)
	if partner_key == "" or not _peers.has(partner_key):
		return
	(_peers[partner_key] as PacketPeerUDP).put_packet(data)


func _exit_tree() -> void:
	stop()
