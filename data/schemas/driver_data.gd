class_name DriverData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var portrait: Texture2D
@export var mesh_scene: PackedScene
@export var driver_color: Color = Color.WHITE
@export var stat_mods: Dictionary[StringName, float] = {}
@export var voice_set: StringName = &""
## AI judgment/style traits (spec §18d); null = neutral (all 0.5), i.e. this
## driver's AI behaves exactly as it did before this phase existed.
@export var ai_personality: AIPersonality
