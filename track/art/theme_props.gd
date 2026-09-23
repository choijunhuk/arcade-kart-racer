class_name ThemeProps
extends RefCounted

## Phase 19 scenery density: procedural low-poly theme props scattered in the
## ground band beyond the walls (pines/rocks, neon signs, ice spires, cacti and
## rim rocks), plus a Kenney banner/billboard pass along the main straight.
## Every prop kind is one MultiMesh per material; visual only, no collision.

const SCATTER_STEP: float = 7.0
const NEAR_CLEARANCE: float = 6.0
const BAND_MIN: float = 7.0
const BAND_MAX: float = 85.0
const GROUND_Y: float = -2.6
const PROP_RANGE: float = 420.0
const CHUNK: int = 48
const RIDGELINE: int = 0
const NIGHT: int = 1
const GLACIER: int = 2
const CANYON: int = 3
const BANNER_HEIGHT: float = 5.5
const BILLBOARD_HEIGHT: float = 4.5
const NEON_COLORS: Array[Color] = [Color(1.0, 0.2, 0.7), Color(0.15, 0.9, 1.0), Color(1.0, 0.8, 0.2)]


## `kenney` mirrors video.art_style == "kenney"; the Kenney straight dressing is skipped otherwise.
static func install(root: Node3D, track: Node3D, line: RacingLine, theme: int, kenney: bool = false) -> void:
	var width: float = float(track.get("road_width")) if track.has_method("bank_at") else 14.0
	var wall: float = float(track.get("wall_height")) if track.has_method("bank_at") else 2.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1900 + theme
	var kinds: Array[Dictionary] = _kinds(theme)
	var buckets: Array = []
	for kind: Dictionary in kinds:
		buckets.append([] as Array[Transform3D])
	var count: int = ceili(line.length() / SCATTER_STEP)
	for index: int in range(count):
		var offset: float = float(index) * SCATTER_STEP + rng.randf() * SCATTER_STEP
		for side: float in [-1.0, 1.0]:
			if rng.randf() > 0.8:
				continue
			var pick: int = _pick(kinds, rng)
			var kind: Dictionary = kinds[pick]
			var band_min: float = float(kind.get("lateral_min", BAND_MIN))
			var lateral: float = side * (width * 0.5 + band_min + pow(rng.randf(), 1.6) * (BAND_MAX - band_min))
			var at: Vector3 = line.sample(offset) + line.right_at(offset) * lateral
			if not _clear(line, at, width * 0.5 + maxf(NEAR_CLEARANCE, band_min - 2.0)):
				continue
			if track.has_method("is_gap") and bool(track.call("is_gap", line.sample(offset))):
				continue
			# Canyon props sit on the rim above the 12 m walls so they read from the floor.
			at.y = line.sample(offset).y + wall if theme == CANYON else GROUND_Y
			var size: float = rng.randf_range(kind["min"], kind["max"])
			var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.85, 1.2), size))
			if kind.has("face_road"):
				basis = Basis.looking_at(-line.right_at(offset) * signf(lateral), Vector3.UP).scaled(Vector3.ONE * size)
			buckets[pick].append(Transform3D(basis, root.to_local(at)))
	for pick: int in range(kinds.size()):
		for part: Array in kinds[pick]["parts"]:
			_batch_chunks(root, "Theme%s" % kinds[pick]["name"], part[0], part[1], buckets[pick])
	if kenney:
		_straight_banners(root, line, width * 0.5, theme)


## Kenney banner towers every 24 m on both sides of the main straight plus
## billboards behind the outside wall: the "race day" read of the grid area.
static func _straight_banners(root: Node3D, line: RacingLine, half_width: float, theme: int) -> void:
	var straight: Vector2 = TrackDressing.longest_straight(line)
	if straight.y < 40.0:
		return
	var towers: Array[ArrayMesh] = [
		TrackKenneyProps._load_prop_mesh("bannerTowerRed", BANNER_HEIGHT),
		TrackKenneyProps._load_prop_mesh("bannerTowerGreen", BANNER_HEIGHT),
	]
	var board: ArrayMesh = TrackKenneyProps._load_prop_mesh("billboard", BILLBOARD_HEIGHT)
	var tower_xf: Array = [[] as Array[Transform3D], [] as Array[Transform3D]]
	var board_xf: Array[Transform3D] = []
	var count: int = int(straight.y / 24.0)
	for index: int in range(count):
		var offset: float = straight.x + 12.0 + float(index) * 24.0
		var basis: Basis = Basis.looking_at(line.tangent_at(offset), Vector3.UP)
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = line.sample(offset) + line.right_at(offset) * side * (half_width + 2.4)
			tower_xf[(index + int(side > 0.0)) % 2].append(Transform3D(basis, root.to_local(at)))
		if index % 2 == 1 and theme != NIGHT:
			# Kenney models face +Z: point -Z away so the printed side faces the road.
			var face: Basis = Basis.looking_at(line.right_at(offset), Vector3.UP)
			var board_at: Vector3 = line.sample(offset) + line.right_at(offset) * (half_width + 5.5)
			board_xf.append(Transform3D(face, root.to_local(board_at)))
	for index: int in range(2):
		if towers[index] != null:
			TrackDressing.batch(root, "KenneyBannerTowers%d" % index, towers[index], null, tower_xf[index])
	if board != null:
		TrackDressing.batch(root, "KenneyBillboards", board, null, board_xf)


static func _clear(line: RacingLine, at: Vector3, clearance: float) -> bool:
	var nearest: Vector3 = line.sample(line.offset_at(at))
	return Vector2(at.x - nearest.x, at.z - nearest.z).length() >= clearance


static func _pick(kinds: Array[Dictionary], rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for kind: Dictionary in kinds:
		total += float(kind["weight"])
	var roll: float = rng.randf() * total
	for index: int in range(kinds.size()):
		roll -= float(kinds[index]["weight"])
		if roll <= 0.0:
			return index
	return kinds.size() - 1


## Prop catalogue per theme: name, weight, size range and [mesh, material] parts.
static func _kinds(theme: int) -> Array[Dictionary]:
	var bark: StandardMaterial3D = _paint(Color(0.36, 0.24, 0.16))
	if theme == NIGHT:
		var kinds: Array[Dictionary] = [{"name": "Crates", "weight": 2.0, "min": 0.8, "max": 1.6,
			"parts": [[_box(Vector3(2.4, 2.4, 2.4), 1.2), _paint(Color(0.12, 0.13, 0.17))]]}]
		var backing: StandardMaterial3D = _paint(Color(0.05, 0.05, 0.07))
		for color: Color in NEON_COLORS:
			var glow: StandardMaterial3D = _paint(color)
			glow.emission_enabled = true
			glow.emission = color
			glow.emission_energy_multiplier = 4.0
			kinds.append({"name": "NeonSign", "weight": 0.7, "min": 0.8, "max": 1.2, "face_road": true, "lateral_min": 16.0,
				"parts": [[_sign_frame(), backing], [_neon_tubes(), glow]]})
		return kinds
	if theme == GLACIER:
		var ice: StandardMaterial3D = _paint(Color(0.62, 0.84, 0.98))
		ice.roughness = 0.12
		ice.rim_enabled = true
		ice.rim = 0.6
		return [
			{"name": "IceSpire", "weight": 2.0, "min": 0.7, "max": 1.6, "parts": [[_cone(1.6, 9.0, 5), ice]]},
			{"name": "SnowPine", "weight": 3.0, "min": 0.8, "max": 1.4, "parts": [[_cone(0.3, 1.2, 6), bark], [_pine(), _paint(Color(0.22, 0.4, 0.34))]]},
			{"name": "IceBoulder", "weight": 1.5, "min": 0.8, "max": 2.2, "parts": [[_rock(), ice]]},
		]
	if theme == CANYON:
		return [
			{"name": "Cactus", "weight": 2.0, "min": 0.8, "max": 1.3, "parts": [[_cactus(), _paint(Color(0.3, 0.5, 0.22))]]},
			{"name": "RimRock", "weight": 3.0, "min": 1.2, "max": 3.5, "parts": [[_rock(), _paint(Color(0.72, 0.38, 0.2))]]},
		]
	return [
		{"name": "Pine", "weight": 4.0, "min": 0.8, "max": 1.5, "parts": [[_cone(0.3, 1.2, 6), bark], [_pine(), _paint(Color(0.12, 0.36, 0.16))]]},
		{"name": "Bush", "weight": 2.0, "min": 0.6, "max": 1.4, "parts": [[_rock(), _paint(Color(0.24, 0.5, 0.18))]]},
		{"name": "Rock", "weight": 1.0, "min": 0.6, "max": 1.8, "parts": [[_rock(), _paint(Color(0.55, 0.55, 0.52))]]},
	]


static func _paint(color: Color) -> StandardMaterial3D:
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = color
	paint.roughness = 0.85
	return paint


static func _box(size: Vector3, lift: float) -> ArrayMesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	return _baked(box, Transform3D(Basis.IDENTITY, Vector3.UP * lift))


static func _cone(radius: float, height: float, sides: int) -> ArrayMesh:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0 if radius > 1.0 else radius
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = sides
	cone.rings = 1
	return _baked(cone, Transform3D(Basis.IDENTITY, Vector3.UP * height * 0.5))


## Three stacked faceted cones on a trunk: the stylised pine silhouette.
static func _pine() -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tier: int in range(3):
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 2.4 - float(tier) * 0.6
		cone.height = 3.2 - float(tier) * 0.5
		cone.radial_segments = 7
		cone.rings = 1
		surface.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3.UP * (2.6 + float(tier) * 1.7)))
	surface.generate_normals()
	return surface.commit()


static func _cactus() -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk: CylinderMesh = CylinderMesh.new()
	trunk.top_radius = 0.38
	trunk.bottom_radius = 0.42
	trunk.height = 4.5
	trunk.radial_segments = 8
	surface.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3.UP * 2.25))
	for side: float in [-1.0, 1.0]:
		var arm: CylinderMesh = CylinderMesh.new()
		arm.top_radius = 0.26
		arm.bottom_radius = 0.26
		arm.height = 1.6
		arm.radial_segments = 8
		surface.append_from(arm, 0, Transform3D(Basis.IDENTITY, Vector3(side * 0.9, 2.6 + side * 0.4, 0.0)))
		var elbow: CylinderMesh = arm.duplicate() as CylinderMesh
		elbow.height = 1.0
		surface.append_from(elbow, 0, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(side * 0.55, 1.9 + side * 0.4, 0.0)))
	surface.generate_normals()
	return surface.commit()


## Pole + dark sign board; the neon tubes are a separate emissive part.
static func _sign_frame() -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_box(surface, Vector3(0.3, 6.4, 0.3), Vector3(0.0, 3.2, 0.2))
	_append_box(surface, Vector3(4.4, 2.0, 0.25), Vector3(0.0, 6.8, 0.0))
	surface.generate_normals()
	return surface.commit()


## Frame outline plus two "lettering" bars of unequal length, facing +Z.
static func _neon_tubes() -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bar: Array in [
		[Vector3(4.2, 0.1, 0.08), Vector3(0.0, 7.72, -0.16)], [Vector3(4.2, 0.1, 0.08), Vector3(0.0, 5.88, -0.16)],
		[Vector3(0.1, 1.9, 0.08), Vector3(-2.1, 6.8, -0.16)], [Vector3(0.1, 1.9, 0.08), Vector3(2.1, 6.8, -0.16)],
		[Vector3(3.0, 0.22, 0.08), Vector3(-0.3, 7.15, -0.16)], [Vector3(2.0, 0.22, 0.08), Vector3(0.5, 6.45, -0.16)],
	]:
		_append_box(surface, bar[0], bar[1])
	surface.generate_normals()
	return surface.commit()


static func _append_box(surface: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	surface.append_from(box, 0, Transform3D(Basis.IDENTITY, at))


## Squashed faceted sphere: rock, boulder or bush depending on paint.
static func _rock() -> ArrayMesh:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.3
	sphere.radial_segments = 7
	sphere.rings = 4
	return _baked(sphere, Transform3D(Basis.IDENTITY, Vector3.UP * 0.35))


static func _baked(mesh: PrimitiveMesh, transform: Transform3D) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.append_from(mesh, 0, transform)
	surface.generate_normals()
	return surface.commit()


## Spatially chunked batches so distant groups can be culled by range.
static func _batch_chunks(root: Node3D, node_name: String, mesh: Mesh, paint: Material, transforms: Array[Transform3D]) -> void:
	for start: int in range(0, transforms.size(), CHUNK):
		var slice: Array[Transform3D] = transforms.slice(start, mini(start + CHUNK, transforms.size()))
		TrackDressing.batch(root, node_name, mesh, paint, slice)
		var node: MultiMeshInstance3D = root.get_child(root.get_child_count() - 1) as MultiMeshInstance3D
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.visibility_range_end = PROP_RANGE
