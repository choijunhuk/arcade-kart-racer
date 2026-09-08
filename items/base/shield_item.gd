class_name ShieldItem
extends ItemBase

## Timed kart attachment that exposes a single consumable shield charge.

var _available: bool = false


## Attaches one shield charge to the owner kart.
func activate(_frame: InputFrame) -> void:
	_available = true
	owner_kart.call("install_shield", self)
	global_position = owner_kart.global_position


## Follows the owner and expires at ItemData.duration.
func tick(dt: float) -> void:
	if is_instance_valid(owner_kart):
		global_position = owner_kart.global_position
	if _advance_lifetime(dt):
		_available = false


## Consumes the charge exactly once and expires the attachment.
func consume() -> bool:
	if not _available or is_expired():
		return false
	_available = false
	expire()
	return true


## Returns whether the shield can absorb a hit.
func is_available() -> bool:
	return _available and not is_expired()
