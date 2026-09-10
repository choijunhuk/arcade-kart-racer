class_name NetRelayClient
extends Node

## Local-side counterpart to NetRelayServer (spec item 4). Both the hosting
## machine and the joining machine run one instance when "Use relay" is
## chosen, letting a real ENetMultiplayerPeer talk to a public relay through
## loopback so neither side needs an inbound port-forward:
## - Host role (`dial_target_port > 0`): the real ENet server listens on
##   127.0.0.1/that port; this proxy dials it and forwards relay traffic in.
## - Join role (`dial_target_port <= 0`): the real ENet client is pointed at
##   this proxy's loopback port; this proxy learns that local address from
##   the client's first packet, then forwards relay traffic to it.
## The relay only ever forwards opaque bytes; it never touches ENet objects.

signal paired()

const HELLO_PREFIX: String = "TCRELAY1:"
const HELLO_INTERVAL_SECONDS: float = 1.0

var running: bool = false
var _relay_socket: PacketPeerUDP = PacketPeerUDP.new()
var _loopback_socket: PacketPeerUDP = PacketPeerUDP.new()
var _room_code: String = ""
var _hello_elapsed: float = 0.0
var _local_dest_set: bool = false
var _paired: bool = false


## Starts the loopback<->relay bridge; see the class doc for role semantics.
func start(loopback_port: int, dial_target_port: int, relay_ip: String, relay_port: int, room_code: String) -> Error:
	_room_code = room_code
	var bind_error: Error = _loopback_socket.bind(loopback_port, "127.0.0.1")
	if bind_error != OK:
		return bind_error
	if dial_target_port > 0:
		_loopback_socket.set_dest_address("127.0.0.1", dial_target_port)
		_local_dest_set = true
	var connect_error: Error = _relay_socket.connect_to_host(relay_ip, relay_port)
	if connect_error != OK:
		_loopback_socket.close()
		return connect_error
	running = true
	_hello_elapsed = HELLO_INTERVAL_SECONDS
	_paired = false
	return OK


func _process(delta: float) -> void:
	if not running:
		return
	_hello_elapsed += delta
	if _hello_elapsed >= HELLO_INTERVAL_SECONDS:
		_hello_elapsed = 0.0
		_relay_socket.put_packet((HELLO_PREFIX + _room_code).to_utf8_buffer())
	while _relay_socket.get_available_packet_count() > 0:
		var data: PackedByteArray = _relay_socket.get_packet()
		if not _paired:
			_paired = true
			paired.emit()
		if _local_dest_set:
			_loopback_socket.put_packet(data)
	while _loopback_socket.get_available_packet_count() > 0:
		var data: PackedByteArray = _loopback_socket.get_packet()
		if not _local_dest_set:
			_local_dest_set = true
			_loopback_socket.set_dest_address(_loopback_socket.get_packet_ip(), _loopback_socket.get_packet_port())
		_relay_socket.put_packet(data)


## Closes both sockets; safe to call even if `start` was never called.
func stop() -> void:
	running = false
	_relay_socket.close()
	_loopback_socket.close()


func _exit_tree() -> void:
	stop()
