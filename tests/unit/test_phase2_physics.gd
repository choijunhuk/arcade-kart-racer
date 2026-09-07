extends GutTest

const TERRAIN_SENSOR_PATH: String = "res://kart/terrain_sensor.gd"
const COLLISION_RESOLVER_PATH: String = "res://race/kart_collision_resolver.gd"
const SLIPSTREAM_SENSOR_PATH: String = "res://kart/slipstream_sensor.gd"
const DT: float = 0.5

var _asphalt: TerrainData
var _grass: TerrainData
var _dirt: TerrainData
var _medium: KartData
var _tuning: PhysicsTuning


func before_each() -> void:
	_asphalt = load("res://data/terrain/asphalt.tres") as TerrainData
	_grass = load("res://data/terrain/grass.tres") as TerrainData
	_dirt = load("res://data/terrain/dirt.tres") as TerrainData
	_medium = load("res://data/karts/medium.tres") as KartData
	_tuning = load("res://data/tuning/physics_default.tres") as PhysicsTuning


func test_offroad_zone_wins_over_collider_metadata() -> void:
	var script: GDScript = _load_required_script(TERRAIN_SENSOR_PATH)
	if script == null:
		return
	var zones: Array[TerrainData] = [_grass]
	var resolved: TerrainData = script.call("resolve_terrain", zones, _dirt, _asphalt) as TerrainData

	assert_eq(resolved.id, &"grass")


func test_collider_metadata_wins_over_default() -> void:
	var script: GDScript = _load_required_script(TERRAIN_SENSOR_PATH)
	if script == null:
		return
	var zones: Array[TerrainData] = []
	var resolved: TerrainData = script.call("resolve_terrain", zones, _dirt, _asphalt) as TerrainData

	assert_eq(resolved.id, &"dirt")


func test_stringname_collider_metadata_resolves_resource_id() -> void:
	var script: GDScript = _load_required_script(TERRAIN_SENSOR_PATH)
	if script == null:
		return
	var zones: Array[TerrainData] = []
	var resolved: TerrainData = script.call("resolve_terrain", zones, &"grass", _asphalt) as TerrainData

	assert_eq(resolved.id, &"grass")


func test_offroad_resistance_lerps_penalties_toward_neutral() -> void:
	var script: GDScript = _load_required_script(TERRAIN_SENSOR_PATH)
	if script == null:
		return
	_medium.offroad_resistance = 0.5
	var sample: RefCounted = script.call("build_sample", _grass, _medium) as RefCounted

	assert_almost_eq(float(sample.get("speed_mult")), 0.85, 0.001)
	assert_almost_eq(float(sample.get("grip_mult")), 0.85, 0.001)
	assert_almost_eq(float(sample.get("drag_mult")), 1.225, 0.001)


func test_collision_impulse_moves_light_kart_more_than_heavy_kart() -> void:
	var script: GDScript = _load_required_script(COLLISION_RESOLVER_PATH)
	if script == null:
		return
	var result: RefCounted = script.call(
		"compute_impulse", Vector3(10.0, 0.0, 0.0), Vector3.ZERO,
		Vector3.RIGHT, 1.35, 0.75, 1.0,
	) as RefCounted
	var heavy_delta: Vector3 = result.get("delta_velocity_a") as Vector3
	var light_delta: Vector3 = result.get("delta_velocity_b") as Vector3

	assert_gt(light_delta.length(), heavy_delta.length())
	assert_lt(heavy_delta.x, 0.0)
	assert_gt(light_delta.x, 0.0)


func test_collision_impulse_is_zero_when_karts_are_separating() -> void:
	var script: GDScript = _load_required_script(COLLISION_RESOLVER_PATH)
	if script == null:
		return
	var result: RefCounted = script.call(
		"compute_impulse", Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0),
		Vector3.RIGHT, 1.0, 1.0, 1.0,
	) as RefCounted

	assert_eq(result.get("delta_velocity_a") as Vector3, Vector3.ZERO)
	assert_eq(result.get("delta_velocity_b") as Vector3, Vector3.ZERO)


func test_landing_alignment_preserves_small_lateral_angle() -> void:
	var lateral: float = KartPhysics.compute_landing_lateral(
		5.0, 20.0, _tuning.landing_align_threshold_degrees,
		_tuning.landing_lateral_retention,
	)

	assert_almost_eq(lateral, 5.0, 0.001)


func test_landing_alignment_removes_lateral_speed_above_threshold() -> void:
	var lateral: float = KartPhysics.compute_landing_lateral(
		20.0, 5.0, _tuning.landing_align_threshold_degrees,
		_tuning.landing_lateral_retention,
	)

	assert_almost_eq(lateral, 20.0 * _tuning.landing_lateral_retention, 0.001)


func test_slipstream_activates_after_charge_time() -> void:
	var script: GDScript = _load_required_script(SLIPSTREAM_SENSOR_PATH)
	if script == null:
		return
	var result: RefCounted = script.call(
		"advance_timer", true, _tuning.slipstream_time, 0.0, false, 0.0, _tuning,
	) as RefCounted

	assert_true(bool(result.get("active")))
	assert_almost_eq(float(result.get("speed_mult")), _tuning.slipstream_speed_mult, 0.001)


func test_slipstream_exit_starts_temporary_boost() -> void:
	var script: GDScript = _load_required_script(SLIPSTREAM_SENSOR_PATH)
	if script == null:
		return
	var result: RefCounted = script.call(
		"advance_timer", false, DT, _tuning.slipstream_time, true, 0.0, _tuning,
	) as RefCounted

	assert_false(bool(result.get("active")))
	assert_gt(float(result.get("exit_remaining")), 0.0)
	assert_almost_eq(float(result.get("speed_mult")), _tuning.slipstream_exit_boost.speed_mult, 0.001)


func test_slipstream_exit_boost_expires() -> void:
	var script: GDScript = _load_required_script(SLIPSTREAM_SENSOR_PATH)
	if script == null:
		return
	var result: RefCounted = script.call(
		"advance_timer", false, _tuning.slipstream_exit_duration, 0.0, false,
		_tuning.slipstream_exit_duration, _tuning,
	) as RefCounted

	assert_almost_eq(float(result.get("exit_remaining")), 0.0, 0.001)
	assert_almost_eq(float(result.get("speed_mult")), 1.0, 0.001)


func _load_required_script(path: String) -> GDScript:
	var exists: bool = ResourceLoader.exists(path)
	assert_true(exists, "%s must exist" % path)
	if not exists:
		return null
	return load(path) as GDScript
