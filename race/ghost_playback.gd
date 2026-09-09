class_name GhostPlayback
extends Node3D

## Replays real kart physics and independently detects checkpoint crossings.

const KART_SCENE_PATH: String = "res://kart/kart.tscn"
const GHOST_ALPHA: float = 0.32
const CHECKPOINT_MASK: int = 16
const MAX_QUERY_RESULTS: int = 32

var kart: KartController
var provider: GhostInputProvider
var ticks: int = 0
var finish_ticks: int = -1
var next_checkpoint: int = 1
var _checkpoint_count: int = 0
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var world_replay: GhostWorldReplay


## Instantiates a translucent input-driven kart, outside every race registration.
func setup(recording: GhostRecording, track: TrackRoot) -> void:
	kart = (load(KART_SCENE_PATH) as PackedScene).instantiate() as KartController
	kart.name = "GhostKart"
	kart.collision_layer = 0
	kart.collision_mask = 0
	var bump: Area3D = kart.get_node("BumpArea") as Area3D
	bump.collision_layer = 0
	bump.collision_mask = 0
	add_child(kart)
	kart.set_physics_process(false)
	KartReplayState.restore(kart, recording.initial_state)
	var motion: KartWorldMotion = KartWorldMotion.new()
	motion.name = "WorldMotion"
	kart.add_child(motion)
	motion.setup(kart)
	(kart.get_node("KartPhysics") as KartPhysics).set_ghost_motion(motion)
	provider = GhostInputProvider.new(recording, kart)
	world_replay = GhostWorldReplay.new()
	add_child(world_replay)
	world_replay.setup(track, kart, motion)
	provider.before_frame = world_replay.apply_frame
	kart.set_input_provider(provider)
	_checkpoint_count = track.get_checkpoints().size()
	_query.shape = (kart.get_node("CollisionShape3D") as CollisionShape3D).shape
	_query.collision_mask = CHECKPOINT_MASK
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	for mesh: Node in kart.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).transparency = 1.0 - GHOST_ALPHA
	for path: String in ["KartAudio", "DriftEffects", "BoostEffects", "SlipstreamSensor"]:
		kart.get_node(path).process_mode = Node.PROCESS_MODE_DISABLED
	(kart.get_node("SlipstreamSensor/ShapeCast3D") as ShapeCast3D).collision_mask = 0
	(kart.get_node("SlipstreamSensor/ShapeCast3D") as ShapeCast3D).enabled = false


## Queries before movement, matching Area3D's next-tick notification boundary.
func step(delta: float) -> void:
	if kart == null or finish_ticks >= 0:
		return
	_query.transform = kart.global_transform
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(_query, MAX_QUERY_RESULTS):
		var checkpoint: Checkpoint = hit.get("collider") as Checkpoint
		if checkpoint != null and checkpoint.index == next_checkpoint:
			if next_checkpoint == 0:
				finish_ticks = ticks
				return
			next_checkpoint = (next_checkpoint + 1) % _checkpoint_count
	kart._physics_process(delta)
	ticks += 1
