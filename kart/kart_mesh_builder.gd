class_name KartMeshBuilder
extends RefCounted

## Original low-poly body meshes, shared by catalogue id; no physics shapes.
const BEVEL: float = 0.18
const BODY_SIZES: Array[Vector3] = [Vector3(1.35, 0.34, 2.3), Vector3(1.6, 0.5, 2.2), Vector3(1.8, 0.65, 2.35)]
const VARIANT_WIDTH: float = 0.91
const VARIANT_LENGTH: float = 1.08
static var _meshes: Dictionary[StringName, ArrayMesh] = {}

## Hub cap radius as a fraction of the rim radius set in decorate().
const HUB_CAP_RADIUS: float = 0.085
const HUB_CAP_HEIGHT: float = 0.28
## Headlight placement, mirrored left/right at the nose (-z).
const HEADLIGHT_SIZE: Vector3 = Vector3(0.22, 0.12, 0.08)
const HEADLIGHT_X: float = 0.52
const HEADLIGHT_Y: float = -0.02
const HEADLIGHT_Z: float = -1.14
const HEADLIGHT_COLOR: Color = Color(1.0, 0.96, 0.78)
## Exhaust pipe geometry, matches effects/boost_effects.tscn Exhaust position (0, -0.05, 1.15).
const EXHAUST_PIPE_RADIUS: float = 0.09
const EXHAUST_PIPE_LENGTH: float = 0.3
const EXHAUST_PIPE_POSITION: Vector3 = Vector3(0.0, -0.05, 1.1)
## Helmet visor placement relative to the driver head sphere (radius 0.34, y 0.4).
const VISOR_SIZE: Vector3 = Vector3(0.42, 0.16, 0.1)
const VISOR_POSITION: Vector3 = Vector3(0.0, 0.42, -0.24)
## Prefix tagging driver-paint decal children so they can be replaced on driver change.
const PAINT_DECAL_PREFIX: String = "PaintDecal"
const PAINT_PATTERN_COUNT: int = 3

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
## `night_theme` gates headlight emission (Phase 17b item 3).
static func decorate(visuals: Node3D, data: KartData, night_theme: bool = false) -> void:
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
	_add_headlights(body, night_theme)
	_add_exhaust_pipe(body, accent)
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
		_add_wheel_hub(node, data.body_color)
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
	_add_helmet_visor(driver)
	_disable_detail_shadows(body)
	_disable_detail_shadows(driver, head)
	for wheel_name: String in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		_disable_detail_shadows(visuals.get_node(wheel_name))


## Small accessories are invisible in shadow maps but each one costs a draw per shadow cascade
## (4 on the high tier), which is what doubled kart draw calls in Phase 17b. Only the chassis
## (the Body mesh itself) and the helmet (`keep`) keep casting shadows.
static func _disable_detail_shadows(parent: Node, keep: Node = null) -> void:
	for child: Node in parent.find_children("*", "MeshInstance3D", true, false):
		if child != keep:
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Emissive nose lamps; only lit (emission enabled) on night-themed tracks.
## Always present as geometry so day tracks still show unlit lamp housings.
static func _add_headlights(body: MeshInstance3D, night_theme: bool) -> void:
	var lamp_material: StandardMaterial3D = PrimitiveArt.material(HEADLIGHT_COLOR, night_theme)
	if night_theme:
		lamp_material.emission_energy_multiplier = 2.0
	for side: float in [-1.0, 1.0]:
		PrimitiveArt.add_box(
			body,
			HEADLIGHT_SIZE,
			Vector3(HEADLIGHT_X * side, HEADLIGHT_Y, HEADLIGHT_Z),
			lamp_material,
		)


## Dark metal tailpipe at the rear, aligned with the BoostEffects exhaust particles.
static func _add_exhaust_pipe(body: MeshInstance3D, accent: StandardMaterial3D) -> void:
	var pipe: CylinderMesh = CylinderMesh.new()
	pipe.top_radius = EXHAUST_PIPE_RADIUS
	pipe.bottom_radius = EXHAUST_PIPE_RADIUS
	pipe.height = EXHAUST_PIPE_LENGTH
	pipe.radial_segments = 10
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = pipe
	node.rotation.x = PI * 0.5
	node.position = EXHAUST_PIPE_POSITION
	node.material_override = PrimitiveArt.material(accent.albedo_color.darkened(0.6))
	body.add_child(node)


## Small contrasting hub cap centered on an already-built wheel rim node.
static func _add_wheel_hub(rim_node: MeshInstance3D, body_color: Color) -> void:
	var cap: CylinderMesh = CylinderMesh.new()
	cap.top_radius = HUB_CAP_RADIUS
	cap.bottom_radius = HUB_CAP_RADIUS
	cap.height = HUB_CAP_HEIGHT
	cap.radial_segments = 8
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = cap
	node.material_override = PrimitiveArt.material(body_color.lightened(0.6))
	rim_node.add_child(node)


## Glossy visor strip on the driver's helmet (high metallic, low roughness).
static func _add_helmet_visor(driver: Node3D) -> void:
	var visor: StandardMaterial3D = StandardMaterial3D.new()
	visor.albedo_color = Color(0.05, 0.08, 0.12)
	visor.metallic = 0.95
	visor.roughness = 0.05
	PrimitiveArt.add_box(driver, VISOR_SIZE, VISOR_POSITION, visor)


## Replaces any existing driver-paint decals with a pattern chosen deterministically
## from the driver id: 0 stripe, 1 checker, 2 gradient (Phase 17b item 3).
static func apply_paint_pattern(body: MeshInstance3D, driver: DriverData) -> void:
	for child: Node in body.get_children():
		if String(child.name).begins_with(PAINT_DECAL_PREFIX):
			child.queue_free()
	if driver == null:
		return
	var pattern: int = int(hash(driver.id)) % PAINT_PATTERN_COUNT
	if pattern < 0:
		pattern += PAINT_PATTERN_COUNT
	match pattern:
		0:
			_paint_stripe(body, driver.driver_color)
		1:
			_paint_checker(body, driver.driver_color)
		_:
			_paint_gradient(body, driver.driver_color)


static func _paint_stripe(body: MeshInstance3D, paint: Color) -> void:
	_tag_decal(PrimitiveArt.add_box(body, Vector3(0.28, 0.1, 1.9), Vector3(0, 0.32, 0), PrimitiveArt.material(paint)), 0)


static func _paint_checker(body: MeshInstance3D, paint: Color) -> void:
	const SQUARES: int = 6
	for index: int in range(SQUARES):
		var color: Color = paint if index % 2 == 0 else Color.WHITE
		var offset_z: float = -0.9 + (1.8 * float(index) / float(SQUARES - 1))
		_tag_decal(PrimitiveArt.add_box(body, Vector3(0.55, 0.09, 0.28), Vector3(0, 0.32, offset_z), PrimitiveArt.material(color)), index)


static func _paint_gradient(body: MeshInstance3D, paint: Color) -> void:
	const BANDS: int = 5
	for index: int in range(BANDS):
		var ratio: float = float(index) / float(BANDS - 1)
		var color: Color = paint.lerp(Color.WHITE, ratio)
		var offset_z: float = -0.9 + (1.8 * ratio)
		_tag_decal(PrimitiveArt.add_box(body, Vector3(1.7, 0.08, 0.36), Vector3(0, 0.31, offset_z), PrimitiveArt.material(color)), index)


static func _tag_decal(node: MeshInstance3D, index: int) -> void:
	node.name = "%s%d" % [PAINT_DECAL_PREFIX, index]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
