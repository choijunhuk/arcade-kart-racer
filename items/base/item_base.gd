@abstract
class_name ItemBase
extends Node3D

## Shared deterministic lifecycle for every pooled item instance.

signal finished(item: ItemBase)

var data: ItemData
var owner_kart: KartController
var context: ItemContext
var elapsed_seconds: float = 0.0
var _expired: bool = false


## Resets a pooled instance with immutable content and race context.
func setup(item_data: ItemData, kart: KartController, item_context: ItemContext) -> void:
	data = item_data
	owner_kart = kart
	context = item_context
	elapsed_seconds = 0.0
	_expired = false
	visible = true


## Activates direction/effect state from the use edge snapshot.
@abstract func activate(frame: InputFrame) -> void


## Advances the common lifetime; category overrides call `_advance_lifetime`.
func tick(dt: float) -> void:
	_advance_lifetime(dt)


## Applies the data-selected hit type and emits the item hit event on success.
func on_hit(target: KartController) -> void:
	if target == null or target == owner_kart or data == null:
		return
	var hit_type: HitReactor.HitType = data.hit_type as HitReactor.HitType
	if target.apply_hit(hit_type, owner_kart):
		EventBus.item_hit.emit(owner_kart, target, data.id)


## Emits the one-shot completion signal used by ItemManager to return the pool.
func expire() -> void:
	if _expired:
		return
	_expired = true
	finished.emit(self)


## Returns whether this instance has completed and awaits pool return.
func is_expired() -> bool:
	return _expired


## Returns whether AI should treat this live item as an approaching projectile.
func is_projectile() -> bool:
	return false


## Returns whether current race state permits consuming the held slot item.
func can_activate() -> bool:
	return true


## Returns whether manager-wide live state permits another instance.
func can_spawn(_active_items: Array[ItemBase]) -> bool:
	return true


func _advance_lifetime(dt: float) -> bool:
	if _expired:
		return true
	elapsed_seconds += maxf(dt, 0.0)
	if data != null and data.lifetime > 0.0 and elapsed_seconds >= data.lifetime:
		expire()
		return true
	return false
