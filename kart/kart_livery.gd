class_name KartLivery
extends RefCounted

## Presentation-only per-driver identity: body paint, accent, race number,
## face and the materials that carry them (car-paint body shader, helmet,
## suit, face shader, rims, number plate). Physics and gameplay never read it.

const PAINT_SHADER: Shader = preload("res://effects/hit_flash.gdshader")
const NUMBER_NODE_NAME: String = "RaceNumber"
const HELMET_NODE_NAME: String = "Helmet"
const HELMET_STRIPE_NODE_NAME: String = "HelmetStripe"
const RIM_SURFACE: int = 1
const PATTERN_COUNT: int = 3
const FALLBACK_ACCENT: Color = Color(0.96, 0.96, 0.98)
## Number plate on the rear deck, facing the chase camera (kart-local, body space).
const NUMBER_POSITION: Vector3 = Vector3(0.0, 0.2, 0.74)
const NUMBER_TILT_DEGREES: float = -62.0
const NUMBER_PIXEL_SIZE: float = 0.0036
const NUMBER_FONT_SIZE: int = 72
const NUMBER_OUTLINE_SIZE: int = 18

var paint: Color = Color.WHITE
var accent: Color = FALLBACK_ACCENT
var helmet: Color = Color.WHITE
var number: int = 0
var pattern: int = 0
var skin: Color = Color(0.96, 0.78, 0.64)
var eyes: Color = Color(0.28, 0.48, 0.9)
var hair: Color = Color(0.32, 0.2, 0.12)
var expression: int = 0
var blink_offset: float = 0.0


## Resolves a stable livery; a null driver falls back to the kart's own colour.
static func resolve(driver: DriverData, kart: KartData = null) -> KartLivery:
	var livery: KartLivery = KartLivery.new()
	var fallback: Color = kart.body_color if kart != null else Color(0.9, 0.2, 0.15)
	if driver == null:
		livery.paint = fallback
		livery.helmet = fallback.lightened(0.3)
		return livery
	livery.paint = driver.livery_primary if driver.livery_primary.a > 0.0 else driver.driver_color
	livery.accent = driver.livery_accent
	livery.helmet = driver.driver_color
	livery.number = driver.race_number
	livery.pattern = pattern_for(driver)
	livery.skin = driver.skin_tone
	livery.eyes = driver.eye_color
	livery.hair = driver.hair_color
	livery.expression = driver.face_expression
	livery.blink_offset = float(posmod(int(hash(driver.id)), 1000)) * 0.0037
	return livery


## Deterministic livery pattern index from the driver id (0 stripe, 1 two-tone, 2 nose).
static func pattern_for(driver: DriverData) -> int:
	if driver == null:
		return 0
	return posmod(int(hash(driver.id)), PATTERN_COUNT)


## Body shader material: reuses the body's current paint material when present
## so the hit-flash reference held by KartVisuals stays valid across driver swaps.
func apply_body(body: MeshInstance3D) -> ShaderMaterial:
	var material: ShaderMaterial = body.material_override as ShaderMaterial
	if material == null or material.shader != PAINT_SHADER:
		material = ShaderMaterial.new()
		material.shader = PAINT_SHADER
		body.material_override = material
	material.set_shader_parameter("albedo_color", paint)
	material.set_shader_parameter("accent_color", accent)
	material.set_shader_parameter("livery_pattern", pattern)
	var has_roles: bool = body.mesh != null and body.mesh.get_meta(&"vertex_roles", false)
	material.set_shader_parameter("use_vertex_roles", has_roles)
	if body.mesh != null:
		var bounds: AABB = body.mesh.get_aabb()
		material.set_shader_parameter("body_min", bounds.position)
		material.set_shader_parameter("body_size", bounds.size)
	_apply_number(body)
	return material


## Driver wears the driver colour: matte suit (vertex COLOR darkens gloves and
## the steering wheel), clearcoated helmet with an accent rim, and the face.
func apply_driver(driver_node: MeshInstance3D) -> void:
	if driver_node == null:
		return
	var suit: StandardMaterial3D = _soft(_glossy(helmet, 0.75, 0.0))
	suit.vertex_color_use_as_albedo = true
	driver_node.material_override = suit
	_apply_face(driver_node.get_node_or_null(KartDriverBuilder.HEAD_NODE_NAME) as MeshInstance3D)
	var helmet_node: MeshInstance3D = driver_node.get_node_or_null(HELMET_NODE_NAME) as MeshInstance3D
	if helmet_node != null:
		var shell: StandardMaterial3D = _soft(_glossy(helmet, 0.22, 0.15))
		shell.clearcoat_enabled = true
		shell.clearcoat = 1.0
		shell.clearcoat_roughness = 0.1
		shell.rim_enabled = true
		shell.rim = 0.35
		helmet_node.material_override = shell
		var stripe: MeshInstance3D = helmet_node.get_node_or_null(HELMET_STRIPE_NODE_NAME) as MeshInstance3D
		if stripe != null:
			stripe.material_override = _soft(_glossy(accent, 0.3, 0.1))


## Accent-tinted metallic rims on each wheel mesh.
func apply_wheels(wheels: Array[MeshInstance3D]) -> void:
	var rim: StandardMaterial3D = _glossy(accent.lerp(Color(0.8, 0.82, 0.85), 0.3), 0.28, 0.75)
	for wheel: MeshInstance3D in wheels:
		if wheel.mesh != null and wheel.mesh.get_surface_count() > RIM_SURFACE:
			wheel.set_surface_override_material(RIM_SURFACE, rim)


func _apply_number(body: MeshInstance3D) -> void:
	var label: Label3D = body.get_node_or_null(NUMBER_NODE_NAME) as Label3D
	if number <= 0:
		if label != null:
			body.remove_child(label)
			label.queue_free()
		return
	if label == null:
		label = Label3D.new()
		label.name = NUMBER_NODE_NAME
		label.pixel_size = NUMBER_PIXEL_SIZE
		label.font_size = NUMBER_FONT_SIZE
		label.outline_size = NUMBER_OUTLINE_SIZE
		label.double_sided = false
		label.shaded = false
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.rotation_degrees = Vector3(NUMBER_TILT_DEGREES, 0.0, 0.0)
		body.add_child(label)
	var anchor: Variant = body.mesh.get_meta(&"number_anchor", null) if body.mesh != null else null
	if anchor is Transform3D:
		label.transform = anchor as Transform3D
	else:
		label.position = NUMBER_POSITION + Vector3(0.0, -body.position.y, 0.0)
	label.text = str(number)
	var dark_paint: bool = paint.get_luminance() < 0.45
	label.modulate = Color.WHITE if dark_paint else Color(0.06, 0.06, 0.08)
	label.outline_modulate = accent if dark_paint else Color.WHITE


func _apply_face(head: MeshInstance3D) -> void:
	if head == null:
		return
	var face: ShaderMaterial = head.material_override as ShaderMaterial
	if face == null:
		return
	face.set_shader_parameter("skin_tone", skin)
	face.set_shader_parameter("eye_color", eyes)
	face.set_shader_parameter("hair_color", hair)
	face.set_shader_parameter("expression", expression)
	face.set_shader_parameter("blink_offset", blink_offset)


## Driver parts skip receiving shadows: on small rounded meshes the shadow map
## only draws blocky, faceted terminator bands (the chassis still receives).
static func _soft(material: StandardMaterial3D) -> StandardMaterial3D:
	material.disable_receive_shadows = true
	return material


static func _glossy(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
