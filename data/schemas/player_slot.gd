class_name PlayerSlot
extends Resource

## One local human participant and the hardware/content assigned to its grid slot.

const KEYBOARD_DEVICE_ID: int = -1

@export var device_id: int = KEYBOARD_DEVICE_ID
@export var driver_id: StringName = &"aurora_vale"
@export var kart_id: StringName = &"medium"
@export_range(0, 11) var grid_slot: int = 0


## Returns an independent slot suitable for config and lobby snapshots.
func copy() -> PlayerSlot:
	var result: PlayerSlot = PlayerSlot.new()
	result.device_id = device_id
	result.driver_id = driver_id
	result.kart_id = kart_id
	result.grid_slot = grid_slot
	return result
