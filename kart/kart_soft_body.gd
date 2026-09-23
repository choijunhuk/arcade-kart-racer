class_name KartSoftBody
extends RefCounted

## Soft, toy-like procedural kart body and wheels (Phase 19 kart-soft): a
## lofted superellipse tub with a rounded nose, sidepods, bumpers, fender arcs,
## seat and spoiler merged into ONE surface for the car-paint shader. Vertex
## COLOR carries the paint role (r = paint, g = glass, b = accent, 0 = trim).
## Visual only: collision shapes and physics never read any of this.

const PAINT: Color = Color(1.0, 0.0, 0.0)
const GLASS: Color = Color(0.0, 1.0, 0.0)
const ACCENT: Color = Color(0.0, 0.0, 1.0)
const TRIM: Color = Color(0.0, 0.0, 0.0)
## Kart-local ground height (the physics hover height below the kart origin).
const GROUND_Y: float = -0.35
const CLEARANCE: float = 0.08
const FRONT_RADIUS: float = 0.23
const REAR_RADIUS: float = 0.28
## Rear tyre half width per weight class (front tyres are 85% of it).
const TYRE_HALF: Array[float] = [0.12, 0.14, 0.16]
const DRIVER_SCALE: Array[float] = [0.92, 1.0, 1.07]
## Wing height above the engine cover per weight class (0 = no wing).
const WING_LIFT: Array[float] = [0.0, 0.2, 0.26]
## Exhaust tip must stay clear of the tub so it lines up with BoostEffects.
const TAIL_LIMIT: float = 0.95
## Tub stations nose->tail: (z / length, half width / tub width, bottom / height, top / height).
const TUB_STATIONS: Array[Vector4] = [
	Vector4(-0.47, 0.58, 0.14, 0.40), Vector4(-0.36, 0.78, 0.06, 0.50),
	Vector4(-0.22, 0.95, 0.0, 0.66), Vector4(-0.08, 1.0, 0.0, 0.56),
	Vector4(0.06, 1.0, 0.0, 0.46), Vector4(0.18, 1.02, 0.0, 0.56),
	Vector4(0.30, 1.0, 0.0, 0.80), Vector4(0.40, 0.92, 0.04, 0.84),
	Vector4(0.47, 0.78, 0.1, 0.68),
]

static var _bodies: Dictionary[StringName, ArrayMesh] = {}
static var _wheels: Dictionary[String, ArrayMesh] = {}
static var _tyre_material: StandardMaterial3D = _plain(Color(0.07, 0.07, 0.08), 0.82, 0.0)
static var _rim_material: StandardMaterial3D = _plain(Color(0.8, 0.82, 0.85), 0.3, 0.75)


## Per-kart proportions derived from the class footprint.
class Shape:
	var size: Vector3
	var weight_class: int
	var floor_y: float
	var tub_half: float
	var front_tyre: float
	var rear_tyre: float
	var front_track: float
	var rear_track: float
	var front_z: float
	var rear_z: float
	var seat: Vector3
	var driver_scale: float


static func shape(data: KartData) -> Shape:
	var s: Shape = Shape.new()
	s.size = KartMeshBuilder.target_body_size(data)
	s.weight_class = data.weight_class
	s.floor_y = GROUND_Y + CLEARANCE
	s.tub_half = s.size.x * 0.24
	s.rear_tyre = TYRE_HALF[s.weight_class]
	s.front_tyre = s.rear_tyre * 0.85
	s.rear_track = s.size.x * 0.5 - s.rear_tyre
	s.front_track = s.rear_track - 0.04
	s.front_z = -s.size.z * 0.5 + 0.36
	s.rear_z = s.size.z * 0.5 - 0.38
	s.seat = Vector3(0.0, s.floor_y + s.size.y * 0.3, s.size.z * 0.05)
	s.driver_scale = DRIVER_SCALE[s.weight_class]
	return s


## Wheel pivot positions (kart-local), keyed by kart.tscn pivot name.
static func wheel_positions(s: Shape) -> Dictionary[StringName, Vector3]:
	var front_y: float = GROUND_Y + FRONT_RADIUS
	var rear_y: float = GROUND_Y + REAR_RADIUS
	return {
		&"WheelFL": Vector3(-s.front_track, front_y, s.front_z),
		&"WheelFR": Vector3(s.front_track, front_y, s.front_z),
		&"WheelRL": Vector3(-s.rear_track, rear_y, s.rear_z),
		&"WheelRR": Vector3(s.rear_track, rear_y, s.rear_z),
	}


## Cached single-surface body. Metas: vertex_roles (car-paint shader reads
## COLOR roles), triangles, number_anchor (race-number Label3D transform).
static func body_mesh(data: KartData) -> ArrayMesh:
	if _bodies.has(data.id):
		return _bodies[data.id]
	var s: Shape = shape(data)
	var mesh: SoftMesh = SoftMesh.new()
	var deck: Array = _tub(mesh, s)
	_pods(mesh, s)
	mesh.dome_rings = 2
	_bumpers(mesh, s)
	for wheel: Vector3 in wheel_positions(s).values():
		_fender(mesh, s, wheel)
	_seat(mesh, s)
	_spoiler(mesh, s, deck)
	var result: ArrayMesh = mesh.commit(PrimitiveArt.material(data.body_color))
	result.set_meta(&"vertex_roles", true)
	result.set_meta(&"triangles", mesh.triangle_count())
	result.set_meta(&"number_anchor", _number_anchor(deck, s))
	_bodies[data.id] = result
	return result


## Chunky rounded tyre (surface 0) and domed hub-cap rim (surface 1, recoloured
## per driver by KartLivery). `outer` is the axle direction facing out (+-1).
static func wheel_mesh(front: bool, outer: float, s: Shape) -> ArrayMesh:
	var half: float = s.front_tyre if front else s.rear_tyre
	var key: String = "%s_%d_%.3f" % [front, int(outer), half]
	if _wheels.has(key):
		return _wheels[key]
	var radius: float = FRONT_RADIUS if front else REAR_RADIUS
	var inner: float = radius * 0.6
	var tyre: SoftMesh = SoftMesh.new()
	var path: PackedVector3Array = PackedVector3Array()
	var sizes: PackedVector2Array = PackedVector2Array()
	var center_radius: float = (radius + inner) * 0.5
	for index: int in range(14):
		var angle: float = TAU * float(index) / 14.0
		path.append(Vector3(0.0, sin(angle), cos(angle)) * center_radius)
		sizes.append(Vector2(half, (radius - inner) * 0.5))
	tyre.sweep(path, sizes, Color.WHITE, 8, 2.8, Vector3.UP, true, 0.0, Vector3.ZERO)
	var rim: SoftMesh = SoftMesh.new()
	rim.dome_rings = 2
	var axle: PackedVector3Array = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.42, 0, 0), Vector3(0.62, 0, 0)])
	for index: int in range(axle.size()):
		axle[index] *= half * outer
	var rim_sizes: PackedVector2Array = PackedVector2Array([Vector2.ONE * (inner + 0.01), Vector2.ONE * (inner + 0.01), Vector2.ONE * inner * 0.55])
	rim.sweep(axle, rim_sizes, Color.WHITE, 10, 2.0, Vector3.UP, false, 0.7)
	var mesh: ArrayMesh = SoftMesh.bake([tyre, rim], [_tyre_material, _rim_material])
	mesh.set_meta(&"triangles", tyre.triangle_count() + rim.triangle_count())
	_wheels[key] = mesh
	return mesh


## Lofted tub; returns the smoothed deck profile [z, top y] for later parts.
static func _tub(mesh: SoftMesh, s: Shape) -> Array:
	var keys: Array = []
	for station: Vector4 in TUB_STATIONS:
		var z: float = minf(station.x * s.size.z, TAIL_LIMIT) if station.x > 0.0 else station.x * s.size.z
		keys.append(Vector4(z, station.y * s.tub_half, s.floor_y + station.z * s.size.y, s.floor_y + station.w * s.size.y))
	var path: PackedVector3Array = PackedVector3Array()
	var sizes: PackedVector2Array = PackedVector2Array()
	var deck: Array = []
	for key: Vector4 in SoftMesh.smooth(keys, 2):
		path.append(Vector3(0.0, (key.z + key.w) * 0.5, key.x))
		sizes.append(Vector2(key.y, (key.w - key.z) * 0.5))
		deck.append(Vector2(key.x, key.w))
	mesh.sweep(path, sizes, PAINT, 12, 3.0, Vector3.UP, false, 0.7)
	return deck


static func _pods(mesh: SoftMesh, s: Shape) -> void:
	var z0: float = s.front_z + FRONT_RADIUS + 0.08
	var z1: float = s.rear_z - REAR_RADIUS - 0.07
	var inner: float = s.tub_half * 0.7
	var outer: float = s.rear_track + s.rear_tyre * 0.4
	var half: float = (outer - inner) * 0.5
	for side: float in [-1.0, 1.0]:
		var path: PackedVector3Array = PackedVector3Array()
		var sizes: PackedVector2Array = PackedVector2Array()
		for t: float in [0.0, 0.33, 0.66, 1.0]:
			var top: float = s.floor_y + s.size.y * lerpf(0.34, 0.5, t)
			var bottom: float = s.floor_y + 0.02
			path.append(Vector3(side * (inner + half), (top + bottom) * 0.5, lerpf(z0, z1, t)))
			sizes.append(Vector2(half * lerpf(0.82, 0.95, sin(t * PI)), (top - bottom) * 0.5))
		mesh.sweep(path, sizes, PAINT, 10, 2.6, Vector3.UP, false, 1.0)


static func _bumpers(mesh: SoftMesh, s: Shape) -> void:
	var y: float = s.floor_y + 0.07
	var nose_z: float = -s.size.z * 0.5 + 0.07
	var wide: float = s.front_track + 0.02
	var front: Array = [Vector3(-wide, y, s.front_z - FRONT_RADIUS - 0.09), Vector3(-wide * 0.5, y, nose_z + 0.02), Vector3(0.0, y, nose_z), Vector3(wide * 0.5, y, nose_z + 0.02), Vector3(wide, y, s.front_z - FRONT_RADIUS - 0.09)]
	_tube(mesh, front, Vector2(0.07, 0.075), TRIM)
	var rear_x: float = s.size.x * 0.5 - 0.1
	var tail_z: float = s.size.z * 0.5 - 0.07
	# Low enough to pass under the exhaust pipe (EXHAUST_PIPE_POSITION).
	var rear_y: float = s.floor_y + 0.02
	var rear: Array = [Vector3(-rear_x, rear_y, s.rear_z + REAR_RADIUS + 0.08), Vector3(-rear_x * 0.5, rear_y, tail_z), Vector3(0.0, rear_y, tail_z), Vector3(rear_x * 0.5, rear_y, tail_z), Vector3(rear_x, rear_y, s.rear_z + REAR_RADIUS + 0.08)]
	_tube(mesh, rear, Vector2(0.07, 0.065), TRIM)


## Mudguard arc over a wheel, following its rim at a small clearance, tied
## to the body by a short rounded stay.
static func _fender(mesh: SoftMesh, s: Shape, wheel: Vector3) -> void:
	var front: bool = wheel.z < 0.0
	var radius: float = (FRONT_RADIUS if front else REAR_RADIUS) + 0.06
	var half: float = (s.front_tyre if front else s.rear_tyre) + 0.03
	var from: float = deg_to_rad(20.0 if front else 45.0)
	var to: float = deg_to_rad(150.0 if front else 125.0)
	var path: PackedVector3Array = PackedVector3Array()
	var sizes: PackedVector2Array = PackedVector2Array()
	for index: int in range(5):
		var t: float = float(index) / 4.0
		var angle: float = lerpf(from, to, t)
		path.append(wheel + Vector3(0.0, sin(angle), -cos(angle)) * radius)
		sizes.append(Vector2(half, 0.034) * lerpf(0.8, 1.0, sin(t * PI)))
	mesh.dome_rings = 2
	mesh.sweep(path, sizes, PAINT, 8, 2.3, Vector3.UP, false, 1.0, wheel)
	var inward: float = -signf(wheel.x)
	var top: Vector3 = wheel + Vector3(inward * half * 0.55, radius * 0.9, 0.0)
	var anchor: Vector3 = Vector3(signf(wheel.x) * s.tub_half * 0.7, s.floor_y + s.size.y * 0.3, wheel.z)
	mesh.sweep(PackedVector3Array([top, anchor]), PackedVector2Array([Vector2(0.04, 0.03), Vector2(0.05, 0.04)]), PAINT, 6, 2.0, Vector3.FORWARD, false, 0.8)


## Rounded bucket-seat backrest behind the driver.
static func _seat(mesh: SoftMesh, s: Shape) -> void:
	var scale: float = s.driver_scale
	var z: float = s.seat.z + 0.18 * scale
	var y: float = s.seat.y + 0.13 * scale
	var back: Array = [Vector3(-0.17 * scale, y, z - 0.04), Vector3(0.0, y + 0.02, z), Vector3(0.17 * scale, y, z - 0.04)]
	_tube(mesh, back, Vector2(0.05, 0.15) * scale, TRIM)


## Accent wing on two struts; light karts stay wingless (slim and nimble).
static func _spoiler(mesh: SoftMesh, s: Shape, deck: Array) -> void:
	var lift: float = WING_LIFT[s.weight_class]
	if lift <= 0.0:
		return
	var z: float = minf(s.size.z * 0.5 - 0.18, TAIL_LIMIT)
	var cover: float = _deck_height(deck, z)
	var y: float = cover + lift
	var span: float = s.rear_track - 0.02
	var wing: Array = [Vector3(-span, y + 0.04, z + 0.02), Vector3(-span * 0.5, y, z), Vector3(0.0, y - 0.01, z), Vector3(span * 0.5, y, z), Vector3(span, y + 0.04, z + 0.02)]
	_tube(mesh, wing, Vector2(0.13, 0.026), ACCENT)
	for side: float in [-1.0, 1.0]:
		var strut: PackedVector3Array = PackedVector3Array([Vector3(side * span * 0.42, cover - 0.03, z - 0.04), Vector3(side * span * 0.42, y - 0.01, z)])
		mesh.sweep(strut, PackedVector2Array([Vector2(0.022, 0.05), Vector2(0.022, 0.05)]), TRIM, 6, 3.0, Vector3.UP, false, 0.5)


## Sweeps a smoothed tube with a constant rounded section through `keys`.
static func _tube(mesh: SoftMesh, keys: Array, half: Vector2, role: Color) -> void:
	var path: PackedVector3Array = PackedVector3Array()
	var sizes: PackedVector2Array = PackedVector2Array()
	for point: Vector3 in SoftMesh.smooth(keys, 2):
		path.append(point)
		sizes.append(half)
	mesh.sweep(path, sizes, role, 8, 2.6, Vector3.UP, false, 1.0)


static func _deck_height(deck: Array, z: float) -> float:
	var best: Vector2 = deck[0]
	for point: Vector2 in deck:
		if absf(point.x - z) < absf(best.x - z):
			best = point
	return best.y


## Race number lies on the sloped engine-cover rear, facing the chase camera.
static func _number_anchor(deck: Array, s: Shape) -> Transform3D:
	var tail: float = minf(0.47 * s.size.z, TAIL_LIMIT)
	var a: Vector2 = Vector2(tail - 0.2, _deck_height(deck, tail - 0.2))
	var b: Vector2 = Vector2(tail - 0.04, _deck_height(deck, tail - 0.04))
	var slope: float = atan2(a.y - b.y, b.x - a.x)
	var basis: Basis = Basis(Vector3.RIGHT, -(PI * 0.5 - slope))
	var at: Vector3 = Vector3(0.0, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5)
	return Transform3D(basis, at + basis.z * 0.03)


static func _plain(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
