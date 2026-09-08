class_name AISensors
extends Node3D

## Forward-left/center/right + rear `ShapeCast3D` perception (spec §13.2).
## Extends Node3D (not a plain Node) because `ShapeCast3D` only inherits a
## global transform from its *direct* Node3D ancestor chain; a plain-Node
## container here would leave the casts stuck at the world origin instead of
## following the kart. Refreshed only on AI ticks (spec §26), never every
## physics frame. Reports perception only; makes no decisions.

const FORWARD_RANGE: float = 16.0
const REAR_RANGE: float = 10.0
const LANE_PROBE_OFFSET: float = 1.6
const PROBE_SHAPE_SIZE: Vector3 = Vector3(0.8, 0.6, 0.6)
## Local height above the kart's own origin (spec's road top sits ~0.35 m
## below it, per `PhysicsTuning.hover_height`); keeps the probe box clear of
## the road/ground `StaticBody3D` (world, layer 1) while still low enough to
## catch a wall (walls are ~2 m tall, spec §15.6).
const PROBE_HEIGHT: float = 0.5
## World (layer 1) | kart_body (layer 2) — spec §13.2's "레이어 마스크 1|2".
const CAST_MASK: int = 0b11
const PROJECTILE_SENSE_RANGE: float = 14.0
const PROJECTILE_APPROACH_DOT: float = 0.35

enum Side { LEFT = -1, CENTER = 0, RIGHT = 1 }

class SensorReport extends RefCounted:
	var kart_ahead_distance: float = INF
	var kart_ahead_relative_speed: float = 0.0
	var kart_ahead_side: int = AISensors.Side.CENTER
	var obstacle_hit: Dictionary[int, bool] = {}
	var obstacle_distance: Dictionary[int, float] = {}
	var rear_kart_distance: float = INF
	var rear_kart_relative_speed: float = 0.0
	## Populated from `ItemManager.active_projectiles` (spec §13.5/§26).
	var incoming_projectile: bool = false

	func side_clear(side: int) -> bool:
		return not bool(obstacle_hit.get(side, false))


var _owner_kart: KartController
var _forward_casts: Dictionary[int, ShapeCast3D] = {}
var _rear_cast: ShapeCast3D
var _item_manager: ItemManager


## Builds the four probes as children and excludes `kart` from every cast.
func setup(kart: KartController, item_manager: ItemManager = null) -> void:
	_owner_kart = kart
	_item_manager = item_manager
	_forward_casts[Side.LEFT] = _make_cast(Vector3(-LANE_PROBE_OFFSET, PROBE_HEIGHT, 0.0), Vector3(0.0, 0.0, -FORWARD_RANGE))
	_forward_casts[Side.CENTER] = _make_cast(Vector3(0.0, PROBE_HEIGHT, 0.0), Vector3(0.0, 0.0, -FORWARD_RANGE))
	_forward_casts[Side.RIGHT] = _make_cast(Vector3(LANE_PROBE_OFFSET, PROBE_HEIGHT, 0.0), Vector3(0.0, 0.0, -FORWARD_RANGE))
	_rear_cast = _make_cast(Vector3(0.0, PROBE_HEIGHT, 0.0), Vector3(0.0, 0.0, REAR_RANGE))


## Refreshes every cast and returns one immutable perception snapshot.
func tick() -> SensorReport:
	var report: SensorReport = SensorReport.new()
	for side: int in _forward_casts.keys():
		_scan_forward(side, _forward_casts[side], report)
	_scan_rear(_rear_cast, report)
	report.incoming_projectile = _sense_projectile()
	return report


func _scan_forward(side: int, cast: ShapeCast3D, report: SensorReport) -> void:
	cast.force_shapecast_update()
	for index: int in cast.get_collision_count():
		var collider: Object = cast.get_collider(index)
		var distance: float = _owner_kart.global_position.distance_to(cast.get_collision_point(index))
		if collider is KartController:
			if distance < report.kart_ahead_distance:
				report.kart_ahead_distance = distance
				report.kart_ahead_side = side
				report.kart_ahead_relative_speed = _owner_kart.get_speed() - (collider as KartController).get_speed()
		else:
			report.obstacle_hit[side] = true
			report.obstacle_distance[side] = minf(distance, report.obstacle_distance.get(side, INF))


func _scan_rear(cast: ShapeCast3D, report: SensorReport) -> void:
	cast.force_shapecast_update()
	for index: int in cast.get_collision_count():
		var collider: Object = cast.get_collider(index)
		if collider is KartController:
			var distance: float = _owner_kart.global_position.distance_to(cast.get_collision_point(index))
			if distance < report.rear_kart_distance:
				report.rear_kart_distance = distance
				report.rear_kart_relative_speed = (collider as KartController).get_speed() - _owner_kart.get_speed()


## Returns whether a projectile lies ahead, in range, and moves toward owner.
static func projectile_is_approaching(
	owner_position: Vector3, owner_forward: Vector3, projectile_position: Vector3,
	projectile_direction: Vector3, sense_range: float,
) -> bool:
	var owner_to_projectile: Vector3 = projectile_position - owner_position
	if owner_to_projectile.length() > sense_range or owner_to_projectile.dot(owner_forward) <= 0.0:
		return false
	var projectile_to_owner: Vector3 = -owner_to_projectile.normalized()
	return projectile_direction.normalized().dot(projectile_to_owner) >= PROJECTILE_APPROACH_DOT


## Reads the injected race-local active projectile registry once per AI tick.
func _sense_projectile() -> bool:
	if _item_manager == null or _owner_kart == null:
		return false
	for projectile: ItemBase in _item_manager.get_active_projectiles():
		if projectile.owner_kart == _owner_kart or not is_instance_valid(projectile):
			continue
		if projectile_is_approaching(
			_owner_kart.global_position, _owner_kart.get_forward(), projectile.global_position,
			projectile.get_travel_direction(), PROJECTILE_SENSE_RANGE,
		):
			return true
	return false


func _make_cast(local_position: Vector3, target: Vector3) -> ShapeCast3D:
	var cast: ShapeCast3D = ShapeCast3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = PROBE_SHAPE_SIZE
	cast.shape = shape
	cast.position = local_position
	cast.target_position = target
	cast.collision_mask = CAST_MASK
	add_child(cast)
	cast.add_exception(_owner_kart)
	return cast
