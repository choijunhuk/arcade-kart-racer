class_name JumpPad
extends Area3D

@export var launch_velocity: Vector3 = Vector3(0.0, 9.0, -18.0)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: Vector3 in [Vector3(-3, 0, 2), Vector3(-3, 0.8, -2), Vector3(3, 0.8, -2), Vector3(-3, 0, 2), Vector3(3, 0.8, -2), Vector3(3, 0, 2)]:
		surface.add_vertex(vertex)
	surface.generate_normals()
	($LaunchArrow as MeshInstance3D).mesh = surface.commit()
	($LaunchArrow as MeshInstance3D).material_override = PrimitiveArt.material(Color(1, 0.4, 0.05), true)


func _on_body_entered(body: Node3D) -> void:
	if body is KartController:
		(body as KartController).launch(launch_velocity)
