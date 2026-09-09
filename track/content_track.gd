class_name ContentTrack
extends TrackRoot

## Shared greybox authoring primitives; theme tracks own dimensions and mechanics.

const SEGMENT_LENGTH: float = 6.0
const ARC_STEP: float = 7.5
const ROAD_HEIGHT: float = 0.4
const CHECKPOINT_COUNT: int = 12
const GRID_SPACING: float = 3.5
const GRID_LATERAL: float = 1.4
const ITEM_ROW_FRACTIONS: Array[float] = [0.10, 0.44, 0.76]
const ITEM_LANES: Array[float] = [-6.0, -3.0, 0.0, 3.0, 6.0]
const KILL_DEPTH: float = 200.0
const KILL_MARGIN: float = 60.0
const PAD_CONTACT_HEIGHT: float = 0.35
const SHORTCUT_GATE_MARGIN: float = 18.0
const CHECKPOINT_SCENE: PackedScene = preload("res://track/elements/checkpoint.tscn")
const BOX_SCENE: PackedScene = preload("res://track/elements/item_box.tscn")
const KILL_SCENE: PackedScene = preload("res://track/elements/kill_zone.tscn")
const BOOST_SCENE: PackedScene = preload("res://track/elements/boost_pad.tscn")
const JUMP_SCENE: PackedScene = preload("res://track/elements/jump_pad.tscn")
const OFFROAD_SCENE: PackedScene = preload("res://track/elements/offroad_zone.tscn")

@export var half_width: float = 300.0
@export var half_depth: float = 110.0
@export var corner_radius: float = 24.0
@export var road_width: float = 16.0
@export var wall_height: float = 3.0
@export var road_color: Color = Color(0.2, 0.22, 0.3)
@export var wall_color: Color = Color(0.2, 0.8, 1.0)
@export var wall_emission: float = 0.0

var line: RacingLine
var geometry: StaticBody3D
var road_material: StandardMaterial3D
var wall_material: StandardMaterial3D


func _ready() -> void:
	line = get_racing_line()
	geometry = $Geometry
	road_material = TrackArt.surface(road_color.lightened(0.25))
	wall_material = material(wall_color, wall_emission)
	_build_line()
	_build_road()
	_build_checkpoints_and_grid()
	_build_pickups_and_kill_plane()
	build_theme()
	super._ready()


## Theme-specific additions run after the shared geometry and before validation.
func build_theme() -> void:
	pass


## Authored elevation; subclasses can supply a smooth height profile.
func surface_height(_point: Vector3) -> float:
	return ROAD_HEIGHT


## Bank angle in radians for the physical road ribbon, not only its mesh.
func bank_at(_offset: float) -> float:
	return 0.0


## Omitted ribbon chords form real chasms; never put invisible road beneath them.
func is_gap(_point: Vector3) -> bool:
	return false


## Opens an inner wall where an authored shortcut joins the road.
func open_inner_wall(_point: Vector3) -> bool:
	return false


## Creates one editable standard material shared by a theme's primitives.
static func material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	result.emission_enabled = emission > 0.0
	result.emission = color
	result.emission_energy_multiplier = emission
	return result


## Adds and aligns an element to a main-line offset with optional lateral shift.
func place(scene: PackedScene, container: String, node_name: String, offset: float, lateral: float = 0.0) -> Node3D:
	var node: Node3D = scene.instantiate() as Node3D
	node.name = node_name
	get_node(container).add_child(node)
	node.global_transform = Transform3D(
		Basis.looking_at(line.tangent_at(offset), Vector3.UP),
		line.sample(offset) + line.right_at(offset) * lateral,
	)
	if node is BoostPad or node is JumpPad:
		node.position.y += PAD_CONTACT_HEIGHT
	return node


## Authors a surface overlay across the lane or on an offroad shoulder.
func terrain_patch(node_name: String, offset: float, size: Vector3, terrain: TerrainData, lateral: float = 0.0) -> OffroadZone:
	var zone: OffroadZone = place(OFFROAD_SCENE, "OffroadZones", node_name, offset, lateral) as OffroadZone
	zone.terrain = terrain
	zone.scale = size
	(zone.get_node("Surface") as MeshInstance3D).material_override = TrackArt.surface(terrain.particle_color, true)
	return zone


## Creates a path in track coordinates with an explicit starting location.
func make_path(container: String, node_name: String, points: Array[Vector3]) -> Path3D:
	var path: Path3D = Path3D.new()
	path.name = node_name
	path.curve = Curve3D.new()
	for point: Vector3 in points:
		path.curve.add_point(point)
	get_node(container).add_child(path)
	return path


## Builds a driveable alternate line and a trigger over its shortcut footprint.
func shortcut(node_name: String, entry: float, exit: float, points: Array[Vector3], required_speed: float, build_surface: bool = true) -> TrackShortcut:
	var route: TrackShortcut = TrackShortcut.new()
	route.name = node_name
	route.entry_offset = entry
	route.exit_offset = exit
	route.required_speed = required_speed
	route.risk = 0.5
	var trigger: Area3D = Area3D.new()
	trigger.name = "TriggerArea"
	trigger.collision_layer = 256
	trigger.collision_mask = 2
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	var start: Vector3 = points[0]
	var end: Vector3 = points.back()
	shape.size = Vector3(8.0, 8.0, start.distance_to(end))
	shape_node.shape = shape
	trigger.add_child(shape_node)
	route.add_child(trigger)
	$Shortcuts.add_child(route)
	trigger.global_transform = Transform3D(Basis.looking_at(end - start), (start + end) * 0.5)
	route.alt_curve = make_path("Shortcuts/%s" % node_name, "AltCurve", points)
	if build_surface:
		TrackBuilder.build_road_segments(geometry, route.alt_curve, 8.0, ROAD_HEIGHT, wall_material)
	# Both routes must pass the same ordered gates: move a bypassed gate past rejoin.
	for gate: Checkpoint in get_checkpoints():
		var offset: float = line.offset_at(gate.global_position)
		if offset > entry and offset < exit:
			var rejoin: float = exit + SHORTCUT_GATE_MARGIN
			gate.global_transform = Transform3D(Basis.looking_at(line.tangent_at(rejoin)), line.sample(rejoin) + Vector3.UP)
	return route


func _build_line() -> void:
	line.curve = Curve3D.new()
	_append_point(Vector3(0.0, 0.0, -half_depth))
	var centers: Array[Vector2] = [
		Vector2(-half_width + corner_radius, -half_depth + corner_radius),
		Vector2(-half_width + corner_radius, half_depth - corner_radius),
		Vector2(half_width - corner_radius, half_depth - corner_radius),
		Vector2(half_width - corner_radius, -half_depth + corner_radius),
	]
	for corner: int in range(centers.size()):
		var center: Vector2 = centers[corner]
		var start_angle: float = -90.0 - float(corner) * 90.0
		var steps: int = roundi(90.0 / ARC_STEP)
		for step: int in range(steps + 1):
			var angle: float = deg_to_rad(start_angle - float(step) * ARC_STEP)
			_append_point(Vector3(center.x + cos(angle) * corner_radius, 0.0, center.y + sin(angle) * corner_radius))
	_append_point(Vector3(0.0, 0.0, -half_depth))
	line.bake()


func _append_point(point: Vector3) -> void:
	# Subdivide straights too, so elevation is represented in the actual curve.
	if line.curve.point_count > 0:
		var previous: Vector3 = line.curve.get_point_position(line.curve.point_count - 1)
		var distance: float = Vector2(point.x - previous.x, point.z - previous.z).length()
		var count: int = maxi(1, ceili(distance / SEGMENT_LENGTH))
		for index: int in range(1, count):
			var sample: Vector3 = previous.lerp(point, float(index) / float(count))
			sample.y = surface_height(sample)
			line.curve.add_point(sample)
	point.y = surface_height(point)
	line.curve.add_point(point)


func _build_road() -> void:
	RoadRibbon.build(self)
	var count: int = ceili(line.length() / SEGMENT_LENGTH)
	for index: int in range(count):
		var from_offset: float = line.length() * float(index) / float(count)
		var to_offset: float = line.length() * float(index + 1) / float(count)
		var start: Vector3 = line.sample(from_offset)
		var end: Vector3 = line.sample(to_offset)
		var middle: Vector3 = (start + end) * 0.5
		if is_gap(middle):
			continue
		var bank: float = bank_at(from_offset)
		for side: float in [-1.0, 1.0]:
			if side < 0.0 and open_inner_wall(middle):
				continue
			var lateral: float = (road_width + 1.0) * 0.5 * side
			var raised: Vector3 = Vector3.UP * (wall_height * 0.5 + absf(sin(bank)) * road_width * 0.5)
			TrackBuilder.add_box_segment(geometry,
				start + line.right_at(from_offset) * lateral + raised,
				end + line.right_at(to_offset) * lateral + raised,
				1.0, wall_height, wall_material)


func _build_checkpoints_and_grid() -> void:
	for index: int in range(CHECKPOINT_COUNT):
		var offset: float = line.length() * float(index) / float(CHECKPOINT_COUNT)
		var gate: Checkpoint = place(CHECKPOINT_SCENE, "Checkpoints", "Checkpoint%02d" % index, offset) as Checkpoint
		gate.position.y += 1.0
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(road_width, 6.0, 2.0)
		(gate.get_node("CollisionShape3D") as CollisionShape3D).shape = shape
	for index: int in range(MIN_GRID_SLOTS):
		var offset: float = 3.0 + GRID_SPACING * float(index / 2)
		var marker: Marker3D = Marker3D.new()
		marker.name = "Grid%02d" % (index + 1)
		$StartGrid.add_child(marker)
		var lateral: float = GRID_LATERAL if index % 2 == 0 else -GRID_LATERAL
		var facing: Vector3 = line.tangent_at(offset)
		facing.y = 0.0
		marker.global_transform = Transform3D(Basis.looking_at(facing.normalized()), line.sample(offset) + line.right_at(offset) * lateral + Vector3.UP * 0.5)


func _build_pickups_and_kill_plane() -> void:
	for row: int in range(ITEM_ROW_FRACTIONS.size()):
		for lane: int in range(ITEM_LANES.size()):
			var box: Node3D = place(BOX_SCENE, "ItemBoxes", "ItemBoxRow%d_%d" % [row, lane], line.length() * ITEM_ROW_FRACTIONS[row], ITEM_LANES[lane])
			box.position.y += 0.5
	var kill: KillZone = KILL_SCENE.instantiate() as KillZone
	kill.name = "FallPlane"
	$KillZones.add_child(kill)
	kill.position = Vector3(0.0, -KILL_DEPTH * 0.5 - 12.0, 0.0)
	kill.scale = Vector3(half_width * 2.0 + KILL_MARGIN, KILL_DEPTH, half_depth * 2.0 + KILL_MARGIN)
