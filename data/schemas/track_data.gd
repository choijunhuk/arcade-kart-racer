class_name TrackData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene
@export var laps_default: int = 3
@export var preview: Texture2D
@export var preview_color: Color = Color(0.08, 0.24, 0.31)
@export var bgm: AudioStream
## Original track identity; placeholder streams may be shared until Phase 13.
@export var bgm_id: StringName = &"race"
@export var minimap_line_points: PackedVector2Array = PackedVector2Array()
@export var lap_length_hint: float = 0.0
