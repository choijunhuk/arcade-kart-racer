class_name DriverData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var portrait: Texture2D
@export var mesh_scene: PackedScene
@export var stat_mods: Dictionary[StringName, float] = {}
@export var voice_set: StringName = &""
