class_name TrackDressing
extends RefCounted

## Phase 17 "v3" trackside dressing layered on top of TrackArt's sky/props:
## crowd, hairpin signage, item-box markers, a countdown-lit start gantry and
## the ground beyond the road (kerbs/checker are painted by road.gdshader).
## Visual only — never adds or edits collision shapes.

const SIGN_STEP: float = 12.0
const SIGN_CURVATURE_MIN: float = 0.033
const SIGN_OUTSET: float = 2.4
const STRAIGHT_STEP: float = 4.0
const STRAIGHT_CURVATURE_MAX: float = 0.006
const STAND_COUNT_MAX: int = 9
const STAND_OUTSET: float = 9.5
const TERRAIN_MARGIN: float = 90.0
const TERRAIN_DIVISIONS: int = 18
const TERRAIN_DEPTH: float = 2.6
const TERRAIN_NOISE_AMPLITUDE: float = 1.4
const CLIFF_STEP: float = 4.0
const CLIFF_DROP: float = 22.0

## Adds every v3 dressing pass; called by `TrackArt.install` once art is up.
static func install(root: Node3D, track: Node3D, line: RacingLine, theme: int) -> void:
	var width: float = float(track.get("road_width")) if track.has_method("bank_at") else 14.0
	_terrain(root, line, theme)
	if track.has_method("is_gap"):
		_cliffs(root, track, line)
	_hairpin_signs(root, track, line, width)
	_crowd(root, line, width)
	_item_box_markers(root, track)
	_gantry(root, line, width)


static func _batch(root: Node3D, node_name: String, mesh: Mesh, paint: Material, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.material_override = paint
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)


## Trackside hazard boards on the outside apex of every hairpin-tight corner,
## tilted toward the direction of travel so they read while approaching.
static func _hairpin_signs(root: Node3D, track: Node3D, line: RacingLine, width: float) -> void:
	var backing: BoxMesh = BoxMesh.new()
	backing.size = Vector3(1.4, 1.0, 0.08)
	var face: BoxMesh = BoxMesh.new()
	face.size = Vector3(0.95, 0.65, 0.1)
	var backing_xf: Array[Transform3D] = []
	var face_xf: Array[Transform3D] = []
	var count: int = ceili(line.length() / SIGN_STEP)
	var last_offset: float = -1000.0
	for index: int in range(count):
		var offset: float = float(index) * SIGN_STEP
		var curvature: float = line.curvature_at(offset)
		if absf(curvature) < SIGN_CURVATURE_MIN or offset - last_offset < SIGN_STEP * 0.9:
			continue
		if track.has_method("is_gap") and bool(track.call("is_gap", line.sample(offset))):
			continue
		last_offset = offset
		var outside: float = signf(curvature)
		var at: Vector3 = line.sample(offset) + line.right_at(offset) * (outside * (width * 0.5 + SIGN_OUTSET)) + Vector3.UP * 1.1
		var facing: Vector3 = -line.tangent_at(offset).rotated(Vector3.UP, outside * 0.35)
		var basis: Basis = Basis.looking_at(facing, Vector3.UP)
		backing_xf.append(Transform3D(basis, root.to_local(at)))
		face_xf.append(Transform3D(basis, root.to_local(at + facing * -0.03)))
	_batch(root, "SignBacking", backing, PrimitiveArt.material(Color(0.95, 0.75, 0.08), true), backing_xf)
	_batch(root, "SignFace", face, PrimitiveArt.material(Color(0.05, 0.05, 0.05)), face_xf)


## Bleacher blocks and a facing banner strip along the lap's longest straight.
static func _crowd(root: Node3D, line: RacingLine, width: float) -> void:
	var straight: Vector2 = _longest_straight(line)
	if straight.y < STRAIGHT_STEP * 3.0:
		return
	var count: int = clampi(int(straight.y / 14.0), 2, STAND_COUNT_MAX)
	var stand: BoxMesh = BoxMesh.new()
	stand.size = Vector3(4.0, 3.2, 3.0)
	var banner: BoxMesh = BoxMesh.new()
	banner.size = Vector3(3.4, 1.1, 0.1)
	var stand_xf: Array[Transform3D] = []
	var banner_xf: Array[Transform3D] = []
	for index: int in range(count):
		var offset: float = straight.x + straight.y * (float(index) + 0.5) / float(count)
		var basis: Basis = Basis.looking_at(line.tangent_at(offset), Vector3.UP)
		var stand_pos: Vector3 = line.sample(offset) + line.right_at(offset) * (width * 0.5 + STAND_OUTSET) + Vector3.UP * 1.6
		stand_xf.append(Transform3D(basis, root.to_local(stand_pos)))
		var banner_pos: Vector3 = line.sample(offset) + line.right_at(offset) * (width * 0.5 + STAND_OUTSET - 2.6) + Vector3.UP * 2.9
		banner_xf.append(Transform3D(basis, root.to_local(banner_pos)))
	_batch(root, "CrowdStands", stand, PrimitiveArt.material(Color(0.32, 0.36, 0.42)), stand_xf)
	_batch(root, "CrowdBanners", banner, PrimitiveArt.material(Color(0.85, 0.2, 0.18), true), banner_xf)


## Longest contiguous low-curvature span of the lap, as `(start_offset, length)`.
static func _longest_straight(line: RacingLine) -> Vector2:
	var count: int = ceili(line.length() / STRAIGHT_STEP)
	var best_start: float = 0.0
	var best_len: float = 0.0
	var run_start: float = 0.0
	var in_run: bool = false
	for index: int in range(count):
		var offset: float = float(index) * STRAIGHT_STEP
		var straight: bool = absf(line.curvature_at(offset)) < STRAIGHT_CURVATURE_MAX
		if straight and not in_run:
			run_start = offset
			in_run = true
		elif not straight and in_run:
			if offset - run_start > best_len:
				best_len = offset - run_start
				best_start = run_start
			in_run = false
	if in_run and line.length() - run_start > best_len:
		best_len = line.length() - run_start
		best_start = run_start
	return Vector2(best_start, best_len)


## A small floating diamond marker above every item box, batched in one draw.
static func _item_box_markers(root: Node3D, track: Node3D) -> void:
	var container: Node = track.get_node_or_null("ItemBoxes")
	if container == null:
		return
	var boxes: Array[Node] = container.get_children()
	if boxes.is_empty():
		return
	var shape: BoxMesh = BoxMesh.new()
	shape.size = Vector3(0.55, 0.55, 0.55)
	var transforms: Array[Transform3D] = []
	for box: Node in boxes:
		if box is Node3D:
			var at: Vector3 = (box as Node3D).global_position + Vector3.UP * 2.1
			transforms.append(Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), root.to_local(at)))
	_batch(root, "ItemBoxMarkers", shape, PrimitiveArt.material(Color(0.95, 0.75, 0.15), true), transforms)


## Two pillars, a header beam and a row of lights over the start line; the
## row lights up on the countdown via `track/elements/start_gantry.gd`.
static func _gantry(root: Node3D, line: RacingLine, width: float) -> void:
	var gantry: Node3D = Node3D.new()
	gantry.name = "StartGantry"
	gantry.set_script(load("res://track/elements/start_gantry.gd"))
	root.add_child(gantry)
	var basis: Basis = Basis.looking_at(line.tangent_at(0.0), Vector3.UP)
	gantry.global_transform = Transform3D(basis, line.sample(0.0))
	var frame: StandardMaterial3D = PrimitiveArt.material(Color(0.55, 0.58, 0.62))
	var half: float = width * 0.5 + 0.6
	PrimitiveArt.add_box(gantry, Vector3(0.5, 5.2, 0.5), Vector3(-half, 2.6, 0.0), frame)
	PrimitiveArt.add_box(gantry, Vector3(0.5, 5.2, 0.5), Vector3(half, 2.6, 0.0), frame)
	PrimitiveArt.add_box(gantry, Vector3(width + 1.2, 0.5, 0.5), Vector3(0.0, 5.2, 0.0), frame)
	gantry.call("build_lights", width)


## A large noise-displaced ground plane, sunk below the road so decorative
## scenery never intersects the drivable surface or its walls.
static func _terrain(root: Node3D, line: RacingLine, theme: int) -> void:
	var min_point: Vector2 = Vector2.INF
	var max_point: Vector2 = -Vector2.INF
	var samples: int = ceili(line.length() / 8.0)
	for index: int in range(samples):
		var point: Vector3 = line.sample(line.length() * float(index) / float(samples))
		min_point = min_point.min(Vector2(point.x, point.z))
		max_point = max_point.max(Vector2(point.x, point.z))
	min_point -= Vector2.ONE * TERRAIN_MARGIN
	max_point += Vector2.ONE * TERRAIN_MARGIN
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 7717
	noise.frequency = 0.01
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(WorldMaterials.terrain(theme))
	var grid: Array = []
	for row: int in range(TERRAIN_DIVISIONS + 1):
		var line_row: Array[Vector3] = []
		for column: int in range(TERRAIN_DIVISIONS + 1):
			var x: float = lerp(min_point.x, max_point.x, float(column) / float(TERRAIN_DIVISIONS))
			var z: float = lerp(min_point.y, max_point.y, float(row) / float(TERRAIN_DIVISIONS))
			var y: float = -TERRAIN_DEPTH + noise.get_noise_2d(x, z) * TERRAIN_NOISE_AMPLITUDE
			line_row.append(Vector3(x, y, z))
		grid.append(line_row)
	for row: int in range(TERRAIN_DIVISIONS):
		for column: int in range(TERRAIN_DIVISIONS):
			var a: Vector3 = grid[row][column]
			var b: Vector3 = grid[row][column + 1]
			var c: Vector3 = grid[row + 1][column + 1]
			var d: Vector3 = grid[row + 1][column]
			for vertex: Vector3 in [a, b, c, a, c, d]:
				surface.set_uv(Vector2(vertex.x, vertex.z) * 0.05)
				surface.add_vertex(root.to_local(vertex))
	surface.generate_normals()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Terrain"
	node.mesh = surface.commit()
	root.add_child(node)


## Decorative canyon walls and a floor beneath every authored track gap, so a
## dropped kart falls past visible rock instead of open sky.
static func _cliffs(root: Node3D, track: Node3D, line: RacingLine) -> void:
	var rock: StandardMaterial3D = TrackArt.surface(Color(0.32, 0.3, 0.28))
	var width: float = float(track.get("road_width"))
	var count: int = ceili(line.length() / CLIFF_STEP)
	var wall: SurfaceTool = SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	wall.set_material(rock)
	var any: bool = false
	for index: int in range(count):
		var a: float = float(index) * CLIFF_STEP
		var b: float = float(index + 1) * CLIFF_STEP
		var mid: Vector3 = (line.sample(a) + line.sample(b)) * 0.5
		if not bool(track.call("is_gap", mid)):
			continue
		any = true
		for side: float in [-1.0, 1.0]:
			var lateral: float = side * width * 0.5
			var top_a: Vector3 = line.sample(a) + line.right_at(a) * lateral
			var top_b: Vector3 = line.sample(b) + line.right_at(b) * lateral
			var bottom_a: Vector3 = top_a + Vector3.DOWN * CLIFF_DROP
			var bottom_b: Vector3 = top_b + Vector3.DOWN * CLIFF_DROP
			for vertex: Vector3 in [top_a, bottom_a, bottom_b, top_a, bottom_b, top_b]:
				wall.set_uv(Vector2(vertex.x, vertex.y) * 0.2)
				wall.add_vertex(root.to_local(vertex))
	if not any:
		return
	wall.generate_normals()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "CliffWalls"
	node.mesh = wall.commit()
	root.add_child(node)
