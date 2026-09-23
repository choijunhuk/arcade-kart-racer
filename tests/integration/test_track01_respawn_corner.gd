extends GutTest

## 19-D item 1 regression: a kart that falls off Track01's wall-less closing
## arc after passing the apex checkpoint (Checkpoint07) used to respawn on that
## apex facing the tangent and, at full throttle, drop straight off the cliff
## again in a loop. The respawn spot must now leave enough straight road ahead.

const TRACK_SCENE: String = "res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn"
const DRIVE_SECONDS: float = 3.0
const ROAD_HALF_WIDTH: float = 7.0
const MIN_ROAD_Y: float = -1.0


class ConstantInput extends InputProvider:
	var throttle: float = 0.0
	var steer: float = 0.0

	func get_frame() -> InputFrame:
		var frame: InputFrame = InputFrame.new()
		frame.throttle = throttle
		frame.steer = steer
		return frame


var _respawns: int = 0


func before_each() -> void:
	_respawns = 0
	EventBus.kart_respawned.connect(_on_respawned)


func after_each() -> void:
	if EventBus.kart_respawned.is_connected(_on_respawned):
		EventBus.kart_respawned.disconnect(_on_respawned)


func _on_respawned(_kart: Node) -> void:
	_respawns += 1


func _build() -> Dictionary:
	var track: TrackRoot = (load(TRACK_SCENE) as PackedScene).instantiate() as TrackRoot
	add_child_autofree(track)
	var tracker: LapTracker = LapTracker.new()
	tracker.total_laps = 3
	add_child_autofree(tracker)
	tracker.setup(track)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(kart)
	tracker.register_kart(kart)
	var respawn: RespawnSystem = RespawnSystem.new()
	add_child_autofree(respawn)
	var line: RacingLine = track.get_racing_line()
	respawn.register_kart(kart, func(k: KartController) -> Transform3D:
		return RespawnSystem.resolve_respawn_transform(k, tracker, line, [k]))
	for zone: Node in track.get_node("KillZones").get_children():
		respawn.register_kill_zone(zone as KillZone)
	var checkpoints: Array[Checkpoint] = track.get_checkpoints()
	kart.global_position = line.sample(checkpoints[7].offset) + Vector3.UP * 0.3
	for index: int in range(1, checkpoints.size()):
		checkpoints[index].body_passed.emit(kart, index)
	return {"track": track, "tracker": tracker, "kart": kart, "respawn": respawn, "line": line}


func test_apex_checkpoint_respawn_is_moved_back_to_straight_road() -> void:
	var context: Dictionary = _build()
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var line: RacingLine = context["line"]
	assert_eq(tracker.get_last_checkpoint_index(kart), 7)
	var target: Transform3D = RespawnSystem.resolve_respawn_transform(kart, tracker, line, [kart])
	var offset: float = line.offset_at(target.origin)
	assert_lte(line.max_curvature_in(offset, RespawnSystem.RESPAWN_CLEAR_RUN), RespawnSystem.RESPAWN_MAX_CURVATURE)
	var forward: Vector3 = -target.basis.z
	assert_gt(forward.dot(line.tangent_at(offset)), 0.99, "respawn must face along the racing line")
	# Still after the previous gate (Checkpoint06), so no checkpoint is re-run.
	var previous_offset: float = (context["track"] as TrackRoot).get_checkpoints()[6].offset
	assert_gt(offset, previous_offset)


func test_straight_checkpoint_respawn_is_unchanged() -> void:
	var context: Dictionary = _build()
	var track: TrackRoot = context["track"]
	var line: RacingLine = context["line"]
	var gate: Checkpoint = track.get_checkpoints()[6]
	var raw: float = line.offset_at(gate.get_respawn_point().global_position)
	assert_almost_eq(RespawnSystem.corner_safe_offset(line, raw, 90.0), raw, 0.01)


func test_full_throttle_after_apex_respawn_stays_on_road_for_three_seconds() -> void:
	await _assert_stays_on_road(0.0)


func test_full_throttle_line_follower_after_apex_respawn_stays_on_road() -> void:
	await _assert_stays_on_road(-1.0)


## steer >= 0 drives a constant input; a negative value uses the full-throttle
## ScriptedInputProvider line follower instead.
func _assert_stays_on_road(steer: float) -> void:
	var context: Dictionary = _build()
	var kart: KartController = context["kart"]
	var line: RacingLine = context["line"]
	var respawn: RespawnSystem = context["respawn"]
	await wait_physics_frames(2)
	if steer >= 0.0:
		var constant: ConstantInput = ConstantInput.new()
		constant.throttle = 1.0
		constant.steer = steer
		kart.set_input_provider(constant)
	else:
		kart.set_input_provider(ScriptedInputProvider.new(kart, line))
	respawn.request_respawn(kart)
	var budget: int = 240
	while kart.get_state() == KartState.RESPAWNING and budget > 0:
		await get_tree().physics_frame
		budget -= 1
	assert_eq(_respawns, 1)
	assert_ne(kart.get_state(), KartState.RESPAWNING)
	for _tick: int in range(int(DRIVE_SECONDS * Engine.physics_ticks_per_second)):
		await get_tree().physics_frame # exactly one tick (wait_physics_frames(1) waits two)
		var lateral: float = kart.global_position.distance_to(line.sample(line.offset_at(kart.global_position)))
		if kart.global_position.y < MIN_ROAD_Y or lateral > ROAD_HALF_WIDTH:
			fail_test("left the road at %s after %d ticks, speed %.1f" % [kart.global_position, _tick, kart.get_speed()])
			return
	assert_eq(_respawns, 1, "no second respawn")
	assert_gt(kart.get_speed(), 5.0, "kart actually drove")
