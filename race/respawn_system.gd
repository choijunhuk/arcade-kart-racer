class_name RespawnSystem
extends Node

## Runs fade, teleport/protection, and frozen phases from physics ticks. The
## caller supplies track-specific respawn lookup so Race never leaks into Kart.

## Metres stepped back along the racing line per occupied-spot retry (§14.5).
const RESPAWN_STEP_BACK: float = 3.0
const RESPAWN_OCCUPANCY_RADIUS: float = 2.0
const RESPAWN_MAX_ATTEMPTS: int = 6
const WALL_FALL_GUARD_SECONDS: float = 1.0
const WALL_FALL_RECOVERY_DEPTH: float = 3.0
const DRIVEABLE_SURFACE_META: StringName = &"driveable_surface"
## Corner-safe respawn (19-D item 1): a checkpoint inside a tight corner
## (Track01's closing arc has no outer wall) would release the kart facing the
## tangent with only ~18 m of road before the cliff, so a full-throttle restart
## fell straight off again in a loop. A spot inside such a corner steps back
## along the line until this much road ahead is no tighter than the limit.
const RESPAWN_CLEAR_RUN: float = 40.0
const RESPAWN_MAX_CURVATURE: float = 0.03
const RESPAWN_MAX_CORNER_STEP_BACK: float = 90.0
## Never step back past (or right onto) the previous checkpoint gate.
const RESPAWN_PREVIOUS_GATE_MARGIN: float = 6.0

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
	var track_motion: bool = false
	var previous_position: Vector3
	var last_grounded_transform: Transform3D
	## False until the first processed tick re-reads the pose: registration
	## happens on the raw grid slot, before GridSettle lifts the kart.
	var pose_seeded: bool = false
	var wall_fall_guard_remaining: float = 0.0
	var pending_respawn_transform: Variant = null


@export var tuning: PhysicsTuning = preload("res://data/tuning/physics_default.tres")

var _registrations: Dictionary[int, Registration] = {}


func _ready() -> void:
	if not EventBus.wall_impacted.is_connected(_on_wall_impacted):
		EventBus.wall_impacted.connect(_on_wall_impacted)


func _physics_process(delta: float) -> void:
	for key: int in _registrations.keys():
		var registration: Registration = _registrations[key]
		if not is_instance_valid(registration.kart):
			_registrations.erase(key)
			continue
		_update_registration(registration, delta)


## Registers a kart and a callable returning its current safe Transform3D.
func register_kart(kart: KartController, get_respawn_transform: Callable, track_motion: bool = false) -> void:
	var registration: Registration = Registration.new()
	registration.kart = kart
	registration.get_respawn_transform = get_respawn_transform
	registration.track_motion = track_motion
	registration.previous_position = kart.global_position
	registration.last_grounded_transform = kart.global_transform
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
	if not registration.pose_seeded:
		registration.pose_seeded = true
		registration.previous_position = registration.kart.global_position
		registration.last_grounded_transform = registration.kart.global_transform
	if _update_wall_fall_guard(registration, delta):
		return
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


func _update_wall_fall_guard(registration: Registration, delta: float) -> bool:
	if registration.phase != RespawnPhase.IDLE or registration.kart.network_replica:
		registration.wall_fall_guard_remaining = 0.0
		return false
	var kart: KartController = registration.kart
	if registration.wall_fall_guard_remaining <= 0.0:
		if kart.is_grounded():
			registration.last_grounded_transform = kart.global_transform
		return false
	registration.wall_fall_guard_remaining = maxf(0.0, registration.wall_fall_guard_remaining - delta)
	if kart.global_position.y >= registration.last_grounded_transform.origin.y - WALL_FALL_RECOVERY_DEPTH:
		return false
	if not _has_driveable_surface_above(kart, registration.last_grounded_transform.origin.y):
		return false
	registration.pending_respawn_transform = registration.last_grounded_transform
	request_respawn(kart)
	registration.previous_position = kart.global_position
	registration.wall_fall_guard_remaining = 0.0
	return true


func _has_driveable_surface_above(kart: KartController, target_y: float) -> bool:
	var origin: Vector3 = kart.global_position
	var target: Vector3 = Vector3(origin.x, target_y + 1.0, origin.z)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target, 1)
	var hit: Dictionary = kart.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: CollisionObject3D = hit.get("collider") as CollisionObject3D
	var shape_index: int = int(hit.get("shape", -1))
	if collider == null or shape_index < 0:
		return false
	var owner_id: int = collider.shape_find_owner(shape_index)
	var owner: Object = collider.shape_owner_get_owner(owner_id)
	return owner != null and bool(owner.get_meta(DRIVEABLE_SURFACE_META, false))


func _on_wall_impacted(body: Node) -> void:
	if not body is KartController:
		return
	var kart: KartController = body as KartController
	var registration: Registration = _registrations.get(kart.get_instance_id()) as Registration
	if registration == null or registration.phase != RespawnPhase.IDLE or kart.network_replica:
		return
	registration.wall_fall_guard_remaining = WALL_FALL_GUARD_SECONDS


func _update_stuck_timer(registration: Registration, delta: float) -> void:
	var kart: KartController = registration.kart
	var speed: float = absf(kart.get_speed())
	if registration.track_motion:
		var travel: Vector3 = kart.global_position - registration.previous_position
		travel.y = 0.0
		speed = minf(speed, travel.length() / delta) if delta > 0.0 else speed
		registration.previous_position = kart.global_position
	# Repeated wall/self BUMP hits must not indefinitely reset a network
	# human's recovery (a kart jammed against a wall keeps re-triggering
	# BUMP, which would otherwise never let the stuck timer accumulate).
	# Item-hit chains (SPIN_OUT/TUMBLE) are a different cause: the kart is
	# legitimately incapacitated, not stuck, so those must keep resetting
	# the timer even for network humans, or a long hit chain would force
	# an unwanted respawn mid-incapacitation.
	var suppress_reset: bool = registration.track_motion and kart.get_hit_state() == HitReactor.HitType.BUMP
	if kart.get_state() in [KartState.FROZEN, KartState.RESPAWNING, KartState.FINISHED] or (kart.get_state() == KartState.HIT and not suppress_reset):
		registration.stuck_timer = 0.0
		return
	if kart.is_throttle_held() and speed < tuning.stuck_speed_threshold:
		registration.stuck_timer += delta
		if registration.stuck_timer >= tuning.stuck_duration:
			request_respawn(kart)
	else:
		registration.stuck_timer = 0.0


func _teleport(registration: Registration) -> void:
	if registration.pending_respawn_transform is Transform3D:
		var guarded_target: Transform3D = registration.pending_respawn_transform
		registration.pending_respawn_transform = null
		_finish_teleport(registration, guarded_target)
		return
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
	_finish_teleport(registration, target)


func _finish_teleport(registration: Registration, target: Transform3D) -> void:
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
	var offset: float = corner_safe_offset(
		racing_line, racing_line.offset_at(respawn_point.global_position),
		_previous_gate_distance(respawn_point, racing_line),
	)
	for attempt: int in range(RESPAWN_MAX_ATTEMPTS):
		var candidate_offset: float = offset - RESPAWN_STEP_BACK * float(attempt)
		var position: Vector3 = racing_line.sample(candidate_offset)
		if not _is_position_occupied(position, kart, other_karts):
			return _oriented_transform(position, racing_line.tangent_at(candidate_offset))
	var fallback_offset: float = offset - RESPAWN_STEP_BACK * float(RESPAWN_MAX_ATTEMPTS)
	return _oriented_transform(racing_line.sample(fallback_offset), racing_line.tangent_at(fallback_offset))


## When the checkpoint spot itself sits inside a corner tighter than
## `RESPAWN_MAX_CURVATURE`, steps `offset` back in `RESPAWN_STEP_BACK`
## increments (at most `max_step_back` metres) until the next
## `RESPAWN_CLEAR_RUN` metres of line stay within that limit. If the limit
## (closely spaced gates) runs out first, returns the candidate in
## [offset - limit, offset] with the lowest mean curvature ahead instead of
## the raw apex. A spot outside a corner keeps the exact checkpoint offset
## (spec §14.5).
static func corner_safe_offset(racing_line: RacingLine, offset: float, max_step_back: float) -> float:
	if absf(racing_line.curvature_at(offset)) <= RESPAWN_MAX_CURVATURE:
		return offset
	var limit: float = clampf(max_step_back, 0.0, RESPAWN_MAX_CORNER_STEP_BACK)
	var length: float = maxf(racing_line.length(), 0.001)
	var best_step: float = 0.0
	var best_score: float = INF
	var step_back: float = 0.0
	while true:
		if racing_line.max_curvature_in(offset - step_back, RESPAWN_CLEAR_RUN) <= RESPAWN_MAX_CURVATURE:
			return fposmod(offset - step_back, length)
		var score: float = mean_curvature_ahead(racing_line, offset - step_back)
		if score < best_score:
			best_score = score
			best_step = step_back
		if step_back >= limit:
			break
		step_back = minf(step_back + RESPAWN_STEP_BACK, limit)
	return fposmod(offset - best_step, length)


## Mean absolute curvature over the next `RESPAWN_CLEAR_RUN` metres.
static func mean_curvature_ahead(racing_line: RacingLine, offset: float) -> float:
	var samples: int = 20
	var total: float = 0.0
	for index: int in range(samples + 1):
		total += absf(racing_line.curvature_at(offset + RESPAWN_CLEAR_RUN * float(index) / float(samples)))
	return total / float(samples + 1)


## Line distance back to the previous checkpoint gate minus a margin, read
## from the respawn marker's own Checkpoint siblings (no upward race lookup).
static func _previous_gate_distance(respawn_point: Marker3D, racing_line: RacingLine) -> float:
	var checkpoint: Checkpoint = respawn_point.get_parent() as Checkpoint
	var container: Node = checkpoint.get_parent() if checkpoint != null else null
	if container == null:
		return 0.0
	var gates: Array[Checkpoint] = []
	for child: Node in container.get_children():
		if child is Checkpoint:
			gates.append(child as Checkpoint)
	if gates.size() < 2:
		return RESPAWN_MAX_CORNER_STEP_BACK
	var previous: Checkpoint = gates[(gates.find(checkpoint) - 1 + gates.size()) % gates.size()]
	var gap: float = fposmod(checkpoint.offset - previous.offset, maxf(racing_line.length(), 0.001))
	return maxf(0.0, gap - RESPAWN_PREVIOUS_GATE_MARGIN)


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
