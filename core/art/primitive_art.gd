class_name PrimitiveArt
extends RefCounted

const METALLIC: float = 0.28
const ROUGHNESS: float = 0.38

## Creates the shared visual material palette.
static func material(color: Color, emission: bool = false) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = METALLIC
	result.roughness = ROUGHNESS
	result.emission_enabled = emission
	result.emission = color
	return result

## Adds a visual-only accessory.
static func add_box(parent: Node3D, size: Vector3, at: Vector3, paint: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = paint
	parent.add_child(node)
	return node
