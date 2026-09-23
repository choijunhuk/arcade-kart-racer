class_name KartDriverBuilder
extends RefCounted

## Soft chibi driver (Phase 19 kart-soft), in driver-local units with the hip
## point at the origin and the nose of the kart towards -Z:
## - the Driver node's own mesh: rounded torso, arms reaching to the steering
##   wheel, mitten gloves and the wheel itself (vertex COLOR tints the suit
##   material: white = suit colour, dark = gloves / wheel);
## - Head: skin head with the SDF face shader (kart/driver_face.gdshader);
## - Helmet: open-face shell framing the face, with a padded accent rim
##   (HelmetStripe) and goggles pushed up on the brow (Visor).
## Materials/colours per driver come from KartLivery.apply_driver().

const FACE_SHADER: Shader = preload("res://kart/driver_face.gdshader")
const HEAD_NODE_NAME: String = "Head"
const VISOR_NODE_NAME: String = "Visor"
const HEAD_RADIUS: float = 0.19
const HEAD_CENTER: Vector3 = Vector3(0.0, 0.5, -0.01)
const HELMET_RADIUS: float = 0.218
## Open-face cut: brow edge elevation in front, lower edge elsewhere, and the
## half-angle of the face opening around -Z (degrees).
const BROW_ELEVATION: float = 33.0
const SKIRT_ELEVATION: float = -40.0
const OPENING_HALF_ANGLE: float = 62.0
## Brow edge drops this much (degrees) towards the temples: an oval face opening.
const BROW_ARCH: float = 12.0
const GOGGLE_ELEVATION: float = 52.0
const HELMET_SEGMENTS: int = 30
const HELMET_BANDS: int = 7
const SUIT: Color = Color(1.0, 1.0, 1.0)
const GLOVE: Color = Color(0.2, 0.2, 0.22)
const WHEEL_TINT: Color = Color(0.1, 0.1, 0.11)
## Steering wheel centre and facing (towards the driver's chest).
const WHEEL_CENTER: Vector3 = Vector3(0.0, 0.2, -0.38)
const WHEEL_NORMAL: Vector3 = Vector3(0.0, 0.62, 0.78)
const WHEEL_RADIUS: float = 0.12

static var _body_mesh: ArrayMesh
static var _head_mesh: ArrayMesh
static var _helmet_meshes: Array[ArrayMesh] = []


## Rebuilds the driver under `driver` and returns the helmet node (the one
## driver part that keeps casting shadows).
static func build(driver: MeshInstance3D) -> MeshInstance3D:
	for child: Node in driver.get_children():
		driver.remove_child(child)
		child.queue_free()
	driver.mesh = _body()
	var head: MeshInstance3D = _child(driver, HEAD_NODE_NAME, _head(), HEAD_CENTER)
	var face: ShaderMaterial = ShaderMaterial.new()
	face.shader = FACE_SHADER
	face.set_shader_parameter("head_radius", HEAD_RADIUS)
	head.material_override = face
	var parts: Array[ArrayMesh] = _helmet()
	var helmet: MeshInstance3D = _child(driver, KartLivery.HELMET_NODE_NAME, parts[0], HEAD_CENTER)
	_child(helmet, KartLivery.HELMET_STRIPE_NODE_NAME, parts[1], Vector3.ZERO)
	var visor: MeshInstance3D = _child(helmet, VISOR_NODE_NAME, parts[2], Vector3.ZERO)
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.08, 0.12)
	glass.metallic = 0.6
	glass.roughness = 0.08
	glass.rim_enabled = true
	glass.rim = 0.6
	visor.material_override = glass
	return helmet


static func triangle_count() -> int:
	var total: int = 0
	for mesh: ArrayMesh in [_body(), _head()] + _helmet():
		total += int(mesh.get_meta(&"triangles", 0))
	return total


static func _child(parent: Node3D, node_name: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node


## Torso, arms, gloves and steering wheel in one surface.
static func _body() -> ArrayMesh:
	if _body_mesh != null:
		return _body_mesh
	var mesh: SoftMesh = SoftMesh.new()
	mesh.dome_rings = 2
	var torso: PackedVector3Array = PackedVector3Array([Vector3(0, -0.04, 0.03), Vector3(0, 0.1, 0.02), Vector3(0, 0.24, 0.0), Vector3(0, 0.31, -0.01)])
	var torso_sizes: PackedVector2Array = PackedVector2Array([Vector2(0.15, 0.12), Vector2(0.175, 0.125), Vector2(0.17, 0.11), Vector2(0.12, 0.085)])
	mesh.sweep(torso, torso_sizes, SUIT, 14, 2.4, Vector3.FORWARD, false, 0.7)
	var u: Vector3 = Vector3.RIGHT
	var n: Vector3 = WHEEL_NORMAL.normalized()
	var v: Vector3 = n.cross(u).normalized()
	for side: float in [-1.0, 1.0]:
		var hand: Vector3 = WHEEL_CENTER + (u * side * 0.94 + v * 0.3) * WHEEL_RADIUS + n * 0.03
		var shoulder: Vector3 = Vector3(side * 0.17, 0.25, 0.01)
		var elbow: Vector3 = Vector3(side * 0.23, 0.13, -0.14)
		var wrist: Vector3 = hand + (elbow - hand).normalized() * 0.07
		var arm: PackedVector3Array = PackedVector3Array(SoftMesh.smooth([shoulder, elbow, wrist], 2))
		var arm_sizes: PackedVector2Array = PackedVector2Array()
		for index: int in range(arm.size()):
			arm_sizes.append(Vector2.ONE * lerpf(0.058, 0.044, float(index) / float(arm.size() - 1)))
		mesh.sweep(arm, arm_sizes, SUIT, 10, 2.0, Vector3.UP, false, 0.8)
		mesh.sweep(PackedVector3Array([wrist, hand]), PackedVector2Array([Vector2(0.05, 0.05), Vector2(0.056, 0.05)]), GLOVE, 8, 2.2, Vector3.UP, false, 1.0)
	var rim: PackedVector3Array = PackedVector3Array()
	var rim_sizes: PackedVector2Array = PackedVector2Array()
	for index: int in range(16):
		var angle: float = TAU * float(index) / 16.0
		rim.append(WHEEL_CENTER + (u * cos(angle) + v * sin(angle)) * WHEEL_RADIUS)
		rim_sizes.append(Vector2(0.018, 0.02))
	mesh.sweep(rim, rim_sizes, WHEEL_TINT, 6, 2.0, Vector3.UP, true, 0.0, WHEEL_CENTER)
	var column: PackedVector3Array = PackedVector3Array([WHEEL_CENTER + n * 0.02, WHEEL_CENTER - n * 0.26])
	mesh.sweep(column, PackedVector2Array([Vector2(0.04, 0.04), Vector2(0.025, 0.025)]), WHEEL_TINT, 8, 2.0, Vector3.UP, false, 0.6)
	_body_mesh = mesh.commit()
	_body_mesh.set_meta(&"triangles", mesh.triangle_count())
	return _body_mesh


## Slightly wide chibi head with a softer jaw, centred on its own origin.
static func _head() -> ArrayMesh:
	if _head_mesh != null:
		return _head_mesh
	var mesh: SoftMesh = SoftMesh.new()
	var rings: Array[PackedVector3Array] = []
	var bands: int = 10
	for index: int in range(1, bands):
		var theta: float = PI * float(index) / float(bands)
		var jaw: float = 1.0 - 0.14 * pow(maxf(cos(theta), 0.0), 2.0)
		var half: Vector2 = Vector2(1.05, 1.0) * sin(theta) * HEAD_RADIUS * jaw
		rings.append(SoftMesh.section_ring(Vector3(0.0, -cos(theta) * HEAD_RADIUS, 0.0), Vector3.UP, Vector3.BACK, half, 16, 2.0))
	mesh.add_rings(rings, Color.WHITE, false, Vector3(0.0, -HEAD_RADIUS * 0.96, 0.0), Vector3(0.0, HEAD_RADIUS, 0.0))
	_head_mesh = mesh.commit()
	_head_mesh.set_meta(&"triangles", mesh.triangle_count())
	return _head_mesh


## Returns [shell, rim, goggles], all centred on the head.
static func _helmet() -> Array[ArrayMesh]:
	if not _helmet_meshes.is_empty():
		return _helmet_meshes
	var shell: SoftMesh = SoftMesh.new()
	var rings: Array[PackedVector3Array] = []
	var edge: PackedVector3Array = PackedVector3Array()
	for band: int in range(HELMET_BANDS):
		var t: float = float(band) / float(HELMET_BANDS)
		var ring: PackedVector3Array = PackedVector3Array()
		for seg: int in range(HELMET_SEGMENTS):
			var psi: float = TAU * float(seg) / float(HELMET_SEGMENTS)
			var elevation: float = lerpf(_edge_elevation(psi), PI * 0.5, t)
			ring.append(_on_helmet(psi, elevation, HELMET_RADIUS))
			if band == 0:
				edge.append(_on_helmet(psi, elevation, HELMET_RADIUS * 0.99))
		rings.append(ring)
	shell.add_rings(rings, Color.WHITE, false, Vector3.INF, Vector3(0.0, HELMET_RADIUS, 0.0))
	var rim: SoftMesh = SoftMesh.new()
	var rim_sizes: PackedVector2Array = PackedVector2Array()
	rim_sizes.resize(edge.size())
	rim_sizes.fill(Vector2(0.024, 0.02))
	rim.sweep(edge, rim_sizes, Color.WHITE, 6, 2.2, Vector3.UP, true, 0.0, Vector3.ZERO)
	var goggles: SoftMesh = SoftMesh.new()
	goggles.dome_rings = 2
	var arc: PackedVector3Array = PackedVector3Array()
	for index: int in range(9):
		var psi: float = -PI * 0.5 + deg_to_rad(lerpf(-62.0, 62.0, float(index) / 8.0))
		arc.append(_on_helmet(psi, deg_to_rad(GOGGLE_ELEVATION), HELMET_RADIUS + 0.004))
	var arc_sizes: PackedVector2Array = PackedVector2Array()
	arc_sizes.resize(arc.size())
	arc_sizes.fill(Vector2(0.022, 0.012))
	goggles.sweep(arc, arc_sizes, Color.WHITE, 6, 2.4, Vector3.UP, false, 1.0, Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		var normal: Vector3 = _on_helmet(-PI * 0.5 + side * deg_to_rad(21.0), deg_to_rad(GOGGLE_ELEVATION), 1.0).normalized()
		var lens: PackedVector3Array = PackedVector3Array([normal * (HELMET_RADIUS - 0.01), normal * (HELMET_RADIUS + 0.018)])
		goggles.sweep(lens, PackedVector2Array([Vector2(0.058, 0.046), Vector2(0.058, 0.046)]), Color.WHITE, 12, 2.6, Vector3.UP, false, 0.45)
	for part: SoftMesh in [shell, rim, goggles]:
		var mesh: ArrayMesh = part.commit()
		mesh.set_meta(&"triangles", part.triangle_count())
		_helmet_meshes.append(mesh)
	return _helmet_meshes


## Lower edge of the shell: the brow in front of the face, the skirt behind.
static func _edge_elevation(psi: float) -> float:
	var from_front: float = absf(wrapf(psi + PI * 0.5, -PI, PI))
	var open: float = deg_to_rad(OPENING_HALF_ANGLE)
	var blend: float = smoothstep(open - deg_to_rad(30.0), open + deg_to_rad(18.0), from_front)
	var brow: float = BROW_ELEVATION - BROW_ARCH * pow(minf(from_front / open, 1.0), 2.0)
	return deg_to_rad(lerpf(brow, SKIRT_ELEVATION, blend))


## Azimuth `psi` turns from +X towards +Z, so -Z (the face) is psi = -PI/2.
static func _on_helmet(psi: float, elevation: float, radius: float) -> Vector3:
	return Vector3(cos(elevation) * cos(psi), sin(elevation), cos(elevation) * sin(psi) * 1.04) * radius
