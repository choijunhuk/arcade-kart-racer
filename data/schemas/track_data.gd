class_name TrackData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene
@export var laps_default: int = 3
@export var preview: Texture2D
@export var bgm: AudioStream
@export var minimap_line_points: PackedVector2Array = PackedVector2Array()
@export var lap_length_hint: float = 0.0
