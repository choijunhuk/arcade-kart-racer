class_name HitReactor
extends Node

## Owns deterministic hit durations and post-hit invulnerability. Physics
## effects are applied once on acceptance; visuals read normalized progress.

enum HitType {
	BUMP,
	SPIN_OUT,
	TUMBLE,
	SQUASH,
}

var _controller: KartController
var _physics: KartPhysics
var _tuning: PhysicsTuning
var _hit_type: HitType = HitType.BUMP
var _duration: float = 0.0
var _remaining: float = 0.0
var _invulnerability_remaining: float = 0.0
var _bump_from_item: bool = false
var _bump_item_speed_factor: float = 1.0


## Wires optional runtime owners; null owners keep the timer unit-testable.
func setup(controller: KartController, physics: KartPhysics, tuning: PhysicsTuning) -> void:
	_controller = controller
	_physics = physics
	_tuning = tuning


## Applies a hit unless invulnerability is active, returning acceptance.
## `from_item` distinguishes an item hit (always shield-absorbable, even a
## BUMP like Pulse Blast, spec §12.2) from a kart-vs-kart BUMP, which still
## bypasses shields. `item_speed_factor` scales speed for an item BUMP only
## (Pulse Blast's `ItemData.power`); it is ignored for every other hit type.
func apply(type: HitType, _source: Node, from_item: bool = false, item_speed_factor: float = 1.0) -> bool:
	if (from_item or type != HitType.BUMP) and _controller != null and _controller.consume_shield():
		return false
	if is_invulnerable():
		return false
	_hit_type = type
	_duration = _duration_for(type)
	_remaining = _duration
	_invulnerability_remaining = _tuning.hit_invulnerability_duration
	_bump_from_item = from_item
	_bump_item_speed_factor = item_speed_factor
	_apply_initial_physics(type, from_item, item_speed_factor)
	if is_inside_tree() and _controller != null:
		EventBus.kart_hit.emit(_controller, type)
	return true


## Advances hit and invulnerability timers without coroutine timers.
func tick(delta: float) -> void:
	_remaining = maxf(0.0, _remaining - delta)
	_invulnerability_remaining = maxf(0.0, _invulnerability_remaining - delta)
	if is_active() and _hit_type == HitType.SQUASH and _physics != null:
		_physics.cap_speed(_tuning.hit_squash_speed_cap_factor)


## Clears reaction and protection timers for debug/reset tooling.
func clear() -> void:
	_remaining = 0.0
	_invulnerability_remaining = 0.0


## Grants invulnerability for at least the requested duration.
func grant_invulnerability(duration: float) -> void:
	_invulnerability_remaining = maxf(_invulnerability_remaining, duration)


## Returns whether a visual/gameplay hit reaction is active.
func is_active() -> bool:
	return _remaining > 0.0


## Returns whether a new hit must be rejected.
func is_invulnerable() -> bool:
	return _invulnerability_remaining > 0.0


## Returns the current hit enum for debug and visual presentation.
func get_hit_type() -> HitType:
	return _hit_type


## Returns seconds left in the current reaction.
func get_remaining_time() -> float:
	return _remaining


## Returns normalized elapsed progress in the active reaction.
func get_progress() -> float:
	if _duration <= 0.0:
		return 0.0
	return clampf(1.0 - (_remaining / _duration), 0.0, 1.0)


## Returns the one-shot speed factor associated with the current hit.
func get_speed_factor() -> float:
	match _hit_type:
		HitType.BUMP:
			return _bump_item_speed_factor if _bump_from_item else 1.0
		HitType.SPIN_OUT:
			return _tuning.hit_spin_out_speed_factor
		HitType.TUMBLE:
			return _tuning.hit_tumble_speed_factor
		HitType.SQUASH:
			return _tuning.hit_squash_speed_cap_factor
		_:
			return 1.0


## Returns analog driving authority for the active hit type.
func get_control_factor() -> float:
	if not is_active():
		return 1.0
	match _hit_type:
		HitType.BUMP:
			return _tuning.hit_bump_control_factor
		HitType.SQUASH:
			return 1.0
		_:
			return 0.0


## Produces a hit-filtered input snapshot without mutating provider data.
func filter_input(frame: InputFrame) -> InputFrame:
	var factor: float = get_control_factor()
	if factor <= 0.0:
		return InputFrame.zero()
	var filtered: InputFrame = frame.clone()
	filtered.throttle *= factor
	filtered.brake *= factor
	filtered.steer *= factor
	if factor < 1.0:
		filtered.drift = false
		filtered.drift_pressed = false
		filtered.item = false
	return filtered


func _duration_for(type: HitType) -> float:
	match type:
		HitType.BUMP:
			return _tuning.hit_bump_duration
		HitType.SPIN_OUT:
			return _tuning.hit_spin_out_duration
		HitType.TUMBLE:
			return _tuning.hit_tumble_duration
		HitType.SQUASH:
			return _tuning.hit_squash_duration
	return 0.0


func _apply_initial_physics(type: HitType, from_item: bool, item_speed_factor: float) -> void:
	if _physics == null:
		return
	match type:
		HitType.BUMP:
			if from_item:
				_physics.scale_speed(item_speed_factor)
		HitType.SPIN_OUT:
			_physics.scale_speed(_tuning.hit_spin_out_speed_factor)
		HitType.TUMBLE:
			_physics.scale_speed(_tuning.hit_tumble_speed_factor)
		HitType.SQUASH:
			_physics.cap_speed(_tuning.hit_squash_speed_cap_factor)
