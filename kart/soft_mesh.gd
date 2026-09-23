class_name SoftMesh
extends RefCounted

## Tiny procedural modelling kit for the soft, toy-like kart art (Phase 19
## "kart-soft"): superellipse sweeps with domed ends and free-form ring grids,
## accumulated into ONE indexed surface with smooth normals. Each part carries
## a vertex COLOR (a car-paint role on the body, a tint on the driver).
##
## Winding: a ring advancing along +T with its section angle turning from the
## section's side axis towards its up axis yields outward-facing triangles.

## Rings emitted per domed end (plus the closing tip vertex).
var dome_rings: int = 3
var vertices: PackedVector3Array = PackedVector3Array()
var colors: PackedColorArray = PackedColorArray()
var indices: PackedInt32Array = PackedInt32Array()


## Point on a superellipse |x/a|^n + |y/b|^n = 1 at parameter `angle`
## (n = 2 ellipse, larger n = rounder box).
static func superellipse(angle: float, half: Vector2, exponent: float) -> Vector2:
	var c: float = cos(angle)
	var s: float = sin(angle)
	var e: float = 2.0 / exponent
	return Vector2(signf(c) * pow(absf(c), e) * half.x, signf(s) * pow(absf(s), e) * half.y)


## Smooth Catmull-Rom resample of `keys` with `steps` samples per span.
static func smooth(keys: Array, steps: int) -> Array:
	var out: Array = []
	var count: int = keys.size()
	for span: int in range(count - 1):
		var p0: Variant = keys[maxi(span - 1, 0)]
		var p1: Variant = keys[span]
		var p2: Variant = keys[span + 1]
		var p3: Variant = keys[mini(span + 2, count - 1)]
		for step: int in range(steps):
			var t: float = float(step) / float(steps)
			var t2: float = t * t
			var t3: float = t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(keys[count - 1])
	return out


## Sweeps a superellipse section along `path`; sizes[i] = half extents of ring
## i along its (side, up) axes. The up axis follows `up_hint`, or points away
## from `radial_center` when that is finite (arcs, loops on a sphere). Open
## paths get domed ends `dome` x the smaller half extent long (0 = open).
func sweep(path: PackedVector3Array, sizes: PackedVector2Array, color: Color, segments: int = 12, exponent: float = 2.0, up_hint: Vector3 = Vector3.UP, closed: bool = false, dome: float = 1.0, radial_center: Vector3 = Vector3.INF) -> void:
	var count: int = path.size()
	var rings: Array[PackedVector3Array] = []
	var first_tangent: Vector3 = Vector3.ZERO
	var last_tangent: Vector3 = Vector3.ZERO
	for index: int in range(count):
		var prev: Vector3 = path[(index - 1 + count) % count] if closed or index > 0 else path[index]
		var next: Vector3 = path[(index + 1) % count] if closed or index < count - 1 else path[index]
		var tangent: Vector3 = (next - prev).normalized()
		var hint: Vector3 = up_hint if not radial_center.is_finite() else (path[index] - radial_center).normalized()
		rings.append(section_ring(path[index], tangent, hint, sizes[index], segments, exponent))
		if index == 0:
			first_tangent = tangent
		last_tangent = tangent
	if closed:
		add_rings(rings, color, true)
		return
	var start_tip: Vector3 = Vector3.INF
	var end_tip: Vector3 = Vector3.INF
	if dome > 0.0:
		var head: Array[PackedVector3Array] = []
		var tail: Array[PackedVector3Array] = []
		var start_len: float = dome * minf(sizes[0].x, sizes[0].y)
		var end_len: float = dome * minf(sizes[count - 1].x, sizes[count - 1].y)
		for k: int in range(dome_rings, 0, -1):
			var theta: float = float(k) / float(dome_rings + 1) * PI * 0.5
			head.append(_offset_ring(rings[0], path[0], -first_tangent * start_len * sin(theta), cos(theta)))
		for k: int in range(1, dome_rings + 1):
			var theta: float = float(k) / float(dome_rings + 1) * PI * 0.5
			tail.append(_offset_ring(rings[count - 1], path[count - 1], last_tangent * end_len * sin(theta), cos(theta)))
		head.append_array(rings)
		head.append_array(tail)
		rings = head
		start_tip = path[0] - first_tangent * start_len
		end_tip = path[count - 1] + last_tangent * end_len
	add_rings(rings, color, false, start_tip, end_tip)


## Connects consecutive closed rings (equal vertex counts) into a tube; finite
## tips close either end with a fan. `skip(ring, segment)` may drop quads.
func add_rings(rings: Array[PackedVector3Array], color: Color, loop: bool = false, start_tip: Vector3 = Vector3.INF, end_tip: Vector3 = Vector3.INF, skip: Callable = Callable()) -> void:
	var base: int = vertices.size()
	var segments: int = rings[0].size()
	for ring: PackedVector3Array in rings:
		for point: Vector3 in ring:
			vertices.append(point)
			colors.append(color)
	var ring_count: int = rings.size()
	var spans: int = ring_count if loop else ring_count - 1
	for ring_index: int in range(spans):
		var a0: int = base + ring_index * segments
		var b0: int = base + ((ring_index + 1) % ring_count) * segments
		for seg: int in range(segments):
			if skip.is_valid() and skip.call(ring_index, seg):
				continue
			var seg1: int = (seg + 1) % segments
			indices.append_array([a0 + seg, a0 + seg1, b0 + seg, a0 + seg1, b0 + seg1, b0 + seg])
	if start_tip.is_finite():
		var tip: int = _append(start_tip, color)
		for seg: int in range(segments):
			indices.append_array([tip, base + (seg + 1) % segments, base + seg])
	if end_tip.is_finite():
		var tip: int = _append(end_tip, color)
		var last: int = base + (ring_count - 1) * segments
		for seg: int in range(segments):
			indices.append_array([last + seg, last + (seg + 1) % segments, tip])


func triangle_count() -> int:
	return indices.size() / 3


## Bakes everything into a one-surface mesh (see bake()).
func commit(material: Material = null) -> ArrayMesh:
	return bake([self], [material])


## Bakes parts into one mesh (a surface per part) with smooth normals merged
## across coincident positions and automatic LODs (ImporterMesh), so distant
## karts render far fewer triangles without any per-frame code.
static func bake(parts: Array[SoftMesh], materials: Array[Material]) -> ArrayMesh:
	var importer: ImporterMesh = ImporterMesh.new()
	for part_index: int in range(parts.size()):
		var part: SoftMesh = parts[part_index]
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index: int in range(part.vertices.size()):
			tool.set_color(part.colors[index])
			tool.add_vertex(part.vertices[index])
		for index: int in part.indices:
			tool.add_index(index)
		tool.generate_normals()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, tool.commit_to_arrays(), [], {}, materials[part_index])
	importer.generate_lods(60.0, 25.0, [])
	return importer.get_mesh()


func _append(point: Vector3, color: Color) -> int:
	vertices.append(point)
	colors.append(color)
	return vertices.size() - 1


## One section ring: `half` along side = tangent x hint, then up = side x tangent.
static func section_ring(center: Vector3, tangent: Vector3, hint: Vector3, half: Vector2, segments: int, exponent: float) -> PackedVector3Array:
	var side: Vector3 = tangent.cross(hint)
	if side.length_squared() < 1e-8:
		side = tangent.cross(Vector3.FORWARD if absf(tangent.z) < 0.9 else Vector3.RIGHT)
	side = side.normalized()
	var up: Vector3 = side.cross(tangent).normalized()
	var ring: PackedVector3Array = PackedVector3Array()
	for seg: int in range(segments):
		var p: Vector2 = superellipse(TAU * float(seg) / float(segments), half, exponent)
		ring.append(center + side * p.x + up * p.y)
	return ring


static func _offset_ring(ring: PackedVector3Array, center: Vector3, offset: Vector3, scale: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in ring:
		out.append(center + offset + (point - center) * scale)
	return out
