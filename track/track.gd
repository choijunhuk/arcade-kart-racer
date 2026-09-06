class_name TrackRoot
extends Node3D

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


func _ready() -> void:
	for missing_path: NodePath in validate_required_nodes():
		push_error("Track is missing required node: %s" % missing_path)


## Returns all direct-child paths missing from the track scene contract.
func validate_required_nodes() -> Array[NodePath]:
	var missing: Array[NodePath] = []
	for node_name: StringName in REQUIRED_NODES:
		var path: NodePath = NodePath(String(node_name))
		if get_node_or_null(path) == null:
			missing.append(path)
	return missing
