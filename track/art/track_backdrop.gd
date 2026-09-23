class_name TrackBackdrop
extends RefCounted

## Phase 19 distant horizon: two silhouette rings (near + far) around the lap
## so the horizon is never empty. Mountains (ridgeline), skyline (lumen), ice
## ridges (glacier) and mesas (ochre). Two draw calls, no shadows, no collision.

const SHADER: Shader = preload("res://assets/shaders/world/backdrop.gdshader")
const NEAR_MARGIN: float = 260.0
const FAR_GAP: float = 480.0
const BASE_DROP: float = 25.0
const ARC_STEP: float = 24.0
const MOUNTAINS: int = 0
const SKYLINE: int = 1
const RIDGES: int = 2
const MESAS: int = 3

## Per theme: [near, far] ring looks. Heights in metres above the ring base.
const RINGS: Array = [
	[
		{"lo": 45.0, "hi": 150.0, "lean": 0.9, "base": Color(0.2, 0.36, 0.22), "peak": Color(0.34, 0.48, 0.44), "cap": 2.0},
		{"lo": 140.0, "hi": 330.0, "lean": 1.1, "base": Color(0.34, 0.46, 0.58), "peak": Color(0.52, 0.62, 0.76), "cap": 0.72},
	],
	[
		{"lo": 25.0, "hi": 120.0, "lean": 0.0, "base": Color(0.03, 0.035, 0.06), "peak": Color(0.07, 0.07, 0.12), "windows": 1.0},
		{"lo": 60.0, "hi": 210.0, "lean": 0.0, "base": Color(0.05, 0.04, 0.1), "peak": Color(0.09, 0.07, 0.16), "windows": 0.45},
	],
	[
		{"lo": 50.0, "hi": 190.0, "lean": 0.7, "base": Color(0.52, 0.62, 0.76), "peak": Color(0.72, 0.82, 0.94), "cap": 0.55},
		{"lo": 150.0, "hi": 380.0, "lean": 0.9, "base": Color(0.5, 0.62, 0.78), "peak": Color(0.8, 0.88, 0.97), "cap": 0.5},
	],
	[
		{"lo": 30.0, "hi": 105.0, "lean": 0.25, "base": Color(0.6, 0.28, 0.14), "peak": Color(0.82, 0.48, 0.27), "strata": 1.0},
		{"lo": 55.0, "hi": 150.0, "lean": 0.25, "base": Color(0.76, 0.5, 0.38), "peak": Color(0.86, 0.62, 0.48), "strata": 0.6},
	],
]


static func install(root: Node3D, line: RacingLine, theme: int) -> void:
	var min_point: Vector3 = Vector3.INF
	var max_point: Vector3 = -Vector3.INF
	var samples: int = ceili(line.length() / 10.0)
	for index: int in range(samples):
		var point: Vector3 = line.sample(line.length() * float(index) / float(samples))
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var centre: Vector3 = (min_point + max_point) * 0.5
	var extent: float = Vector2(max_point.x - min_point.x, max_point.z - min_point.z).length() * 0.5
	var base_y: float = min_point.y - BASE_DROP
	var looks: Array = RINGS[clampi(theme, 0, RINGS.size() - 1)]
	for ring: int in range(2):
		var radius: float = extent + NEAR_MARGIN + FAR_GAP * float(ring)
		var look: Dictionary = looks[ring]
		var profile: PackedVector2Array = _profile(theme, radius, look, 4101 + ring * 77)
		_ring(root, "Backdrop%d" % ring, Vector3(centre.x, base_y, centre.z), radius, profile, look)


## (arc metres, height) points around the full ring, closed.
static func _profile(theme: int, radius: float, look: Dictionary, seed_value: int) -> PackedVector2Array:
	var circumference: float = TAU * radius
	var lo: float = look["lo"]
	var hi: float = look["hi"]
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0 / 420.0
	noise.fractal_octaves = 4
	var points: PackedVector2Array = PackedVector2Array()
	if theme == SKYLINE:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		var arc: float = 0.0
		while arc < circumference:
			var width: float = minf(rng.randf_range(16.0, 55.0), circumference - arc)
			var tower: float = 1.0 if rng.randf() < 0.18 else 0.0
			var height: float = lerpf(lo, hi, clampf(rng.randf() * 0.65 + tower * 0.45 + noise.get_noise_1d(arc) * 0.3, 0.0, 1.0))
			points.append(Vector2(arc, height))
			points.append(Vector2(arc + width, height))
			arc += width
		return points
	var steps: int = ceili(circumference / ARC_STEP)
	for index: int in range(steps + 1):
		# Wrap the last sample onto the first so the ring closes without a seam.
		var arc: float = circumference * float(index % steps) / float(steps)
		var n: float = noise.get_noise_1d(arc)
		var t: float
		if theme == RIDGES:
			t = pow(1.0 - absf(n) * 1.6, 2.0)
		elif theme == MESAS:
			t = smoothstep(-0.12, 0.02, n) * 0.75 + smoothstep(0.25, 0.3, n) * 0.25
		else:
			t = 0.5 + n * 0.9
		points.append(Vector2(circumference * float(index) / float(steps), lerpf(lo, hi, clampf(t, 0.0, 1.0))))
	return points


static func _ring(root: Node3D, node_name: String, centre: Vector3, radius: float, profile: PackedVector2Array, look: Dictionary) -> void:
	var lean: float = look["lean"]
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(profile.size() - 1):
		var a: Vector2 = profile[index]
		var b: Vector2 = profile[index + 1]
		var rows_a: Array[Vector3] = _column(centre, radius, a, lean)
		var rows_b: Array[Vector3] = _column(centre, radius, b, lean)
		for row: int in range(2):
			var quad: Array = [
				[rows_a[row], Vector2(a.x, a.y * row * 0.5)], [rows_b[row], Vector2(b.x, b.y * row * 0.5)],
				[rows_b[row + 1], Vector2(b.x, b.y * (row + 1) * 0.5)], [rows_a[row], Vector2(a.x, a.y * row * 0.5)],
				[rows_b[row + 1], Vector2(b.x, b.y * (row + 1) * 0.5)], [rows_a[row + 1], Vector2(a.x, a.y * (row + 1) * 0.5)],
			]
			for vertex: Array in quad:
				surface.set_uv(vertex[1])
				surface.add_vertex(root.to_local(vertex[0]))
	surface.generate_normals()
	var paint: ShaderMaterial = ShaderMaterial.new()
	paint.shader = SHADER
	paint.set_shader_parameter(&"base_color", look["base"])
	paint.set_shader_parameter(&"peak_color", look["peak"])
	paint.set_shader_parameter(&"peak_height", float(look["hi"]))
	paint.set_shader_parameter(&"cap_line", float(look.get("cap", 2.0)))
	paint.set_shader_parameter(&"strata", float(look.get("strata", 0.0)))
	paint.set_shader_parameter(&"windows", float(look.get("windows", 0.0)))
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = surface.commit()
	node.material_override = paint
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(node)


## Base, shoulder and crest vertices; the crest leans away from the track.
static func _column(centre: Vector3, radius: float, point: Vector2, lean: float) -> Array[Vector3]:
	var angle: float = point.x / radius
	var outward: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var mid_radius: float = radius + point.y * lean * 0.35
	var top_radius: float = radius + point.y * lean
	return [
		centre + outward * radius,
		centre + outward * mid_radius + Vector3.UP * point.y * 0.5,
		centre + outward * top_radius + Vector3.UP * point.y,
	]
