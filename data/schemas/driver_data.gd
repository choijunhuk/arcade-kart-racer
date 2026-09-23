class_name DriverData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var portrait: Texture2D
@export var mesh_scene: PackedScene
@export var driver_color: Color = Color.WHITE
## Kart livery (presentation only). Transparent primary = use driver_color.
@export var livery_primary: Color = Color(0, 0, 0, 0)
@export var livery_accent: Color = Color.WHITE
@export_range(0, 99) var race_number: int = 0
## Face painted on the driver's head (presentation only, kart/driver_face.gdshader).
@export var skin_tone: Color = Color(0.96, 0.78, 0.64)
@export var eye_color: Color = Color(0.28, 0.48, 0.9)
@export var hair_color: Color = Color(0.32, 0.2, 0.12)
@export_enum("Cheerful", "Confident", "Fierce", "Calm") var face_expression: int = 0
@export var stat_mods: Dictionary[StringName, float] = {}
@export var voice_set: StringName = &""
## AI judgment/style traits (spec §18d); null = neutral (all 0.5), i.e. this
## driver's AI behaves exactly as it did before this phase existed.
@export var ai_personality: AIPersonality
