class_name ItemData
extends Resource

enum ItemCategory {
	PROJECTILE,
	HOMING,
	TRAP,
	BOOST,
	SHIELD,
	AREA,
	LEADER_STRIKE,
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
@export var scene: PackedScene
@export var category: ItemCategory = ItemCategory.PROJECTILE
@export var power: float = 1.0
@export var duration: float = 0.0
@export var cooldown: float = 0.3
@export var lifetime: float = 6.0
@export var max_bounces: int = 0
@export_enum("Bump", "Spin Out", "Tumble", "Squash") var hit_type: int = 0
@export var ai_use_profile: AIItemUseProfile
