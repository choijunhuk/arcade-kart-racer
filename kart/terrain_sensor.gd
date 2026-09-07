class_name TerrainSensor
extends Node

## Resolves the current surface using OffroadZone overlap, ground-collider
## metadata, then asphalt fallback order from spec section 15.4.

const DEFAULT_TERRAIN: TerrainData = preload("res://data/terrain/asphalt.tres")
const TERRAIN_DIRECTORY: String = "res://data/terrain"

var _probe: Area3D
var _ground_rays: Array[RayCast3D] = []
var _kart_data: KartData
var _overlapping_terrain: Array[TerrainData] = []


## Connects the sensor to the kart's trigger probe and ground rays.
func setup(probe: Area3D, ground_rays: Array[RayCast3D], kart_data: KartData) -> void:
	_probe = probe
	_ground_rays = ground_rays
	_kart_data = kart_data
	if not _probe.area_entered.is_connected(_on_area_entered):
		_probe.area_entered.connect(_on_area_entered)
	if not _probe.area_exited.is_connected(_on_area_exited):
		_probe.area_exited.connect(_on_area_exited)


## Updates the kart data used to soften offroad penalties.
func set_kart_data(kart_data: KartData) -> void:
	_kart_data = kart_data


## Returns a physics-ready sample for the highest-priority current terrain.
func sample(ignores_offroad: bool = false) -> KartPhysics.TerrainSample:
	var collider_terrain: Variant = _get_ground_terrain_metadata()
	var terrain: TerrainData = resolve_terrain(_overlapping_terrain, collider_terrain, DEFAULT_TERRAIN)
	var result: KartPhysics.TerrainSample = build_sample(terrain, _kart_data)
	result.ignores_offroad = ignores_offroad
	if ignores_offroad and terrain.id != DEFAULT_TERRAIN.id:
		result.speed_mult = 1.0
		result.grip_mult = 1.0
		result.drag_mult = 1.0
	return result


## Pure priority resolver used by unit tests and runtime sampling.
static func resolve_terrain(
	overlapping_terrain: Array[TerrainData], collider_terrain: Variant,
	default_terrain: TerrainData,
) -> TerrainData:
	if not overlapping_terrain.is_empty():
		return overlapping_terrain.back()
	if collider_terrain is TerrainData:
		return collider_terrain as TerrainData
	if collider_terrain is StringName or collider_terrain is String:
		var terrain_id: StringName = StringName(collider_terrain)
		var path: String = "%s/%s.tres" % [TERRAIN_DIRECTORY, String(terrain_id)]
		if ResourceLoader.exists(path):
			return load(path) as TerrainData
	return default_terrain


## Pure conversion from content data to resistance-adjusted physics values.
static func build_sample(terrain: TerrainData, kart_data: KartData) -> KartPhysics.TerrainSample:
	var result: KartPhysics.TerrainSample = KartPhysics.TerrainSample.new()
	result.terrain_id = terrain.id
	var resistance: float = clampf(kart_data.offroad_resistance, 0.0, 1.0)
	if terrain.id == DEFAULT_TERRAIN.id:
		resistance = 0.0
	result.speed_mult = lerpf(terrain.speed_mult, 1.0, resistance)
	result.grip_mult = lerpf(terrain.grip, 1.0, resistance)
	result.drag_mult = lerpf(terrain.drag_mult, 1.0, resistance)
	return result


func _get_ground_terrain_metadata() -> Variant:
	for ray: RayCast3D in _ground_rays:
		ray.force_raycast_update()
		if not ray.is_colliding():
			continue
		var collider: Object = ray.get_collider()
		if collider != null and collider.has_meta(&"terrain"):
			return collider.get_meta(&"terrain")
	return null


func _on_area_entered(area: Area3D) -> void:
	var terrain_value: Variant = area.get("terrain")
	if terrain_value is TerrainData:
		_overlapping_terrain.append(terrain_value as TerrainData)


func _on_area_exited(area: Area3D) -> void:
	var terrain_value: Variant = area.get("terrain")
	if terrain_value is TerrainData:
		_overlapping_terrain.erase(terrain_value as TerrainData)
