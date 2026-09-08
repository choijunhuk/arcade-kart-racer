extends SceneTree

## Headless track-authoring tool (spec §15.6): replaces a track's Checkpoints
## container with `count` equally-spaced Checkpoint instances (RespawnPoint
## already on the racing line, facing the direction of travel), then
## resaves the scene. Run against a fresh `track_template.tscn` copy after
## its RacingLine curve has been authored.
##
## Usage: godot --headless --path . -s tools/place_checkpoints.gd -- <track.tscn> [count]

const CHECKPOINT_SCENE: String = "res://track/elements/checkpoint.tscn"
const DEFAULT_COUNT: int = 8


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		print("Usage: place_checkpoints.gd <track.tscn> [count]")
		quit(1)
		return
	var track_path: String = arguments[0]
	var count: int = int(arguments[1]) if arguments.size() > 1 else DEFAULT_COUNT
	var scene: PackedScene = load(track_path) as PackedScene
	if scene == null:
		print("Could not load %s" % track_path)
		quit(1)
		return
	var track: Node = scene.instantiate()
	root.add_child(track)
	await physics_frame

	var racing_line: RacingLine = track.get_node_or_null("RacingLine") as RacingLine
	var checkpoints: Node = track.get_node_or_null("Checkpoints")
	if racing_line == null or checkpoints == null:
		print("Track is missing RacingLine or Checkpoints")
		quit(1)
		return

	_clear_children(checkpoints)
	_place_checkpoints(checkpoints, racing_line, track, count)

	var packed: PackedScene = PackedScene.new()
	var pack_error: Error = packed.pack(track)
	if pack_error != OK:
		print("Failed to pack scene: %s" % pack_error)
		quit(1)
		return
	var save_error: Error = ResourceSaver.save(packed, track_path)
	if save_error != OK:
		print("Failed to save %s: %s" % [track_path, save_error])
		quit(1)
		return
	print("Placed %d checkpoints in %s" % [count, track_path])
	quit(0)


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _place_checkpoints(checkpoints: Node, racing_line: RacingLine, owner_node: Node, count: int) -> void:
	var length: float = racing_line.length()
	var checkpoint_scene: PackedScene = load(CHECKPOINT_SCENE) as PackedScene
	for index: int in range(count):
		var offset: float = length * float(index) / float(count)
		var checkpoint: Node3D = checkpoint_scene.instantiate() as Node3D
		checkpoint.name = "Checkpoint%02d" % index
		checkpoints.add_child(checkpoint)
		checkpoint.owner = owner_node
		var position: Vector3 = racing_line.sample(offset)
		var tangent: Vector3 = racing_line.tangent_at(offset)
		checkpoint.global_transform = Transform3D(Basis.looking_at(tangent, Vector3.UP), position)
