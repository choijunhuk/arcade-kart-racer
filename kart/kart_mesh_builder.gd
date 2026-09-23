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
const HEADLIGHT_SIZE: Vector3 = Vector3(0.16, 0.06, 0.06)
const HEADLIGHT_X: float = 0.42
const HEADLIGHT_Y: float = -0.19
const HEADLIGHT_Z: float = -1.02
const HEADLIGHT_COLOR: Color = Color(1.0, 0.96, 0.78)
## Exhaust pipe geometry, matches effects/boost_effects.tscn Exhaust position (0, -0.05, 1.15).
const EXHAUST_PIPE_RADIUS: float = 0.075
const EXHAUST_PIPE_LENGTH: float = 0.2
const EXHAUST_PIPE_POSITION: Vector3 = Vector3(0.0, -0.1, 1.05)
## Driver figure (driver-local units): suit torso, helmet shell, accent
## stripe and a wrap-around visor facing the kart's nose (-Z).
const TORSO_RADIUS: float = 0.21
const TORSO_HEIGHT: float = 0.56
const HELMET_RADIUS: float = 0.25
const HELMET_Y: float = 0.4
const HELMET_STRIPE_SCALE: Vector3 = Vector3(0.26, 1.03, 1.03)
const VISOR_SCALE: Vector3 = Vector3(0.94, 0.52, 0.78)
const VISOR_OFFSET: Vector3 = Vector3(0.0, 0.01, -0.08)
## Prefix tagging legacy driver-paint decal children so they are removed on driver change.
const PAINT_DECAL_PREFIX: String = "PaintDecal"
## Driver placement: matches kart.tscn/kart_preview.gd's authored offset for
## the boxy procedural chassis. The Kenney chassis' cockpit sits lower and
## more open, so its driver is nestled down and shrunk to match.
const PROCEDURAL_DRIVER_POSITION: Vector3 = Vector3(0.0, 0.55, 0.15)
const KENNEY_DRIVER_POSITION: Vector3 = Vector3(0.0, 0.1, 0.12)
const KENNEY_DRIVER_SCALE: float = 0.7

## Visual target footprint for a kart (BODY_SIZES, scaled for named "_"
## variants). Shared by the procedural chassis() and the Kenney art path
## (KartKenneyArt.build_body_mesh) so both fit the same silhouette per class.
static func target_body_size(data: KartData) -> Vector3:
	var size: Vector3 = BODY_SIZES[data.weight_class]
	if String(data.id).contains("_"):
		size *= Vector3(VARIANT_WIDTH, VARIANT_LENGTH, VARIANT_LENGTH)
	return size


## Builds a bevelled eight-sided chassis with class-specific nose height.
static func chassis(data: KartData) -> ArrayMesh:
	if _meshes.has(data.id):
		return _meshes[data.id]
	var size: Vector3 = target_body_size(data)
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
## Visual style is picked by the `video.art_style` setting ("kenney" CC0 race
## car meshes, default; "procedural" keeps the original low-poly chassis).
## Kenney assets that fail to load fall back to the procedural chassis.
static func decorate(visuals: Node3D, data: KartData, night_theme: bool = false) -> void:
	var body: MeshInstance3D = visuals.get_node("Body") as MeshInstance3D
	var use_kenney: bool = String(SettingsManager.get_setting(&"video", &"art_style", "kenney")) == "kenney"
	var kenney_body: ArrayMesh = KartKenneyArt.build_body_mesh(data) if use_kenney else null
	var accent: StandardMaterial3D = PrimitiveArt.material(data.body_color.lightened(0.35))
	if kenney_body != null:
		body.mesh = kenney_body
		body.position.y = KartKenneyArt.GROUND_CONTACT_Y
	else:
		body.mesh = chassis(data)
		body.position.y = 0.0
		PrimitiveArt.add_box(body, Vector3(1.65, 0.12, 0.18), Vector3(0, -0.12, -1.1), PrimitiveArt.material(Color(0.1, 0.12, 0.16)))
		PrimitiveArt.add_box(body, Vector3(0.15, 0.08, 1.7), Vector3(0, 0.3, 0), accent)
		if data.weight_class == KartData.WeightClass.HEAVY:
			PrimitiveArt.add_box(body, Vector3(1.9, 0.12, 0.45), Vector3(0, 0.65, 0.9), accent)
			PrimitiveArt.add_box(body, Vector3(0.15, 0.5, 0.15), Vector3(0, 0.4, 0.9), accent)
		elif data.weight_class == KartData.WeightClass.LIGHT:
			PrimitiveArt.add_box(body, Vector3(0.55, 0.12, 0.8), Vector3(0, 0, -1.0), accent)
		else:
			PrimitiveArt.add_box(body, Vector3(1.75, 0.18, 0.65), Vector3(0, 0.05, 0.65), accent)
	# Headlights/exhaust are children of `body`, whose own local origin moved
	# (see body.position.y above) to ground the Kenney mesh; compensate so
	# both land at the same absolute height/alignment as in procedural mode
	# (the exhaust in particular must still line up with the fixed BoostEffects
	# particle emitter, which is positioned in Kart-local space).
	var accessory_y_offset: float = -body.position.y
	_add_headlights(body, night_theme, accessory_y_offset)
	_add_exhaust_pipe(body, accessory_y_offset)
	for wheel_name: String in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var pivot: Node3D = visuals.get_node(wheel_name) as Node3D
		var kenney_wheel: ArrayMesh = KartKenneyArt.build_wheel_mesh(StringName(wheel_name)) if kenney_body != null else null
		if kenney_wheel != null:
			var layout: Dictionary = KartKenneyArt.wheel_layout(data)
			if layout.has(StringName(wheel_name)):
				var ground_xz: Vector2 = layout[StringName(wheel_name)] as Vector2
				pivot.position = Vector3(ground_xz.x, KartKenneyArt.GROUND_CONTACT_Y + KartKenneyArt.WHEEL_VISUAL_RADIUS, ground_xz.y)
			var placeholder: Node = pivot.get_node_or_null("Mesh")
			if placeholder is MeshInstance3D:
				(placeholder as MeshInstance3D).visible = false
			var node: MeshInstance3D = MeshInstance3D.new()
			node.name = "WheelMesh"
			node.mesh = kenney_wheel
			pivot.add_child(node)
			continue
		var rim: CylinderMesh = CylinderMesh.new()
		rim.top_radius = 0.17
		rim.bottom_radius = 0.17
		rim.height = 0.26
		rim.radial_segments = 12
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = rim
		node.rotation.z = PI * 0.5
		node.material_override = accent
		pivot.add_child(node)
		_add_wheel_hub(node, data.body_color)
	var driver: MeshInstance3D = visuals.get_node("Driver") as MeshInstance3D
	if kenney_body != null:
		# The Kenney chassis' cockpit sits lower than the boxy procedural one;
		# nestle the driver down into it instead of perching on top.
		driver.position = KENNEY_DRIVER_POSITION
		driver.scale = Vector3.ONE * KENNEY_DRIVER_SCALE
	else:
		driver.position = PROCEDURAL_DRIVER_POSITION
		driver.scale = Vector3.ONE
	var head: MeshInstance3D = _build_driver(driver)
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
static func _add_headlights(body: MeshInstance3D, night_theme: bool, y_offset: float = 0.0) -> void:
	var lamp_material: StandardMaterial3D = PrimitiveArt.material(HEADLIGHT_COLOR, night_theme)
	if night_theme:
		lamp_material.emission_energy_multiplier = 2.0
	for side: float in [-1.0, 1.0]:
		PrimitiveArt.add_box(
			body,
			HEADLIGHT_SIZE,
			Vector3(HEADLIGHT_X * side, HEADLIGHT_Y + y_offset, HEADLIGHT_Z),
			lamp_material,
		)


## Dark metal tailpipe at the rear, aligned with the BoostEffects exhaust particles.
static func _add_exhaust_pipe(body: MeshInstance3D, y_offset: float = 0.0) -> void:
	var pipe: CylinderMesh = CylinderMesh.new()
	pipe.top_radius = EXHAUST_PIPE_RADIUS
	pipe.bottom_radius = EXHAUST_PIPE_RADIUS
	pipe.height = EXHAUST_PIPE_LENGTH
	pipe.radial_segments = 10
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = pipe
	node.rotation.x = PI * 0.5
	node.position = EXHAUST_PIPE_POSITION + Vector3(0.0, y_offset, 0.0)
	node.material_override = _gunmetal()
	body.add_child(node)


static func _gunmetal() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.13, 0.15)
	material.metallic = 0.85
	material.roughness = 0.35
	return material


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


## Replaces the driver placeholder with suit torso + helmet (shell, accent
## stripe, glossy visor). Colours come from KartLivery.apply_driver().
static func _build_driver(driver: MeshInstance3D) -> MeshInstance3D:
	for child: Node in driver.get_children():
		driver.remove_child(child)
		child.queue_free()
	var torso: CapsuleMesh = CapsuleMesh.new()
	torso.radius = TORSO_RADIUS
	torso.height = TORSO_HEIGHT
	torso.radial_segments = 12
	torso.rings = 4
	driver.mesh = torso
	var helmet: MeshInstance3D = _sphere(driver, KartLivery.HELMET_NODE_NAME, HELMET_RADIUS, Vector3(0.0, HELMET_Y, 0.0))
	var stripe: MeshInstance3D = _sphere(helmet, KartLivery.HELMET_STRIPE_NODE_NAME, HELMET_RADIUS, Vector3.ZERO)
	stripe.scale = HELMET_STRIPE_SCALE
	var visor: MeshInstance3D = _sphere(helmet, "Visor", HELMET_RADIUS, VISOR_OFFSET)
	visor.scale = VISOR_SCALE
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.05, 0.09)
	glass.metallic = 0.9
	glass.roughness = 0.06
	glass.rim_enabled = true
	glass.rim = 0.6
	visor.material_override = glass
	return helmet


static func _sphere(parent: Node3D, node_name: String, radius: float, at: Vector3) -> MeshInstance3D:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = sphere
	node.position = at
	parent.add_child(node)
	return node


## Applies the driver's livery (body paint shader + race number; helmet, suit
## and rims when the body sits in a full Visuals rig). The pattern index is
## deterministic per driver id (KartLivery.pattern_for). A null driver only
## clears legacy decals so callers can keep the kart's default paint.
static func apply_paint_pattern(body: MeshInstance3D, driver: DriverData, kart: KartData = null) -> void:
	for child: Node in body.get_children():
		if String(child.name).begins_with(PAINT_DECAL_PREFIX):
			body.remove_child(child)
			child.queue_free()
	if driver == null and kart == null:
		return
	var livery: KartLivery = KartLivery.resolve(driver, kart)
	livery.apply_body(body)
	var rig: Node = body.get_parent()
	if rig == null:
		return
	livery.apply_driver(rig.get_node_or_null("Driver") as MeshInstance3D)
	var wheels: Array[MeshInstance3D] = []
	for wheel_name: String in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var wheel_mesh: MeshInstance3D = rig.get_node_or_null("%s/WheelMesh" % wheel_name) as MeshInstance3D
		if wheel_mesh != null:
			wheels.append(wheel_mesh)
	livery.apply_wheels(wheels)
