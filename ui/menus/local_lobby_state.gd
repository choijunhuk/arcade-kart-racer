class_name LocalLobbyState
extends RefCounted

## Pure local-lobby ownership, selection, and readiness model.

const MAX_PLAYERS: int = 4
const MIN_PLAYERS_TO_START: int = 2

var _default_driver_id: StringName
var _default_kart_id: StringName
var _players: Array[PlayerSlot] = []
var _ready_by_device: Dictionary[int, bool] = {}


func _init(
	default_driver_id: StringName = &"aurora_vale",
	default_kart_id: StringName = &"medium",
) -> void:
	_default_driver_id = default_driver_id
	_default_kart_id = default_kart_id


## Adds one unique device, keeping keyboard as player one when present.
func join(device_id: int) -> bool:
	if _players.size() >= MAX_PLAYERS or player_index_for_device(device_id) >= 0:
		return false
	var slot: PlayerSlot = PlayerSlot.new()
	slot.device_id = device_id
	slot.driver_id = _default_driver_id
	slot.kart_id = _default_kart_id
	if device_id == PlayerSlot.KEYBOARD_DEVICE_ID:
		_players.push_front(slot)
	else:
		_players.append(slot)
	_ready_by_device[device_id] = false
	_reindex()
	return true


## Removes a joined device and compacts player/grid identities.
func leave(device_id: int) -> bool:
	var index: int = player_index_for_device(device_id)
	if index < 0:
		return false
	_players.remove_at(index)
	_ready_by_device.erase(device_id)
	_reindex()
	return true


## Updates the selected content identifiers for one joined player.
func set_selection(device_id: int, driver_id: StringName, kart_id: StringName) -> bool:
	var index: int = player_index_for_device(device_id)
	if index < 0:
		return false
	_players[index].driver_id = driver_id
	_players[index].kart_id = kart_id
	_ready_by_device[device_id] = false
	return true


## Changes readiness for one joined device.
func set_ready(device_id: int, ready: bool) -> bool:
	if player_index_for_device(device_id) < 0:
		return false
	_ready_by_device[device_id] = ready
	return true


## Returns whether the joined device is ready.
func is_ready(device_id: int) -> bool:
	return bool(_ready_by_device.get(device_id, false))


## Returns true when at least two joined players are all ready.
func can_start() -> bool:
	if _players.size() < MIN_PLAYERS_TO_START:
		return false
	for slot: PlayerSlot in _players:
		if not is_ready(slot.device_id):
			return false
	return true


## Returns the stable current player index for a device, or -1.
func player_index_for_device(device_id: int) -> int:
	for index: int in range(_players.size()):
		if _players[index].device_id == device_id:
			return index
	return -1


## Returns independent player-slot snapshots in P1-P4 order.
func players() -> Array[PlayerSlot]:
	var result: Array[PlayerSlot] = []
	for slot: PlayerSlot in _players:
		result.append(slot.copy())
	return result


func _reindex() -> void:
	for index: int in range(_players.size()):
		_players[index].grid_slot = index
