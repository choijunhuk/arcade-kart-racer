class_name OffroadZone
extends Area3D

## Declares an overlapping terrain override. TerrainSensor reads this resource;
## the zone itself never changes kart physics.

@export var terrain: TerrainData = preload("res://data/terrain/grass.tres")

@onready var _surface: MeshInstance3D = $Surface


func _ready() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = terrain.particle_color
	material.roughness = 1.0
	_surface.material_override = material
