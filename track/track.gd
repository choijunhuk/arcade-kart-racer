class_name TrackRoot
extends Node3D

## Track-scene contract + read-only query API for Race/AI/UI (spec §8, §15).
## Never references Kart; checkpoint order/offset are assigned here from
## child index so Checkpoint itself never looks upward (spec §29 rule 5).

const REQUIRED_NODES: Array[StringName] = [
	&"Geometry",
	&"Environment",
	&"RacingLine",
	&"Checkpoints",
	&"StartGrid",
	&"ItemBoxes",
	&"BoostPads",
	&"JumpPads",
	&"OffroadZones",
	&"Hazards",
	&"KillZones",
	&"MovingObstacles",
	&"Shortcuts",
]

## Minimum StartGrid slots; `get_start_grid()` pads shorter tracks using
## `StartGrid.generate()` (spec §15.2/§15.5).
const MIN_GRID_SLOTS: int = 8


func _ready() -> void:
	for missing_path: NodePath in validate_required_nodes():
		push_error("Track is missing required node: %s" % missing_path)
	_configure_checkpoints()


## Returns all direct-child paths missing from the track scene contract.
func validate_required_nodes() -> Array[NodePath]:
	var missing: Array[NodePath] = []
	for node_name: StringName in REQUIRED_NODES:
		var path: NodePath = NodePath(String(node_name))
		if get_node_or_null(path) == null:
			missing.append(path)
	return missing


## Returns the `Checkpoints` children in child (= racing) order.
func get_checkpoints() -> Array[Checkpoint]:
	var result: Array[Checkpoint] = []
	var container: Node = get_node_or_null("Checkpoints")
	if container == null:
		return result
	for child: Node in container.get_children():
		if child is Checkpoint:
			result.append(child as Checkpoint)
	return result


func get_racing_line() -> RacingLine:
	return get_node_or_null("RacingLine") as RacingLine


## Returns StartGrid transforms in child order, padded to `MIN_GRID_SLOTS`
## with `StartGrid.generate()` when the authored track has fewer markers.
func get_start_grid() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var container: Node = get_node_or_null("StartGrid")
	if container == null:
		return result
	for child: Node in container.get_children():
		if child is Marker3D:
			result.append((child as Marker3D).global_transform)
	if not result.is_empty() and result.size() < MIN_GRID_SLOTS:
		var missing: int = MIN_GRID_SLOTS - result.size()
		result.append_array(StartGrid.generate(result[result.size() - 1], missing))
	return result


## Returns the `ItemBoxes` children (as Node3D anchors).
func get_item_box_anchors() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var container: Node = get_node_or_null("ItemBoxes")
	if container == null:
		return result
	for child: Node in container.get_children():
		if child is Node3D:
			result.append(child as Node3D)
	return result


## Total baked racing-line length, or 0.0 if the line is not ready yet.
func get_lap_length() -> float:
	var racing_line: RacingLine = get_racing_line()
	return racing_line.length() if racing_line != null else 0.0


## Assigns each Checkpoint's `index`/`offset` from its position among
## siblings. Runs in `_ready()`, after RacingLine's own `_ready()` has baked
## or built its curve (children ready before parents in Godot).
func _configure_checkpoints() -> void:
	var racing_line: RacingLine = get_racing_line()
	if racing_line == null:
		return
	var index: int = 0
	for checkpoint: Checkpoint in get_checkpoints():
		checkpoint.configure(index, racing_line)
		index += 1
