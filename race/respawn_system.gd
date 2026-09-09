class_name RespawnSystem
extends Node

## Runs fade, teleport/protection, and frozen phases from physics ticks. The
## caller supplies track-specific respawn lookup so Race never leaks into Kart.

## Metres stepped back along the racing line per occupied-spot retry (§14.5).
const RESPAWN_STEP_BACK: float = 3.0
const RESPAWN_OCCUPANCY_RADIUS: float = 2.0
const RESPAWN_MAX_ATTEMPTS: int = 6

enum RespawnPhase {
	IDLE,
	FADE,
	FROZEN,
}

class Registration extends RefCounted:
	var kart: KartController
	var get_respawn_transform: Callable
	var phase: RespawnPhase = RespawnPhase.IDLE
	var timer: float = 0.0
	var stuck_timer: float = 0.0


@export var tuning: PhysicsTuning = preload("res://data/tuning/physics_default.tres")

var _registrations: Dictionary[int, Registration] = {}


func _physics_process(delta: float) -> void:
	for key: int in _registrations.keys():
		var registration: Registration = _registrations[key]
		if not is_instance_valid(registration.kart):
			_registrations.erase(key)
			continue
		_update_registration(registration, delta)


## Registers a kart and a callable returning its current safe Transform3D.
func register_kart(kart: KartController, get_respawn_transform: Callable) -> void:
	var registration: Registration = Registration.new()
	registration.kart = kart
	registration.get_respawn_transform = get_respawn_transform
	_registrations[kart.get_instance_id()] = registration


## Removes a kart from kill-zone and stuck handling.
func unregister_kart(kart: KartController) -> void:
	_registrations.erase(kart.get_instance_id())


## Clears all kart registrations for an in-place race restart.
func clear_karts() -> void:
	_registrations.clear()


## Connects a KillZone once to this system's request path.
func register_kill_zone(zone: KillZone) -> void:
	if not zone.body_fell.is_connected(_on_kill_zone_body_fell):
		zone.body_fell.connect(_on_kill_zone_body_fell)


func _on_kill_zone_body_fell(body: Node3D) -> void:
	if body is KartController:
		request_respawn(body as KartController)


## Begins a respawn unless this kart is already in its respawn sequence.
func request_respawn(kart: KartController) -> void:
	var registration: Registration = _registrations.get(kart.get_instance_id()) as Registration
	if registration == null or registration.phase != RespawnPhase.IDLE:
		return
	registration.phase = RespawnPhase.FADE
	registration.timer = tuning.respawn_fade_duration
	registration.stuck_timer = 0.0
	kart.begin_respawn()


func _update_registration(registration: Registration, delta: float) -> void:
	match registration.phase:
		RespawnPhase.IDLE:
			_update_stuck_timer(registration, delta)
		RespawnPhase.FADE:
			registration.timer = maxf(0.0, registration.timer - delta)
			if registration.timer <= 0.0:
				_teleport(registration)
		RespawnPhase.FROZEN:
			registration.timer = maxf(0.0, registration.timer - delta)
			if registration.timer <= 0.0:
				registration.phase = RespawnPhase.IDLE
				registration.kart.finish_respawn()


func _update_stuck_timer(registration: Registration, delta: float) -> void:
	var kart: KartController = registration.kart
	if kart.get_state() == KartState.HIT:
		registration.stuck_timer = 0.0
		return
	if kart.is_throttle_held() and absf(kart.get_speed()) < tuning.stuck_speed_threshold:
		registration.stuck_timer += delta
		if registration.stuck_timer >= tuning.stuck_duration:
			request_respawn(kart)
	else:
		registration.stuck_timer = 0.0


func _teleport(registration: Registration) -> void:
	if not registration.get_respawn_transform.is_valid():
		push_error("RespawnSystem requires a valid respawn-transform callable")
		registration.phase = RespawnPhase.IDLE
		registration.kart.finish_respawn()
		return
	var result: Variant = registration.get_respawn_transform.call(registration.kart)
	if not result is Transform3D:
		push_error("Respawn transform callable must return Transform3D")
		registration.phase = RespawnPhase.IDLE
		registration.kart.finish_respawn()
		return
	var target: Transform3D = result
	registration.kart.teleport_for_respawn(target)
	registration.phase = RespawnPhase.FROZEN
	registration.timer = tuning.respawn_frozen_duration
	EventBus.kart_respawned.emit(registration.kart)


## Resolves a racing-line-oriented respawn transform from `kart`'s last
## passed checkpoint (via `lap_tracker`), stepping back `RESPAWN_STEP_BACK`
## along the line each time the candidate spot is occupied by another kart
## (spec §14.5). Static/pure aside from the read-only lookups it is handed.
static func resolve_respawn_transform(
	kart: KartController, lap_tracker: LapTracker, racing_line: RacingLine, other_karts: Array[KartController],
) -> Transform3D:
	var respawn_point: Marker3D = lap_tracker.get_respawn_point(kart) if lap_tracker != null else null
	if respawn_point == null or racing_line == null:
		return kart.global_transform
	var offset: float = racing_line.offset_at(respawn_point.global_position)
	for attempt: int in range(RESPAWN_MAX_ATTEMPTS):
		var candidate_offset: float = offset - RESPAWN_STEP_BACK * float(attempt)
		var position: Vector3 = racing_line.sample(candidate_offset)
		if not _is_position_occupied(position, kart, other_karts):
			return _oriented_transform(position, racing_line.tangent_at(candidate_offset))
	var fallback_offset: float = offset - RESPAWN_STEP_BACK * float(RESPAWN_MAX_ATTEMPTS)
	return _oriented_transform(racing_line.sample(fallback_offset), racing_line.tangent_at(fallback_offset))


static func _is_position_occupied(position: Vector3, self_kart: KartController, other_karts: Array[KartController]) -> bool:
	for other: KartController in other_karts:
		if other == self_kart or not is_instance_valid(other):
			continue
		if other.global_position.distance_to(position) < RESPAWN_OCCUPANCY_RADIUS:
			return true
	return false


static func _oriented_transform(position: Vector3, forward: Vector3) -> Transform3D:
	forward.y = 0.0
	var facing: Vector3 = forward if forward.length() > 0.001 else Vector3.FORWARD
	return Transform3D(Basis.looking_at(facing, Vector3.UP), position + Vector3.UP * 0.05)
