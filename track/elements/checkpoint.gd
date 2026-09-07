class_name Checkpoint
extends Area3D

## Track element: order/offset are assigned by `Track` from child index at
## `_ready()` (spec: "index auto-assigned from child order by Track"), never
## queried upward by this node. Emits a generic body signal so LapTracker
## (not Track) is the one that knows about KartController (spec §6.5).

signal body_passed(body: Node3D, index: int)

@onready var _respawn_point: Marker3D = $RespawnPoint

var index: int = -1
var offset: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## Assigns this checkpoint's order index and racing-line offset. Called once
## per child by `Track._configure_checkpoints()`.
func configure(new_index: int, racing_line: RacingLine) -> void:
	index = new_index
	offset = racing_line.offset_at(global_position)


func get_respawn_point() -> Marker3D:
	return _respawn_point


func _on_body_entered(body: Node3D) -> void:
	body_passed.emit(body, index)
