class_name ItemContext
extends RefCounted

## Immutable-after-configuration race services available to live items.

var _karts: Array[KartController] = []
var _position_tracker: PositionTracker
var _racing_line: RacingLine
var _rng: RandomNumberGenerator
var _item_manager: Node


## Captures race references once; getters do not expose the mutable kart array.
func configure(
	karts: Array[KartController], position_tracker: PositionTracker,
	racing_line: RacingLine, rng: RandomNumberGenerator, item_manager: Node,
) -> void:
	_karts = karts.duplicate()
	_position_tracker = position_tracker
	_racing_line = racing_line
	_rng = rng
	_item_manager = item_manager


## Returns a defensive copy of registered race karts.
func get_karts() -> Array[KartController]:
	return _karts.duplicate()


## Returns the race ranking source.
func get_position_tracker() -> PositionTracker:
	return _position_tracker


## Returns the baked line used by homing movement.
func get_racing_line() -> RacingLine:
	return _racing_line


## Returns the race-seeded random stream.
func get_rng() -> RandomNumberGenerator:
	return _rng


## Returns the race-local manager for registries and pooled effects.
func get_item_manager() -> Node:
	return _item_manager
