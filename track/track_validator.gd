extends SceneTree

const DEFAULT_TRACK_PATH: String = "res://track/tracks/test_loop/test_loop.tscn"
const MIN_CHECKPOINTS: int = 4
const MIN_START_SLOTS: int = 8
const MAX_GRID_LINE_DISTANCE: float = 10.0
const CLOSED_LINE_DISTANCE: float = 1.0


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
	var errors: PackedStringArray = _collect_errors(track)
	_print_phase_later_warnings(track)
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
	var racing_line: Path3D = track.get_node_or_null("RacingLine") as Path3D
	_validate_checkpoint_contract(checkpoints, errors)
	_validate_grid_contract(start_grid, racing_line, errors)
	_validate_racing_line(racing_line, errors)
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


func _print_phase_later_warnings(track: Node) -> void:
	var item_boxes: Node = track.get_node_or_null("ItemBoxes")
	if item_boxes == null or item_boxes.get_child_count() == 0:
		print("WARNING: Item-box count/proximity check skipped until Phase 4")
	var kill_zones: Node = track.get_node_or_null("KillZones")
	if kill_zones == null or kill_zones.get_child_count() == 0:
		print("WARNING: Kill-zone coverage check skipped until Phase 4")
	print("WARNING: Respawn ground raycast and monotonic offset checks skipped until Phase 4 metadata exists")
