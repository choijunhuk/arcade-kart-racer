class_name NetRelayRooms
extends RefCounted

## Pure pairing table for the double-NAT UDP relay (spec item 4/7): matches
## two peers that announce the same room code, independent of any actual
## socket, so the pairing logic is unit-testable without real networking.
##
## Everything here expires. A relay listens on a public port, so an attacker
## can spam HELLOs with fresh room codes forever; without bounds the pending,
## partner and last-seen tables grow until the process dies. Pending rooms and
## pairings are dropped after ROOM_IDLE_SECONDS of silence, individual peers
## after PEER_IDLE_SECONDS, and the pending table is hard-capped at
## MAX_PENDING_ROOMS with oldest-first eviction.

## A room with only one side waiting, or a pairing with no traffic, is dropped
## after this long.
const ROOM_IDLE_SECONDS: float = 60.0
## A peer that sends nothing at all for this long is dropped.
const PEER_IDLE_SECONDS: float = 30.0
## Hard ceiling on half-open rooms; the oldest is evicted to make room.
const MAX_PENDING_ROOMS: int = 256

var _pending: Dictionary[String, String] = {}
var _partners: Dictionary[String, String] = {}
var _rooms: Dictionary[String, String] = {}
var _pending_since: Dictionary[String, float] = {}
var _peer_seen: Dictionary[String, float] = {}


## Registers `peer_key` (e.g. "ip:port") under `room_code` at time `now`.
## Returns the partner peer_key once both sides have announced the same code,
## or "" while still waiting. Re-announcing an already-paired peer_key is a
## no-op that just re-confirms its existing partner (and refreshes last-seen).
func announce(room_code: String, peer_key: String, now: float = 0.0) -> String:
	_peer_seen[peer_key] = now
	if _partners.has(peer_key):
		return _partners[peer_key]
	if not _pending.has(room_code):
		_evict_oldest_pending()
		_pending[room_code] = peer_key
		_pending_since[room_code] = now
		_rooms[peer_key] = room_code
		return ""
	var waiting: String = _pending[room_code]
	if waiting == peer_key:
		return ""
	_pending.erase(room_code)
	_pending_since.erase(room_code)
	_partners[peer_key] = waiting
	_partners[waiting] = peer_key
	_rooms[peer_key] = room_code
	return waiting


## Returns the paired partner for `peer_key`, or "" when unpaired.
func partner_of(peer_key: String) -> String:
	return _partners.get(peer_key, "")


## Records traffic from `peer_key` so it (and its partner) stay alive.
func touch(peer_key: String, now: float) -> void:
	if _peer_seen.has(peer_key):
		_peer_seen[peer_key] = now


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
		_pending_since.erase(room)
	_rooms.erase(peer_key)
	_peer_seen.erase(peer_key)


## Drops every peer silent past PEER_IDLE_SECONDS and every half-open room
## older than ROOM_IDLE_SECONDS. Returns the peer keys removed so the caller
## can close their sockets.
func expire(now: float) -> Array[String]:
	var stale: Array[String] = []
	for peer_key: String in _peer_seen.keys():
		if now - float(_peer_seen[peer_key]) > PEER_IDLE_SECONDS:
			stale.append(peer_key)
	for room_code: String in _pending_since.keys():
		if now - float(_pending_since[room_code]) > ROOM_IDLE_SECONDS:
			var waiting: String = _pending.get(room_code, "")
			if waiting != "" and not stale.has(waiting):
				stale.append(waiting)
	for peer_key: String in stale:
		remove(peer_key)
	return stale


## Number of half-open rooms still waiting for a second announcer.
func pending_count() -> int:
	return _pending.size()


func _evict_oldest_pending() -> void:
	if _pending.size() < MAX_PENDING_ROOMS:
		return
	var oldest_room: String = ""
	var oldest_time: float = INF
	for room_code: String in _pending_since.keys():
		if float(_pending_since[room_code]) < oldest_time:
			oldest_time = float(_pending_since[room_code])
			oldest_room = room_code
	if oldest_room == "":
		return
	remove(_pending.get(oldest_room, ""))
	_pending.erase(oldest_room)
	_pending_since.erase(oldest_room)
