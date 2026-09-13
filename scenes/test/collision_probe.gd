class_name CollisionProbe
extends Node

## Headless wall-collision reproducer. It runs the real kart and generated
## track collision, preserving 40 physics ticks on either side of first contact.

class StraightInputProvider extends InputProvider:
	func get_frame() -> InputFrame:
		var frame: InputFrame = InputFrame.new()
		frame.throttle = 1.0
		return frame


const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const FLAT_WALL_PROBE: Script = preload("res://scenes/test/flat_wall_probe.gd")
const TRACK_SCENES: Dictionary = {
	&"track_01": preload("res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn"),
	&"track_02": preload("res://track/tracks/track_02_lumen_underpass/track_02_lumen_underpass.tscn"),
	&"track_03": preload("res://track/tracks/track_03_glacier_crown/track_03_glacier_crown.tscn"),
	&"track_04": preload("res://track/tracks/track_04_ochre_rift/track_04_ochre_rift.tscn"),
}
const TRACK_CONFIGS: Dictionary = {
	&"track_01": {
		"road_half_width": 7.0,
		"wall_center": 7.5,
		"wall_half_thickness": 0.5,
		"wall_segment_length": 8.0,
		"locations": [
			{"name": "guardrail_straight_right", "fraction": 0.08, "side": 1.0},
			{"name": "guardrail_straight_left", "fraction": 0.08, "side": -1.0},
			{"name": "chicane_wall_right", "fraction": 0.20, "side": 1.0},
			{"name": "chicane_wall_left", "fraction": 0.20, "side": -1.0},
			{"name": "hairpin_wall_right", "fraction": 0.46, "side": 1.0},
			{"name": "hairpin_wall_left", "fraction": 0.46, "side": -1.0},
		],
	},
	&"track_02": {
		"road_half_width": 8.0,
		"wall_center": 8.5,
		"wall_half_thickness": 0.5,
		"wall_segment_length": 6.0,
		"locations": [
			{"name": "tunnel_wall_right", "fraction": 0.43, "side": 1.0},
			{"name": "tunnel_wall_left", "fraction": 0.43, "side": -1.0},
			{"name": "underpass_corner_right", "fraction": 0.67, "side": 1.0},
			{"name": "underpass_corner_left", "fraction": 0.67, "side": -1.0},
		],
	},
	&"track_03": {
		"road_half_width": 9.0,
		"wall_center": 9.5,
		"wall_half_thickness": 0.5,
		"wall_segment_length": 6.0,
		"locations": [
			{"name": "glacier_wall_right", "fraction": 0.62, "side": 1.0},
			{"name": "glacier_wall_left", "fraction": 0.62, "side": -1.0},
		],
	},
	&"track_04": {
		"road_half_width": 16.0,
		"wall_center": 16.5,
		"wall_half_thickness": 0.5,
		"wall_segment_length": 6.0,
		"locations": [
			{"name": "canyon_wall_right", "fraction": 0.18, "side": 1.0},
			{"name": "canyon_wall_left", "fraction": 0.18, "side": -1.0},
			{"name": "canyon_curve_right", "fraction": 0.72, "side": 1.0},
			{"name": "canyon_curve_left", "fraction": 0.72, "side": -1.0},
		],
	},
}
const DEFAULT_ANGLES: Array[float] = [15.0, 45.0, 75.0, 90.0]
const SWEEP_SPEEDS: Array[float] = [12.0, 22.0, 30.0]
const PRE_CONTACT_TICKS: int = 40
const POST_CONTACT_TICKS: int = 40
const MAX_SCENARIO_TICKS: int = 720
const KART_HALF_WIDTH: float = 0.8
const FALL_DEPTH: float = 3.0
const APPROACH_CLEARANCE: float = 2.0
const START_SEARCH_STEP: float = 0.25
const START_SEARCH_DISTANCE: float = 40.0


func _ready() -> void:
	GameState.automation_mode = true
	_run.call_deferred()


## Parses `--track <index|name> --speed <m/s> --angle <deg>` and the optional
## `--sweep`/`--location <name>` diagnostic expansions.
static func parse_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {
		"track": &"track_01",
		"speed": 22.0,
		"angles": DEFAULT_ANGLES.duplicate(),
		"sweep": false,
		"flat_wall": false,
		"location": "",
		"wall_push_out": -1.0,
		"wall_bounce": -1.0,
	}
	var index: int = 0
	while index < arguments.size():
		var key: String = arguments[index]
		if key == "--sweep":
			result["sweep"] = true
			index += 1
			continue
		if key == "--flat-wall":
			result["flat_wall"] = true
			index += 1
			continue
		if index + 1 >= arguments.size():
			break
		var value: String = arguments[index + 1]
		match key:
			"--track":
				result["track"] = _normalize_track(value)
			"--speed":
				if value.is_valid_float():
					result["speed"] = maxf(1.0, value.to_float())
			"--angle":
				if value.is_valid_float():
					result["angles"] = [clampf(value.to_float(), 1.0, 90.0)]
			"--location":
				result["location"] = value
			"--wall-push-out":
				if value.is_valid_float():
					result["wall_push_out"] = maxf(0.0, value.to_float())
			"--wall-bounce":
				if value.is_valid_float():
					result["wall_bounce"] = clampf(value.to_float(), 0.0, 1.0)
		index += 2
	return result


static func _normalize_track(value: String) -> StringName:
	var normalized: String = value.to_lower().replace("-", "_")
	match normalized:
		"0", "1", "track_01", "track_01_ridgeline_circuit", "ridgeline", "ridgeline_circuit":
			return &"track_01"
		"2", "track_02", "track_02_lumen_underpass", "lumen", "lumen_underpass":
			return &"track_02"
		"3", "track_03", "track_03_glacier_crown", "glacier", "glacier_crown":
			return &"track_03"
		"4", "track_04", "track_04_ochre_rift", "ochre", "ochre_rift":
			return &"track_04"
		_:
			return &"track_01"


func _run() -> void:
	var options: Dictionary = parse_options(OS.get_cmdline_user_args())
	if bool(options["flat_wall"]):
		await FLAT_WALL_PROBE.run(self, options)
		return
	var track_id: StringName = options["track"]
	var config: Dictionary = TRACK_CONFIGS[track_id]
	var locations: Array = config["locations"]
	var requested_location: String = options["location"]
	if not requested_location.is_empty():
		locations = locations.filter(func(candidate: Dictionary) -> bool: return candidate["name"] == requested_location)
	if locations.is_empty():
		push_error("Unknown collision probe location: %s" % requested_location)
		get_tree().quit(2)
		return
	var speeds: Array = SWEEP_SPEEDS if bool(options["sweep"]) else [float(options["speed"])]
	var results: Array[Dictionary] = []
	for location: Dictionary in locations:
		for speed: float in speeds:
			for angle: float in options["angles"]:
				results.append(await _run_scenario(track_id, config, location, speed, angle, options))
	var failed_count: int = 0
	for result: Dictionary in results:
		if bool(result["penetrated"]) or bool(result["fell_below_track"]):
			failed_count += 1
	var summary: Dictionary = {
		"summary": true,
		"track": String(track_id),
		"scenario_count": results.size(),
		"failed_count": failed_count,
		"penetrated": results.any(func(result: Dictionary) -> bool: return bool(result["penetrated"])),
		"fell_below_track": results.any(func(result: Dictionary) -> bool: return bool(result["fell_below_track"])),
	}
	print("COLLISION_PROBE ", JSON.stringify(summary))
	get_tree().quit(1 if failed_count > 0 else 0)


func _run_scenario(
	track_id: StringName, config: Dictionary, location: Dictionary, speed: float, angle_degrees: float,
	options: Dictionary,
) -> Dictionary:
	var track: TrackRoot = (TRACK_SCENES[track_id] as PackedScene).instantiate() as TrackRoot
	add_child(track)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var line: RacingLine = track.get_racing_line()
	var wall_step: float = line.length() / float(ceili(line.length() / float(config["wall_segment_length"])))
	var target_offset: float = roundf(line.length() * float(location["fraction"]) / wall_step) * wall_step
	var center: Vector3 = line.sample(target_offset)
	var right: Vector3 = line.right_at(target_offset).normalized()
	var side: float = float(location["side"])
	var safe_center_limit: float = float(config["road_half_width"]) - KART_HALF_WIDTH
	var start: Dictionary = find_grounded_start(line, target_offset, center, right, side, safe_center_limit, angle_degrees)
	var start_position: Vector3 = start["position"]
	var impact_direction: Vector3 = start["direction"]
	var kart: KartController = KART_SCENE.instantiate() as KartController
	if float(options["wall_push_out"]) >= 0.0 or float(options["wall_bounce"]) >= 0.0:
		var diagnostic_tuning: PhysicsTuning = kart.tuning.duplicate(true) as PhysicsTuning
		if float(options["wall_push_out"]) >= 0.0:
			diagnostic_tuning.wall_push_out = float(options["wall_push_out"])
		if float(options["wall_bounce"]) >= 0.0:
			diagnostic_tuning.wall_bounce = float(options["wall_bounce"])
		kart.tuning = diagnostic_tuning
	track.add_child(kart)
	await get_tree().physics_frame
	kart.global_transform = Transform3D(Basis.looking_at(impact_direction, Vector3.UP), start_position + Vector3.UP * 0.55)
	var pre_contact: Array[Dictionary] = []
	for warmup_tick: int in range(-PRE_CONTACT_TICKS, 0):
		await get_tree().physics_frame
		pre_contact.append(_sample_tick(kart, warmup_tick, _wall_normal(kart)))
	var initial_ground_ray_hits: int = _ground_ray_hits(kart)
	kart.set_input_provider(StraightInputProvider.new())
	(kart.get_node("KartPhysics") as KartPhysics).speed = speed
	var trace: Array[Dictionary] = []
	var event_tick: int = -1
	var ticks_after_event: int = 0
	var min_y: float = kart.global_position.y
	var max_depth: float = 0.0
	var max_lateral: float = 0.0
	var min_wall_inward_dot: float = 1.0
	var penetrated: bool = false
	var fell_below_track: bool = false
	for tick: int in range(MAX_SCENARIO_TICKS):
		await get_tree().physics_frame
		var wall_normal: Variant = _wall_normal(kart)
		var closest_offset: float = line.offset_at(kart.global_position)
		var road_center: Vector3 = line.sample(closest_offset)
		var road_right: Vector3 = line.right_at(closest_offset).normalized()
		var signed_lateral: float = (kart.global_position - road_center).dot(road_right) * side
		var depth: float = maxf(0.0, signed_lateral - safe_center_limit)
		var wall_inward_dot: Variant = null
		if wall_normal != null:
			wall_inward_dot = (wall_normal as Vector3).dot(-road_right * side)
			min_wall_inward_dot = minf(min_wall_inward_dot, float(wall_inward_dot))
		min_y = minf(min_y, kart.global_position.y)
		max_depth = maxf(max_depth, depth)
		max_lateral = maxf(max_lateral, signed_lateral)
		penetrated = penetrated or signed_lateral > float(config["wall_center"]) + float(config["wall_half_thickness"])
		fell_below_track = fell_below_track or kart.global_position.y < road_center.y - FALL_DEPTH
		var sample: Dictionary = _sample_tick(kart, tick, wall_normal, wall_inward_dot)
		if event_tick < 0:
			if wall_normal != null or penetrated or fell_below_track:
				event_tick = tick
				trace.append_array(pre_contact)
				trace.append(sample)
			else:
				pre_contact.append(sample)
				if pre_contact.size() > PRE_CONTACT_TICKS:
					pre_contact.pop_front()
		else:
			trace.append(sample)
			ticks_after_event += 1
			if ticks_after_event >= POST_CONTACT_TICKS:
				break
	for sample: Dictionary in trace:
		print("COLLISION_TRACE ", JSON.stringify(sample))
	var result: Dictionary = {
		"track": String(track_id),
		"location": location["name"],
		"offset": snappedf(target_offset, 0.001),
		"speed": speed,
		"angle": angle_degrees,
		"actual_angle": snappedf(float(start["actual_angle"]), 0.01),
		"initial_ground_ray_hits": initial_ground_ray_hits,
		"wall_push_out": kart.tuning.wall_push_out,
		"wall_bounce": kart.tuning.wall_bounce,
		"event_tick": event_tick,
		"penetrated": penetrated,
		"fell_below_track": fell_below_track,
		"min_y": snappedf(min_y, 0.001),
		"max_depth": snappedf(max_depth, 0.001),
		"max_lateral": snappedf(max_lateral, 0.001),
		"min_wall_inward_dot": snappedf(min_wall_inward_dot, 0.001),
		"final_position": _vector(kart.global_position),
	}
	print("COLLISION_PROBE ", JSON.stringify(result))
	track.queue_free()
	await get_tree().physics_frame
	return result


static func find_grounded_start(
	line: RacingLine, target_offset: float, target_center: Vector3, target_right: Vector3,
	side: float, safe_center_limit: float, requested_angle: float,
) -> Dictionary:
	var target: Vector3 = target_center + target_right * side * safe_center_limit
	var best_position: Vector3 = target_center + target_right * side * (safe_center_limit - APPROACH_CLEARANCE)
	var best_direction: Vector3 = target_right * side
	var best_angle: float = 90.0
	var best_error: float = absf(requested_angle - best_angle)
	var step_count: int = ceili(START_SEARCH_DISTANCE / START_SEARCH_STEP)
	for index: int in range(step_count + 1):
		var start_offset: float = target_offset - float(index) * START_SEARCH_STEP
		var start_center: Vector3 = line.sample(start_offset)
		var start_right: Vector3 = line.right_at(start_offset).normalized()
		var candidate: Vector3 = start_center + start_right * side * (safe_center_limit - APPROACH_CLEARANCE)
		var direction: Vector3 = target - candidate
		direction.y = 0.0
		if direction.length() < 0.001:
			continue
		direction = direction.normalized()
		var actual_angle: float = rad_to_deg(asin(clampf(absf(direction.dot(target_right)), 0.0, 1.0)))
		var error: float = absf(requested_angle - actual_angle)
		if error < best_error:
			best_error = error
			best_position = candidate
			best_direction = direction
			best_angle = actual_angle
	return {
		"position": best_position,
		"direction": best_direction,
		"actual_angle": best_angle,
	}


func _sample_tick(
	kart: KartController, tick: int, wall_normal: Variant, wall_inward_dot: Variant = null,
) -> Dictionary:
	return {
		"tick": tick,
		"position": _vector(kart.global_position),
		"velocity": _vector(kart.velocity),
		"grounded": kart.is_grounded(),
		"ground_ray_hits": _ground_ray_hits(kart),
		"state": _state_name(kart.get_state()),
		"colliding_wall_normal": null if wall_normal == null else _vector(wall_normal as Vector3),
		"wall_inward_dot": wall_inward_dot,
	}


func _ground_ray_hits(kart: KartController) -> int:
	var hits: int = 0
	var max_angle: float = deg_to_rad(kart.tuning.max_climb_angle_degrees)
	for child: Node in kart.get_node("GroundRays").get_children():
		if child is RayCast3D:
			var ray: RayCast3D = child as RayCast3D
			ray.force_raycast_update()
			if ray.is_colliding() and ray.get_collision_normal().angle_to(Vector3.UP) <= max_angle:
				hits += 1
	return hits


func _wall_normal(kart: KartController) -> Variant:
	for index: int in range(kart.get_slide_collision_count()):
		var collision: KinematicCollision3D = kart.get_slide_collision(index)
		var normal: Vector3 = collision.get_normal()
		if absf(normal.dot(Vector3.UP)) < kart.tuning.wall_normal_threshold:
			return normal
	return null


static func _state_name(state: int) -> String:
	match state:
		KartState.GROUNDED:
			return "GROUNDED"
		KartState.DRIFTING:
			return "DRIFTING"
		KartState.AIRBORNE:
			return "AIRBORNE"
		KartState.HIT:
			return "HIT"
		KartState.RESPAWNING:
			return "RESPAWNING"
		KartState.FINISHED:
			return "FINISHED"
		KartState.FROZEN:
			return "FROZEN"
		_:
			return "UNKNOWN"


static func _vector(value: Vector3) -> Array[float]:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
