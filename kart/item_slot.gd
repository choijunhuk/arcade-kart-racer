class_name ItemSlot
extends Node

## Holds one item, a tick-driven roulette, and one pending input-edge request.

var roulette_active: bool = false

var _item: ItemData
var _roulette: ItemRoulette = ItemRoulette.new()
var _use_requested: bool = false
var _last_input_tick: int = -1


## Replaces the held item immediately and ends any active roulette.
func set_item(item: ItemData) -> void:
	_item = item
	roulette_active = false


## Removes and returns the held item.
func clear_item() -> ItemData:
	var previous: ItemData = _item
	_item = null
	_use_requested = false
	return previous


## Starts a reveal while keeping the usable slot empty until it finishes.
func begin_roulette(result: ItemData) -> void:
	_item = null
	_use_requested = false
	_roulette.start(result)
	roulette_active = _roulette.is_active()


## Advances roulette state and returns true on the reveal tick.
func tick_roulette(dt: float) -> bool:
	if not roulette_active or not _roulette.tick(dt):
		return false
	roulette_active = false
	_item = _roulette.get_result()
	return true


## Captures a unique InputFrame item edge without repeating an AI-held frame.
func capture_input(frame: InputFrame) -> void:
	if frame == null or frame.tick == _last_input_tick:
		return
	_last_input_tick = frame.tick
	if frame.item and has_item() and not roulette_active:
		_use_requested = true


## Consumes the pending request exactly once.
func consume_use_request() -> bool:
	var requested: bool = _use_requested
	_use_requested = false
	return requested


## Returns whether one usable item is held.
func has_item() -> bool:
	return _item != null


## Returns the held category, or the harmless default when empty.
func get_category() -> ItemData.ItemCategory:
	return _item.category if _item != null else ItemData.ItemCategory.PROJECTILE


## Returns the held data id, or an empty id when empty.
func get_item_id() -> StringName:
	return _item.id if _item != null else &""


## Returns the read-only held resource reference.
func get_item_data() -> ItemData:
	return _item


## Returns roulette progress for presentation observers.
func get_roulette_progress() -> float:
	return _roulette.get_progress()
