class_name KartData
extends Resource

enum WeightClass {
	LIGHT,
	MEDIUM,
	HEAVY,
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var weight_class: WeightClass = WeightClass.MEDIUM
@export var max_speed: float = 28.0
@export var acceleration: float = 14.0
@export var handling: float = 1.0
@export var drift_factor: float = 1.0
## Mini-turbo charge rate multiplier; lighter karts charge faster (spec §10.3).
@export var drift_charge_mult: float = 1.0
@export var weight: float = 1.0
@export var traction: float = 1.0
@export var boost_power: float = 1.0
@export_range(0.0, 1.0) var offroad_resistance: float = 0.0
@export var mesh_scene: PackedScene
@export var body_color: Color = Color.WHITE
