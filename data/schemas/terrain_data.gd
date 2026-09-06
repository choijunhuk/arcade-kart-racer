class_name TerrainData
extends Resource

@export var id: StringName = &"asphalt"
@export var display_name: String = "Asphalt"
@export var speed_mult: float = 1.0
@export var grip: float = 1.0
@export var drag_mult: float = 1.0
@export var particle_color: Color = Color(0.65, 0.65, 0.65)
@export var particle_type: StringName = &"road_dust"
@export var sound_type: StringName = &"asphalt"
@export var sfx: AudioStream
