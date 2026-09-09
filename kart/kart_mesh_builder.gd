class_name KartMeshBuilder
extends RefCounted

## Original low-poly body meshes, shared by catalogue id; no physics shapes.
const BEVEL: float = 0.18
const BODY_SIZES: Array[Vector3] = [Vector3(1.35, 0.34, 2.3), Vector3(1.6, 0.5, 2.2), Vector3(1.8, 0.65, 2.35)]
const VARIANT_WIDTH: float = 0.91
const VARIANT_LENGTH: float = 1.08
static var _meshes: Dictionary[StringName, ArrayMesh] = {}

## Builds a bevelled eight-sided chassis with class-specific nose height.
static func chassis(data: KartData) -> ArrayMesh:
	if _meshes.has(data.id):
		return _meshes[data.id]
	var size: Vector3 = BODY_SIZES[data.weight_class]
	if String(data.id).contains("_"):
		size *= Vector3(VARIANT_WIDTH, VARIANT_LENGTH, VARIANT_LENGTH)
	var outline: Array[Vector2] = [Vector2(-1, -1 + BEVEL), Vector2(-1 + BEVEL, -1), Vector2(1 - BEVEL, -1), Vector2(1, -1 + BEVEL), Vector2(1, 1 - BEVEL), Vector2(1 - BEVEL, 1), Vector2(-1 + BEVEL, 1), Vector2(-1, 1 - BEVEL)]
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(PrimitiveArt.material(data.body_color))
	for index: int in range(outline.size()):
		var a: Vector2 = outline[index] * Vector2(size.x, size.z) * 0.5
		var b: Vector2 = outline[(index + 1) % outline.size()] * Vector2(size.x, size.z) * 0.5
		var low_a: Vector3 = Vector3(a.x, -size.y * 0.5, a.y)
		var low_b: Vector3 = Vector3(b.x, -size.y * 0.5, b.y)
		var top_a: Vector3 = Vector3(a.x * (1.0 - BEVEL), size.y * 0.5, a.y * (1.0 - BEVEL))
		var top_b: Vector3 = Vector3(b.x * (1.0 - BEVEL), size.y * 0.5, b.y * (1.0 - BEVEL))
		for vertex: Vector3 in [low_a, top_a, top_b, low_a, top_b, low_b, Vector3(0, size.y * 0.5, 0), top_b, top_a, Vector3(0, -size.y * 0.5, 0), low_a, low_b]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	_meshes[data.id] = surface.commit()
	return _meshes[data.id]

## Installs accessories under the existing animated body and wheel pivots.
static func decorate(visuals: Node3D, data: KartData) -> void:
	var body: MeshInstance3D = visuals.get_node("Body") as MeshInstance3D
	body.mesh = chassis(data)
	var accent: StandardMaterial3D = PrimitiveArt.material(data.body_color.lightened(0.35), true)
	PrimitiveArt.add_box(body, Vector3(1.65, 0.12, 0.18), Vector3(0, -0.12, -1.1), PrimitiveArt.material(Color(0.1, 0.12, 0.16)))
	PrimitiveArt.add_box(body, Vector3(0.15, 0.08, 1.7), Vector3(0, 0.3, 0), accent)
	if data.weight_class == KartData.WeightClass.HEAVY:
		PrimitiveArt.add_box(body, Vector3(1.9, 0.12, 0.45), Vector3(0, 0.65, 0.9), accent)
		PrimitiveArt.add_box(body, Vector3(0.15, 0.5, 0.15), Vector3(0, 0.4, 0.9), accent)
	elif data.weight_class == KartData.WeightClass.LIGHT:
		PrimitiveArt.add_box(body, Vector3(0.55, 0.12, 0.8), Vector3(0, 0, -1.0), accent)
	else:
		PrimitiveArt.add_box(body, Vector3(1.75, 0.18, 0.65), Vector3(0, 0.05, 0.65), accent)
	for wheel_name: String in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var rim: CylinderMesh = CylinderMesh.new()
		rim.top_radius = 0.17
		rim.bottom_radius = 0.17
		rim.height = 0.26
		rim.radial_segments = 12
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = rim
		node.rotation.z = PI * 0.5
		node.material_override = accent
		visuals.get_node(wheel_name).add_child(node)
	var driver: Node3D = visuals.get_node("Driver") as Node3D
	var helmet: SphereMesh = SphereMesh.new()
	helmet.radius = 0.34
	helmet.height = 0.55
	helmet.radial_segments = 12
	helmet.rings = 6
	var head: MeshInstance3D = MeshInstance3D.new()
	head.mesh = helmet
	head.position.y = 0.4
	head.material_override = accent
	driver.add_child(head)
	PrimitiveArt.add_box(driver, Vector3(0.5, 0.16, 0.15), Vector3(0, 0.43, -0.28), PrimitiveArt.material(Color(0.02, 0.06, 0.12)))
