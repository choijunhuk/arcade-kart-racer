class_name TrackShortcut
extends Node3D

## Track element: an alternate route off the main RacingLine. `TriggerArea`
## marks "on shortcut" so PositionTracker can substitute `progress_at()` for
## the normal checkpoint-window progress while a kart rides it (spec §14.4).

signal kart_entered(body: Node3D)
signal kart_exited(body: Node3D)

## Main-line offset where this shortcut branches off.
@export var entry_offset: float = 0.0
## Main-line offset where this shortcut rejoins.
@export var exit_offset: float = 0.0
## Alternate route geometry; progress along it maps to `[entry_offset, exit_offset]`.
@export var alt_curve: Path3D
## Minimum speed a driver should carry to attempt this shortcut safely.
@export var required_speed: float = 0.0
## AI entry-probability hint in [0, 1] (higher = more AI take it).
@export_range(0.0, 1.0) var risk: float = 0.5

@onready var _trigger: Area3D = $TriggerArea


func _ready() -> void:
	_trigger.body_entered.connect(_on_body_entered)
	_trigger.body_exited.connect(_on_body_exited)


## Interpolates main-line-equivalent progress from `entry_offset` to
## `exit_offset` using the kart's nearest position on `alt_curve`.
func progress_at(global_pos: Vector3) -> float:
	if alt_curve == null or alt_curve.curve == null or alt_curve.curve.point_count < 2:
		return entry_offset
	var local_pos: Vector3 = alt_curve.to_local(global_pos)
	var offset: float = alt_curve.curve.get_closest_offset(local_pos)
	var length: float = alt_curve.curve.get_baked_length()
	var t: float = clampf(offset / length, 0.0, 1.0) if length > 0.0 else 0.0
	return lerpf(entry_offset, exit_offset, t)


func _on_body_entered(body: Node3D) -> void:
	kart_entered.emit(body)


func _on_body_exited(body: Node3D) -> void:
	kart_exited.emit(body)
