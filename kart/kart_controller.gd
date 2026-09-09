class_name KartController
extends CharacterBody3D
## Coordinates kart child components and exposes a read-only state API to
## camera/HUD/AI. Never reads the `Input` singleton directly (spec §23);
## drives from whatever `InputProvider` is installed. Spec: §8, §9.3.
signal state_changed(old_state: int, new_state: int)
signal replay_event_received(event: Dictionary)
const ENGINE_BOOST_PITCH_ADD: float = 0.3
@export var kart_data: KartData = preload("res://data/karts/medium.tres")
@export var driver_data: DriverData
@export var tuning: PhysicsTuning = preload("res://data/tuning/physics_default.tres")
@onready var _physics: KartPhysics = $KartPhysics
@onready var _ground_rays: Node3D = $GroundRays
@onready var _terrain_sensor: TerrainSensor = $TerrainSensor
@onready var _terrain_probe: Area3D = $TerrainProbe
@onready var _slipstream_sensor: SlipstreamSensor = $SlipstreamSensor
@onready var _slipstream_cast: ShapeCast3D = $SlipstreamSensor/ShapeCast3D
@onready var _hit_reactor: HitReactor = $HitReactor
@onready var drift_controller: DriftController = $DriftController
@onready var boost_controller: BoostController = $BoostController
@onready var item_slot: ItemSlot = $ItemSlot
var input_provider: InputProvider = InputProvider.new()
var state: int = KartState.GROUNDED
var _current_terrain_id: StringName = &"asphalt"
var _slipstream_active: bool = false
var _respawning: bool = false
var _ungrounded_ticks: int = 0
var _throttle_held: bool = false
var _latest_input_frame: InputFrame = InputFrame.zero()
var _race_frozen: bool = false
var _finished: bool = false
var _start_wheelspin_remaining: float = 0.0
var _shield_item: ShieldItem
var _last_landing_speed: float = 0.0
var network_replica: bool = false
func _ready() -> void:
	var rays: Array[RayCast3D] = []
	for child: Node in _ground_rays.get_children():
		if child is RayCast3D:
			rays.append(child as RayCast3D)
	_physics.setup(self, rays, tuning, kart_data)
	_terrain_sensor.setup(_terrain_probe, rays, kart_data)
	_slipstream_sensor.setup(_slipstream_cast, self, tuning)
	_hit_reactor.setup(self, _physics, tuning)
	drift_controller.configure(tuning, kart_data)
	drift_controller.set_owner_kart(self)
	boost_controller.configure(tuning, kart_data)
	boost_controller.set_owner_kart(self)
	drift_controller.hop_requested.connect(_physics.hop)
	drift_controller.boost_requested.connect(boost_controller.request)
	_physics.wall_head_on.connect(_on_wall_head_on)
	_physics.landed.connect(_on_landed)
func _physics_process(delta: float) -> void:
	step_input(input_provider.get_frame(), delta)

## Runs the ordinary fixed-step physics from explicit input, optionally without feedback.
func step_input(raw: InputFrame, delta: float, replaying: bool = false) -> void:
	var was_blocked: bool = EventBus.is_blocking_signals()
	var muted: bool = replaying or network_replica
	if muted:
		EventBus.set_block_signals(true)
	var frame: InputFrame = _filter_input_frame(raw)
	if not muted:
		item_slot.capture_input(frame)
	_start_wheelspin_remaining = maxf(0.0, _start_wheelspin_remaining - delta)
	if _race_frozen or _start_wheelspin_remaining > 0.0:
		_physics.reset_motion()
		_set_state(KartState.FROZEN)
		if muted:
			EventBus.set_block_signals(was_blocked)
		return
	var terrain: KartPhysics.TerrainSample = _sample_terrain(boost_controller.get_result().ignores_offroad)
	var ground: KartPhysics.GroundProbe = _physics.probe_ground()
	var drift_result: KartPhysics.DriftResult = _update_drift(frame, ground, delta)
	var boost_result: KartPhysics.BoostResult = _update_boost(delta)
	_physics.integrate(frame, terrain, ground, drift_result, boost_result, delta)
	_update_hit_reactor(delta)
	_update_state(ground)
	if muted:
		EventBus.set_block_signals(was_blocked)
## Installs a new input source. Karts never read `Input` directly (spec §23).
func set_input_provider(provider: InputProvider) -> void:
	input_provider = provider
## Freezes or releases race motion while continuing to poll the input provider.
func set_frozen(frozen: bool) -> void:
	_race_frozen = frozen
	if frozen:
		_physics.reset_motion()
		_set_state(KartState.FROZEN)
	elif _start_wheelspin_remaining <= 0.0 and not _finished:
		_set_state(KartState.GROUNDED)
## Installs safe post-finish input and keeps the public state at FINISHED.
func set_finished(provider: InputProvider) -> void:
	_finished = true
	_race_frozen = false
	input_provider = provider
	_set_state(KartState.FINISHED)
## Applies the early-throttle penalty beginning at GO.
func apply_start_wheelspin(duration: float) -> void:
	_start_wheelspin_remaining = maxf(_start_wheelspin_remaining, duration)
	_physics.reset_motion()
	_set_state(KartState.FROZEN)
## Returns the remaining early-throttle wheelspin freeze in seconds.
func get_start_wheelspin_remaining() -> float:
	return _start_wheelspin_remaining
## Returns a defensive copy of the latest raw provider frame.
func get_input_frame_snapshot() -> InputFrame:
	return _latest_input_frame.clone()
## Returns the latest raw steer value for presentation-only wheel/body motion.
func get_steer_input() -> float:
	return _latest_input_frame.steer
## Returns the latest raw throttle value for presentation-only body pitch.
func get_throttle_input() -> float:
	return _latest_input_frame.throttle
## Returns the latest raw brake value for presentation-only body pitch.
func get_brake_input() -> float:
	return _latest_input_frame.brake
func get_speed() -> float:
	return _physics.speed
## Returns the local sideways velocity component used by arcade grip.
func get_lateral_speed() -> float:
	return _physics.lateral
## Returns seconds spent continuously without enough grounded rays.
func get_air_time() -> float:
	return _physics.air_time
## Returns KartData's mass scalar for deterministic kart contact.
func get_mass() -> float:
	return kart_data.weight
## Returns whether HitReactor currently rejects new hit effects.
func is_invulnerable() -> bool:
	return _hit_reactor.is_invulnerable()
## Returns the most recently sampled TerrainData identifier.
func get_terrain_id() -> StringName:
	return _current_terrain_id
## Returns whether a fully charged slipstream is being sustained.
func is_slipstream_active() -> bool:
	return _slipstream_active
## Returns the active hit type, or -1 while no hit reaction is running.
func get_hit_state() -> int:
	return _hit_reactor.get_hit_type() if _hit_reactor.is_active() else -1
## Returns normalized elapsed hit progress for visual-only deformation.
func get_hit_progress() -> float:
	return _hit_reactor.get_progress()
## Returns whether the raw provider held throttle on the latest physics tick.
func is_throttle_held() -> bool:
	return _throttle_held
func get_speed_ratio() -> float:
	return clampf(absf(_physics.speed) / maxf(kart_data.max_speed, 0.001), 0.0, 1.0)
## Phase 10 audio hook: speed ratio plus the specified boost pitch addition.
func get_engine_pitch_ratio() -> float:
	return get_speed_ratio() + (ENGINE_BOOST_PITCH_ADD if is_boosting() else 0.0)
## Phase 10 audio hook: normalized lateral slip magnitude for tyre squeal.
func get_drift_squeal_ratio() -> float:
	return clampf(absf(get_lateral_speed()) / maxf(kart_data.max_speed, 0.001), 0.0, 1.0)
## Returns the most recent landing vertical speed for presentation impulses.
func get_last_landing_speed() -> float:
	return _last_landing_speed
func get_forward() -> Vector3:
	return -global_transform.basis.z
func is_grounded() -> bool:
	return _physics.grounded
func get_ground_normal() -> Vector3:
	return _physics.ground_normal
func get_state() -> int:
	return state
## Returns whether this kart has crossed the finish line (spec §9.3).
func is_finished() -> bool:
	return _finished
func get_kart_data() -> KartData:
	return kart_data
## Returns the driver identity used by results and presentation.
func get_driver_data() -> DriverData:
	return driver_data
## Rebinds the driver identity and refreshes its placeholder color when ready.
func set_driver_data(data: DriverData) -> void:
	driver_data = data
	if is_node_ready():
		($Visuals as KartVisuals).apply_driver_data(data)
## Rebinds KartData for sandbox weight-class comparisons.
func set_kart_data(data: KartData) -> void:
	kart_data = data
	_physics.set_kart_data(data)
	_terrain_sensor.set_kart_data(data)
	drift_controller.configure(tuning, data)
	boost_controller.configure(tuning, data)
## Converts a world velocity change into local speed/lateral components.
func apply_impulse_arcade(delta_velocity: Vector3, yaw_nudge: float) -> void:
	_physics.apply_world_delta_velocity(delta_velocity)
	rotate(Vector3.UP, yaw_nudge)
## Applies an external hit through the invulnerability gate. `from_item` and
## `item_speed_factor` forward the item-hit distinction to HitReactor (spec
## §12.2): item hits always allow shield absorption, even a BUMP.
func apply_hit(type: HitReactor.HitType, source: Node = null, from_item: bool = false, item_speed_factor: float = 1.0) -> bool:
	if network_replica:
		return false # Server snapshot owns external gameplay effects.
	var accepted: bool = _hit_reactor.apply(type, source, from_item, item_speed_factor)
	if accepted:
		replay_event_received.emit({"type": "hit", "hit_type": int(type)})
	return accepted
## Starts the tick-driven respawn state and suppresses driving input.
func begin_respawn() -> void:
	if network_replica:
		return # Server snapshot owns external gameplay effects.
	_respawning = true
	_set_state(KartState.RESPAWNING)
## Teleports to a safe transform, clears momentum, and grants protection.
func teleport_for_respawn(target: Transform3D) -> void:
	if network_replica:
		return # Server snapshot owns external gameplay effects.
	global_transform = target
	_physics.reset_motion()
	_hit_reactor.grant_invulnerability(tuning.respawn_invulnerability_duration)
## Clears momentum without changing state or granting invulnerability.
func reset_motion_arcade() -> void:
	_physics.reset_motion()
## Applies a local-space forward/up launch through KartPhysics ownership.
func launch(local_velocity: Vector3) -> void:
	if network_replica:
		return # Server snapshot owns external gameplay effects.
	replay_event_received.emit({"type": "launch", "velocity": [local_velocity.x, local_velocity.y, local_velocity.z]})
	_physics.launch(local_velocity)
	_ungrounded_ticks = tuning.airborne_grace_ticks + 1
	_set_state(KartState.AIRBORNE)
	EventBus.kart_launched.emit(self)
## Publishes a contact resolved by the race-owned collision system.
func notify_contact() -> void:
	EventBus.kart_contacted.emit(self)
## Requests a boost from a track or future item source.
func request_boost(spec: BoostSpecData, source: StringName) -> void:
	if network_replica:
		return # Server snapshot owns external gameplay effects.
	replay_event_received.emit(KartReplayState.boost_dict(spec, source))
	boost_controller.request(spec, source)
## Returns drift visual state without exposing mutable controller internals.
func get_drift_direction() -> int:
	return drift_controller.get_direction()
## Returns current drift charge seconds.
func get_drift_charge() -> float:
	return drift_controller.get_charge()
## Returns current mini-turbo tier.
func get_drift_tier() -> int:
	return drift_controller.get_tier()
## Returns current drift state enum.
func get_drift_state() -> DriftController.DriftState:
	return drift_controller.get_state()
## Returns current boost source for HUD/debug observers.
func get_boost_source() -> StringName:
	return boost_controller.get_source()
## Returns active boost seconds remaining.
func get_boost_remaining() -> float:
	return boost_controller.get_remaining()
## Returns whether an airborne trick is armed.
func is_trick_armed() -> bool:
	return drift_controller.is_trick_armed()
## Returns the tier-derived body yaw request in degrees.
func get_drift_visual_angle_degrees() -> float:
	return drift_controller.get_visual_angle_degrees() * float(drift_controller.get_direction())
## Returns whether any boost currently affects physics.
func is_boosting() -> bool:
	return boost_controller.get_result().active
## Attaches or replaces the one active shield item.
func install_shield(shield: ShieldItem) -> void:
	if _shield_item != null and _shield_item != shield and not _shield_item.is_expired():
		_shield_item.expire()
	_shield_item = shield
## Returns whether a live one-charge shield is attached.
func has_shield() -> bool:
	if _shield_item == null or not is_instance_valid(_shield_item) or not _shield_item.is_available():
		_shield_item = null
		return false
	return true
## Consumes one shield charge, returning true only for the absorbed hit.
func consume_shield() -> bool:
	if not has_shield():
		return false
	var absorbed: bool = _shield_item.consume()
	if absorbed:
		_shield_item = null
	return absorbed
## Returns shield seconds remaining for HUD/debug observers.
func get_shield_remaining() -> float:
	if not has_shield():
		return 0.0
	return maxf(0.0, _shield_item.data.duration - _shield_item.elapsed_seconds)
## Ends respawn freeze and returns state control to ground probing.
func finish_respawn() -> void:
	_respawning = false
	_ungrounded_ticks = 0
	_set_state(KartState.GROUNDED)
## Step 1 (§9.3): HIT/RESPAWNING/FROZEN states drive with a zero frame. The
## provider is still polled so edge-detected inputs (drift/item press) do not
## desynchronize once HitReactor/RespawnSystem/Countdown exist in later phases.
func _get_input_frame() -> InputFrame:
	return _filter_input_frame(input_provider.get_frame())
func _filter_input_frame(frame: InputFrame) -> InputFrame:
	_latest_input_frame = frame.clone()
	_throttle_held = frame.throttle > 0.0
	if state == KartState.RESPAWNING or _race_frozen or _start_wheelspin_remaining > 0.0:
		return InputFrame.zero()
	if state == KartState.HIT:
		return _hit_reactor.filter_input(frame)
	return frame
func _sample_terrain(ignores_offroad: bool = false) -> KartPhysics.TerrainSample:
	var sample: KartPhysics.TerrainSample = _terrain_sensor.sample(ignores_offroad)
	_current_terrain_id = sample.terrain_id
	return sample
func _update_drift(frame: InputFrame, ground: KartPhysics.GroundProbe, delta: float) -> KartPhysics.DriftResult:
	return drift_controller.step(
		frame, _physics.speed, ground.grounded, _physics.air_time,
		_physics.last_yaw_rate, _hit_reactor.is_active(), delta,
	)
func _update_boost(delta: float) -> KartPhysics.BoostResult:
	var was_active: bool = _slipstream_active
	var timer: SlipstreamSensor.TimerResult = _slipstream_sensor.tick(delta)
	_slipstream_active = timer.active
	if was_active and not timer.active:
		boost_controller.request(tuning.slipstream_exit_boost, &"slipstream_exit")
	var result: KartPhysics.BoostResult = boost_controller.step(delta)
	if timer.active and timer.speed_mult > result.speed_mult:
		result.speed_mult = timer.speed_mult
		result.accel_mult = timer.speed_mult
	return result
func _update_hit_reactor(delta: float) -> void:
	_hit_reactor.tick(delta)
func _update_state(ground: KartPhysics.GroundProbe) -> void:
	if _respawning:
		_set_state(KartState.RESPAWNING)
		return
	if _race_frozen or _start_wheelspin_remaining > 0.0:
		_set_state(KartState.FROZEN)
		return
	if _finished:
		_set_state(KartState.FINISHED)
		return
	if _hit_reactor.is_active():
		_set_state(KartState.HIT)
		return
	if ground.grounded:
		_ungrounded_ticks = 0
		if drift_controller.get_state() == DriftController.DriftState.HOLD:
			_set_state(KartState.DRIFTING)
		else:
			_set_state(KartState.GROUNDED)
		return
	_ungrounded_ticks += 1
	if _ungrounded_ticks > tuning.airborne_grace_ticks:
		_set_state(KartState.AIRBORNE)
func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old_state: int = state
	state = new_state
	state_changed.emit(old_state, new_state)
func _on_wall_head_on() -> void:
	if network_replica:
		return # Wall-hit adjudication is mirrored from the server.
	EventBus.wall_head_on.emit(self)
	_hit_reactor.apply(HitReactor.HitType.BUMP, self, false, 1.0, false)
func _on_landed(vertical_speed: float) -> void:
	_last_landing_speed = vertical_speed

## Captures deterministic motion, drift, boost, hit and slipstream state.
func capture_state() -> Dictionary:
	var snapshot: Dictionary = KartReplayState.capture(self)
	snapshot["slip_charge"] = _slipstream_sensor.get("_charge_time")
	snapshot["slip_exit"] = _slipstream_sensor.get("_exit_remaining")
	snapshot["slip_active"] = _slipstream_active
	return snapshot

## Restores validated state without replaying audiovisual or gameplay events.
func apply_state(snapshot: Dictionary) -> void:
	var was_blocked: bool = EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	KartReplayState.restore(self, snapshot)
	_slipstream_sensor.set("_charge_time", float(snapshot.get("slip_charge", 0.0)))
	_slipstream_sensor.set("_exit_remaining", float(snapshot.get("slip_exit", 0.0)))
	_slipstream_active = bool(snapshot.get("slip_active", false))
	_slipstream_sensor.set("_active", _slipstream_active)
	EventBus.set_block_signals(was_blocked)
