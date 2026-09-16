extends SceneTree

const DEFAULT_TRACK_PATH: String = "res://track/tracks/test_loop/test_loop.tscn"
const MIN_CHECKPOINTS: int = 4
const MIN_START_SLOTS: int = 8
const MAX_GRID_LINE_DISTANCE: float = 10.0
const CLOSED_LINE_DISTANCE: float = 1.0
const MIN_ITEM_BOXES: int = 6
const MAX_ITEM_LINE_DISTANCE: float = 8.0
const KILL_ZONE_SAMPLE_STEP: float = 5.0
const MIN_KILL_DEPTH: float = 32.0
const REJOIN_SLOT_TOLERANCE: float = 1.0
const REJOIN_GATE_MARGIN: float = 18.0


func _init() -> void:
	call_deferred("_validate_requested_track")


func _validate_requested_track() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var track_path: String = arguments[0] if not arguments.is_empty() else DEFAULT_TRACK_PATH
	var resource: Resource = load(track_path)
	if not resource is PackedScene:
		print("TRACK VALIDATION FAILED: unable to load %s" % track_path)
		quit(1)
		return
	var track: Node = (resource as PackedScene).instantiate()
	root.add_child(track)
	await physics_frame
	var errors: PackedStringArray = _collect_errors(track)
	if not errors.is_empty():
		for error: String in errors:
			print("ERROR: %s" % error)
		print("TRACK VALIDATION FAILED: %s" % track_path)
		quit(1)
		return
	print("TRACK VALIDATION PASSED: %s" % track_path)
	quit(0)


func _collect_errors(track: Node) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var track_root: TrackRoot = track as TrackRoot
	if track_root == null:
		errors.append("Root must use track/track.gd")
		return errors
	for missing_path: NodePath in track_root.validate_required_nodes():
		errors.append("Missing required node: %s" % missing_path)
	var checkpoints: Node = track.get_node_or_null("Checkpoints")
	var start_grid: Node = track.get_node_or_null("StartGrid")
	var item_boxes: Node = track.get_node_or_null("ItemBoxes")
	var kill_zones: Node = track.get_node_or_null("KillZones")
	var racing_line: Path3D = track.get_node_or_null("RacingLine") as Path3D
	_validate_checkpoint_contract(checkpoints, errors)
	_validate_grid_contract(start_grid, racing_line, errors)
	_validate_racing_line(racing_line, errors)
	_validate_checkpoint_offsets(checkpoints, racing_line, errors)
	errors.append_array(shortcut_errors(track))
	_validate_respawn_ground(checkpoints, track, errors)
	_validate_item_boxes(item_boxes, racing_line, errors)
	_validate_kill_zone_coverage(kill_zones, track, errors)
	return errors


func _validate_checkpoint_contract(checkpoints: Node, errors: PackedStringArray) -> void:
	if checkpoints == null:
		return
	if checkpoints.get_child_count() < MIN_CHECKPOINTS:
		errors.append("Checkpoints must contain at least %d Area3D nodes" % MIN_CHECKPOINTS)
	for checkpoint: Node in checkpoints.get_children():
		if not checkpoint is Area3D:
			errors.append("Checkpoint %s must be an Area3D" % checkpoint.name)
		elif checkpoint.get_node_or_null("RespawnPoint") == null:
			errors.append("Checkpoint %s needs a RespawnPoint" % checkpoint.name)


func _validate_grid_contract(start_grid: Node, racing_line: Path3D, errors: PackedStringArray) -> void:
	if start_grid == null:
		return
	if start_grid.get_child_count() < MIN_START_SLOTS:
		errors.append("StartGrid must contain at least %d Marker3D nodes" % MIN_START_SLOTS)
	if racing_line == null or racing_line.curve == null:
		return
	for grid_slot: Node in start_grid.get_children():
		if not grid_slot is Marker3D:
			errors.append("Start slot %s must be a Marker3D" % grid_slot.name)
			continue
		var local_position: Vector3 = racing_line.to_local((grid_slot as Marker3D).global_position)
		var closest: Vector3 = racing_line.curve.get_closest_point(local_position)
		if local_position.distance_to(closest) > MAX_GRID_LINE_DISTANCE:
			errors.append("Start slot %s is more than %.1fm from RacingLine" % [grid_slot.name, MAX_GRID_LINE_DISTANCE])


func _validate_racing_line(racing_line: Path3D, errors: PackedStringArray) -> void:
	if racing_line == null or racing_line.curve == null:
		errors.append("RacingLine must have a Curve3D")
		return
	if racing_line.curve.point_count < 2:
		errors.append("RacingLine must contain at least two points")
		return
	var first: Vector3 = racing_line.curve.get_point_position(0)
	var last: Vector3 = racing_line.curve.get_point_position(racing_line.curve.point_count - 1)
	if first.distance_to(last) >= CLOSED_LINE_DISTANCE:
		errors.append("RacingLine must close within %.1fm" % CLOSED_LINE_DISTANCE)


func _validate_checkpoint_offsets(checkpoints: Node, racing_line: Path3D, errors: PackedStringArray) -> void:
	if checkpoints == null or racing_line == null or racing_line.curve == null:
		return
	var previous_offset: float = -1.0
	for checkpoint: Node in checkpoints.get_children():
		if not checkpoint is Node3D:
			continue
		var offset: float = _checkpoint_offset(checkpoint as Node3D, racing_line)
		if offset <= previous_offset:
			errors.append("Checkpoint offsets must increase in child order at %s (offset %.1f after %.1f)" % [checkpoint.name, offset, previous_offset])
		previous_offset = offset


static func _checkpoint_offset(checkpoint: Node3D, racing_line: Path3D) -> float:
	if checkpoint is Checkpoint:
		return (checkpoint as Checkpoint).offset
	return racing_line.curve.get_closest_offset(racing_line.to_local(checkpoint.global_position))


## Shortcut invariants (Phase 18k): entry precedes exit, relocated rejoin gates
## do not collapse onto one offset, and the last rejoin gate still sits before
## the next main-line checkpoint so child-order offsets stay strictly
## increasing. Static so tests can call it on a live track without running the
## whole CLI validator.
static func shortcut_errors(track: Node) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var shortcuts: Node = track.get_node_or_null("Shortcuts")
	var checkpoints: Node = track.get_node_or_null("Checkpoints")
	var racing_line: Path3D = track.get_node_or_null("RacingLine") as Path3D
	if shortcuts == null or checkpoints == null or racing_line == null or racing_line.curve == null:
		return errors
	var offsets: Array[float] = []
	var names: PackedStringArray = PackedStringArray()
	for checkpoint: Node in checkpoints.get_children():
		if checkpoint is Node3D:
			offsets.append(_checkpoint_offset(checkpoint as Node3D, racing_line))
			names.append(checkpoint.name)
	for child: Node in shortcuts.get_children():
		if not child is TrackShortcut:
			continue
		var route: TrackShortcut = child as TrackShortcut
		if route.entry_offset >= route.exit_offset:
			errors.append("Shortcut %s entry_offset %.1f must be before exit_offset %.1f" % [route.name, route.entry_offset, route.exit_offset])
			continue
		var last_rejoin: int = -1
		for index: int in range(offsets.size()):
			var offset: float = offsets[index]
			if not _is_rejoin_slot(offset, route.exit_offset):
				continue
			if last_rejoin == index - 1 and last_rejoin >= 0 and offset <= offsets[last_rejoin]:
				errors.append("Shortcut %s rejoin gates %s and %s collapsed onto the same offset %.1f" % [route.name, names[last_rejoin], names[index], offset])
			last_rejoin = index
		if last_rejoin >= 0 and last_rejoin + 1 < offsets.size() and offsets[last_rejoin + 1] <= offsets[last_rejoin]:
			errors.append("Shortcut %s rejoin gate %s (offset %.1f) lands at or after the next checkpoint %s (%.1f)" % [route.name, names[last_rejoin], offsets[last_rejoin], names[last_rejoin + 1], offsets[last_rejoin + 1]])
	return errors


## True when `offset` sits on one of ContentTrack.shortcut()'s rejoin slots
## (exit + REJOIN_GATE_MARGIN * n, n >= 1), within reprojection tolerance.
## REJOIN_GATE_MARGIN mirrors ContentTrack.SHORTCUT_GATE_MARGIN (asserted by
## tests/unit/test_shortcut_rejoin_gates.gd) because this script runs under
## `godot -s` without autoloads, where loading ContentTrack fails to compile.
static func _is_rejoin_slot(offset: float, exit_offset: float) -> bool:
	var steps: float = (offset - exit_offset) / REJOIN_GATE_MARGIN
	return steps >= 0.9 and absf(steps - roundf(steps)) * REJOIN_GATE_MARGIN <= REJOIN_SLOT_TOLERANCE


func _validate_respawn_ground(checkpoints: Node, track: Node, errors: PackedStringArray) -> void:
	if checkpoints == null or not track is Node3D:
		return
	var world: World3D = (track as Node3D).get_world_3d()
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	for checkpoint: Node in checkpoints.get_children():
		var respawn: Marker3D = checkpoint.get_node_or_null("RespawnPoint") as Marker3D
		if respawn == null:
			continue
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			respawn.global_position + Vector3.UP,
			respawn.global_position + Vector3.DOWN * 5.0,
			1,
		)
		if space_state.intersect_ray(query).is_empty():
			errors.append("RespawnPoint for %s has no world ground below it" % checkpoint.name)


## §15.5: item boxes >= MIN_ITEM_BOXES, each within MAX_ITEM_LINE_DISTANCE of the racing line.
func _validate_item_boxes(item_boxes: Node, racing_line: Path3D, errors: PackedStringArray) -> void:
	if item_boxes == null:
		errors.append("Track is missing an ItemBoxes container")
		return
	if item_boxes.get_child_count() < MIN_ITEM_BOXES:
		errors.append("ItemBoxes must contain at least %d boxes" % MIN_ITEM_BOXES)
	if racing_line == null or racing_line.curve == null:
		return
	for box: Node in item_boxes.get_children():
		if not box is Node3D:
			continue
		var local_position: Vector3 = racing_line.to_local((box as Node3D).global_position)
		var closest: Vector3 = racing_line.curve.get_closest_point(local_position)
		if local_position.distance_to(closest) > MAX_ITEM_LINE_DISTANCE:
			errors.append("ItemBox %s is more than %.1fm from RacingLine" % [box.name, MAX_ITEM_LINE_DISTANCE])


## §15.5: KillZones must cover the horizontal (X/Z) footprint under the
## track's own geometry, so any fall anywhere over the track is caught.
func _validate_kill_zone_coverage(kill_zones: Node, track: Node, errors: PackedStringArray) -> void:
	if kill_zones == null or kill_zones.get_child_count() == 0:
		errors.append("Track needs at least one KillZone covering its fall area")
		return
	var geometry: Node = track.get_node_or_null("Geometry")
	if geometry == null:
		return
	var track_rect: Rect2 = _horizontal_aabb(geometry)
	var floor_y: float = INF
	for shape: CollisionShape3D in _collect_collision_shapes(geometry):
		floor_y = minf(floor_y, _shape_world_aabb(shape).position.y)
	for shape: CollisionShape3D in _collect_collision_shapes(kill_zones):
		if not kill_plane_is_safe(_shape_world_aabb(shape), floor_y):
			errors.append("KillZone must be below geometry with at least %.0fm vertical depth" % MIN_KILL_DEPTH)
	if track_rect.size == Vector2.ZERO:
		return
	var kill_rect: Rect2 = _horizontal_aabb(kill_zones)
	if kill_rect.size == Vector2.ZERO:
		errors.append("KillZones have no measurable coverage area")
		return
	var uncovered: PackedVector2Array = _sample_uncovered_corners(track_rect, kill_rect)
	if not uncovered.is_empty():
		errors.append("KillZones do not cover the full track footprint (e.g. missed point %s)" % uncovered[0])


## Unions the world-space X/Z rectangle of every CollisionShape3D under `node`.
func _horizontal_aabb(node: Node) -> Rect2:
	var rect: Rect2 = Rect2()
	var started: bool = false
	for shape: CollisionShape3D in _collect_collision_shapes(node):
		var shape_aabb: AABB = _shape_world_aabb(shape)
		var shape_rect: Rect2 = Rect2(shape_aabb.position.x, shape_aabb.position.z, shape_aabb.size.x, shape_aabb.size.z)
		if not started:
			rect = shape_rect
			started = true
		else:
			rect = rect.merge(shape_rect)
	return rect


func _collect_collision_shapes(node: Node) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	if node is CollisionShape3D:
		result.append(node as CollisionShape3D)
	for child: Node in node.get_children():
		result.append_array(_collect_collision_shapes(child))
	return result


func _shape_world_aabb(shape: CollisionShape3D) -> AABB:
	var extents: Vector3 = Vector3.ONE
	if shape.shape is BoxShape3D:
		extents = (shape.shape as BoxShape3D).size * 0.5
	elif shape.shape is SphereShape3D:
		var radius: float = (shape.shape as SphereShape3D).radius
		extents = Vector3(radius, radius, radius)
	else:
		if shape.shape != null:
			return shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
	var local_aabb: AABB = AABB(-extents, extents * 2.0)
	return shape.global_transform * local_aabb


## Checks the track rectangle's corners (and center) fall inside `kill_rect`;
## a lightweight coverage proxy rather than exact polygon containment.
func _sample_uncovered_corners(track_rect: Rect2, kill_rect: Rect2) -> PackedVector2Array:
	var uncovered: PackedVector2Array = PackedVector2Array()
	var points: Array[Vector2] = [
		track_rect.position,
		track_rect.position + Vector2(track_rect.size.x, 0.0),
		track_rect.position + Vector2(0.0, track_rect.size.y),
		track_rect.position + track_rect.size,
		track_rect.get_center(),
	]
	for point: Vector2 in points:
		if not kill_rect.has_point(point):
			uncovered.append(point)
	return uncovered


## Thick planes below the lowest geometry catch fast falls without tunnelling.
static func kill_plane_is_safe(bounds: AABB, floor_y: float) -> bool:
	return bounds.size.y >= MIN_KILL_DEPTH and bounds.end.y < floor_y
