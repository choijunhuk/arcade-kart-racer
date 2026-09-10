class_name NetRelayRooms
extends RefCounted

## Pure pairing table for the double-NAT UDP relay (spec item 4/7): matches
## two peers that announce the same room code, independent of any actual
## socket, so the pairing logic is unit-testable without real networking.
var _pending: Dictionary[String, String] = {}
var _partners: Dictionary[String, String] = {}
var _rooms: Dictionary[String, String] = {}


## Registers `peer_key` (e.g. "ip:port") under `room_code`. Returns the
## partner peer_key once both sides have announced the same code, or ""
## while still waiting. Re-announcing an already-paired peer_key is a no-op
## that just re-confirms its existing partner.
func announce(room_code: String, peer_key: String) -> String:
	if _partners.has(peer_key):
		return _partners[peer_key]
	if not _pending.has(room_code):
		_pending[room_code] = peer_key
		_rooms[peer_key] = room_code
		return ""
	var waiting: String = _pending[room_code]
	if waiting == peer_key:
		return ""
	_pending.erase(room_code)
	_partners[peer_key] = waiting
	_partners[waiting] = peer_key
	_rooms[peer_key] = room_code
	return waiting


## Returns the paired partner for `peer_key`, or "" when unpaired.
func partner_of(peer_key: String) -> String:
	return _partners.get(peer_key, "")


## Drops a peer (disconnect/timeout), clearing its pairing and any pending
## room slot it was occupying.
func remove(peer_key: String) -> void:
	var partner: String = _partners.get(peer_key, "")
	if partner != "":
		_partners.erase(partner)
	_partners.erase(peer_key)
	var room: String = _rooms.get(peer_key, "")
	if room != "" and _pending.get(room, "") == peer_key:
		_pending.erase(room)
	_rooms.erase(peer_key)
