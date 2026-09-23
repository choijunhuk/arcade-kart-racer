class_name KartMeshBuilder
extends RefCounted

## Installs the soft, toy-like kart art (KartSoftBody body + wheels,
## KartDriverBuilder driver with a painted face) into a Visuals rig. Shared by
## real karts (KartVisuals) and the menu KartPreview; no physics shapes.
const BODY_SIZES: Array[Vector3] = [Vector3(1.35, 0.34, 2.3), Vector3(1.6, 0.5, 2.2), Vector3(1.8, 0.65, 2.35)]
const VARIANT_WIDTH: float = 0.91
const VARIANT_LENGTH: float = 1.08
const WHEEL_NAMES: Array[StringName] = [&"WheelFL", &"WheelFR", &"WheelRL", &"WheelRR"]

## Domed nose lamps, mirrored left/right (x as a fraction of the tub width).
const HEADLIGHT_HALF: Vector2 = Vector2(0.065, 0.045)
const HEADLIGHT_X: float = 0.5
const HEADLIGHT_COLOR: Color = Color(1.0, 0.96, 0.78)
## Exhaust pipe geometry, matches effects/boost_effects.tscn Exhaust position (0, -0.05, 1.15).
const EXHAUST_PIPE_RADIUS: float = 0.07
const EXHAUST_PIPE_LENGTH: float = 0.2
const EXHAUST_PIPE_POSITION: Vector3 = Vector3(0.0, -0.1, 1.05)
## Prefix tagging legacy driver-paint decal children so they are removed on driver change.
const PAINT_DECAL_PREFIX: String = "PaintDecal"

static var _lamp_mesh: ArrayMesh
static var _pipe_mesh: ArrayMesh


## Visual target footprint for a kart (BODY_SIZES, scaled for named "_"
## variants); the soft body is modelled to fit it per class.
static func target_body_size(data: KartData) -> Vector3:
	var size: Vector3 = BODY_SIZES[data.weight_class]
	if String(data.id).contains("_"):
		size *= Vector3(VARIANT_WIDTH, VARIANT_LENGTH, VARIANT_LENGTH)
	return size


## The kart's single-surface soft body (cached per kart id).
static func chassis(data: KartData) -> ArrayMesh:
	return KartSoftBody.body_mesh(data)


## Installs body, wheels and driver under the existing animated pivots.
## `night_theme` gates headlight emission (Phase 17b item 3). The kart's own
## default livery is applied so previews without a driver are still painted.
static func decorate(visuals: Node3D, data: KartData, night_theme: bool = false) -> void:
	var body: MeshInstance3D = visuals.get_node("Body") as MeshInstance3D
	var shape: KartSoftBody.Shape = KartSoftBody.shape(data)
	body.mesh = chassis(data)
	body.position = Vector3.ZERO
	_add_headlights(body, night_theme, shape)
	_add_exhaust_pipe(body)
	var positions: Dictionary[StringName, Vector3] = KartSoftBody.wheel_positions(shape)
	for wheel_name: StringName in WHEEL_NAMES:
		var pivot: Node3D = visuals.get_node(String(wheel_name)) as Node3D
		pivot.position = positions[wheel_name]
		var placeholder: MeshInstance3D = pivot.get_node_or_null("Mesh") as MeshInstance3D
		if placeholder != null:
			placeholder.visible = false
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "WheelMesh"
		node.mesh = KartSoftBody.wheel_mesh(String(wheel_name).contains("F"), signf(pivot.position.x), shape)
		pivot.add_child(node)
	var driver: MeshInstance3D = visuals.get_node("Driver") as MeshInstance3D
	driver.position = shape.seat
	driver.scale = Vector3.ONE * shape.driver_scale
	var helmet: MeshInstance3D = KartDriverBuilder.build(driver)
	apply_paint_pattern(body, null, data)
	_disable_detail_shadows(body)
	_disable_detail_shadows(driver, helmet)
	for wheel_name: StringName in WHEEL_NAMES:
		_disable_detail_shadows(visuals.get_node(String(wheel_name)))


## Triangles of one fully decorated kart (body, 4 wheels, driver).
static func triangle_count(data: KartData) -> int:
	var shape: KartSoftBody.Shape = KartSoftBody.shape(data)
	var total: int = int(chassis(data).get_meta(&"triangles", 0)) + KartDriverBuilder.triangle_count()
	for front: bool in [true, false]:
		total += 2 * int(KartSoftBody.wheel_mesh(front, 1.0, shape).get_meta(&"triangles", 0))
	return total


## Small accessories are invisible in shadow maps but each one costs a draw per shadow cascade
## (4 on the high tier), which is what doubled kart draw calls in Phase 17b. Only the chassis
## (the Body mesh itself) and the helmet (`keep`) keep casting shadows.
static func _disable_detail_shadows(parent: Node, keep: Node = null) -> void:
	for child: Node in parent.find_children("*", "MeshInstance3D", true, false):
		if child != keep:
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Emissive nose lamps; only lit (emission enabled) on night-themed tracks.
## Always present as geometry so day tracks still show unlit lamp lenses.
static func _add_headlights(body: MeshInstance3D, night_theme: bool, shape: KartSoftBody.Shape) -> void:
	var lamp_material: StandardMaterial3D = PrimitiveArt.material(HEADLIGHT_COLOR, night_theme)
	lamp_material.roughness = 0.15
	if night_theme:
		lamp_material.emission_energy_multiplier = 2.0
	var z: float = -shape.size.z * 0.4
	var y: float = shape.floor_y + shape.size.y * 0.36
	for side: float in [-1.0, 1.0]:
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = _lamp()
		node.position = Vector3(side * shape.tub_half * HEADLIGHT_X, y, z)
		node.rotation.x = deg_to_rad(-12.0)
		node.material_override = lamp_material
		body.add_child(node)


## Dark metal tailpipe with a rolled lip, aligned with the BoostEffects exhaust particles.
static func _add_exhaust_pipe(body: MeshInstance3D) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = _pipe()
	node.position = EXHAUST_PIPE_POSITION
	node.material_override = _gunmetal()
	body.add_child(node)


## Shallow domed lens facing -Z.
static func _lamp() -> ArrayMesh:
	if _lamp_mesh == null:
		var mesh: SoftMesh = SoftMesh.new()
		mesh.dome_rings = 2
		mesh.sweep(PackedVector3Array([Vector3(0, 0, 0.02), Vector3(0, 0, -0.005)]), PackedVector2Array([HEADLIGHT_HALF, HEADLIGHT_HALF]), Color.WHITE, 10, 2.4, Vector3.UP, false, 0.5)
		_lamp_mesh = mesh.commit()
	return _lamp_mesh


## Pipe along +Z centred on its origin, flaring into a rounded lip at the tip.
static func _pipe() -> ArrayMesh:
	if _pipe_mesh == null:
		var half: float = EXHAUST_PIPE_LENGTH * 0.5
		var r: float = EXHAUST_PIPE_RADIUS
		var mesh: SoftMesh = SoftMesh.new()
		mesh.dome_rings = 2
		var path: PackedVector3Array = PackedVector3Array([Vector3(0, 0, -half), Vector3(0, 0, half * 0.6), Vector3(0, 0, half)])
		mesh.sweep(path, PackedVector2Array([Vector2.ONE * r * 0.85, Vector2.ONE * r * 0.85, Vector2.ONE * r]), Color.WHITE, 10, 2.0, Vector3.UP, false, 0.4)
		_pipe_mesh = mesh.commit()
	return _pipe_mesh


static func _gunmetal() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.13, 0.15)
	material.metallic = 0.85
	material.roughness = 0.35
	return material


## Applies the driver's livery (body paint shader + race number; helmet, suit,
## face and rims when the body sits in a full Visuals rig). The pattern index
## is deterministic per driver id (KartLivery.pattern_for). A null driver and
## kart only clears legacy decals so callers can keep the default paint.
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
	for wheel_name: StringName in WHEEL_NAMES:
		var wheel_mesh: MeshInstance3D = rig.get_node_or_null("%s/WheelMesh" % wheel_name) as MeshInstance3D
		if wheel_mesh != null:
			wheels.append(wheel_mesh)
	livery.apply_wheels(wheels)
