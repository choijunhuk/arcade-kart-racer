class_name TrackArt
extends RefCounted

## Original procedural surfaces and batched scenery; never changes collisions.
const TEXTURE_SIZE: int = 128
const PROP_SPACING: float = 24.0
const PROP_OFFSET: float = 15.0
const PROP_RANGE: float = 160.0
const THEMES: Array[Color] = [Color(0.18, 0.42, 0.18), Color(0.06, 0.12, 0.25), Color(0.65, 0.83, 0.9), Color(0.65, 0.36, 0.15)]

## Makes tiled noise with optional bump normals, using an original fixed seed.
static func surface(color: Color, bump: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = KartMeshBuilder.material(color)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 13013
	noise.frequency = 0.15
	var texture: NoiseTexture2D = NoiseTexture2D.new()
	texture.width = TEXTURE_SIZE
	texture.height = TEXTURE_SIZE
	texture.seamless = true
	texture.noise = noise
	material.albedo_texture = texture
	material.roughness = 0.9
	material.metallic = 0.0
	if bump:
		var normal: NoiseTexture2D = texture.duplicate() as NoiseTexture2D
		normal.as_normal_map = true
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 0.3
	return material

## Adds themed sky, props and road markings after authored geometry exists.
static func install(track: Node3D) -> void:
	var line: RacingLine = track.call("get_racing_line") as RacingLine
	if line == null or line.length() <= 0.0:
		return
	var theme: int = 0
	for index: int in range(2, 5):
		if String(track.scene_file_path).contains("track_0%d" % index):
			theme = index - 1
	var root: Node3D = Node3D.new()
	root.name = "ProceduralArt"
	track.add_child(root)
	_sky(root, theme)
	_props(root, line, theme)
	_markings(root, track, line)
	_posts(root, line)
	var settings: Node = track.get_tree().root.get_node_or_null("SettingsManager")
	if settings != null:
		QualityTier.apply_scene(track, int(settings.call("get_setting", &"video", &"particle_quality", 2)))

static func _sky(root: Node3D, theme: int) -> void:
	# Reuse authored WorldEnvironment, avoiding competing active environments.
	var environments: Array[Node] = root.get_parent().find_children("*", "WorldEnvironment", true, false)
	if environments.is_empty():
		return
	var world: WorldEnvironment = environments[0] as WorldEnvironment
	world.environment = world.environment.duplicate() as Environment
	var sky: Sky = Sky.new()
	var paint: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	paint.sky_top_color = THEMES[theme].darkened(0.45)
	paint.sky_horizon_color = THEMES[theme].lightened(0.4)
	paint.ground_bottom_color = THEMES[theme].darkened(0.7)
	sky.sky_material = paint
	world.environment.sky = sky
	world.environment.background_mode = Environment.BG_SKY
	world.environment.fog_light_color = THEMES[theme].lightened(0.3)
	world.environment.fog_density = 0.0015

static func _props(root: Node3D, line: RacingLine, theme: int) -> void:
	var shape: CylinderMesh = CylinderMesh.new()
	shape.radial_segments = 6
	shape.top_radius = 0.0 if theme == 0 else 0.6
	shape.bottom_radius = 2.0 if theme == 0 else 1.2
	shape.height = 5.0 if theme < 2 else 2.5
	shape.material = surface(THEMES[theme], true)
	var count: int = ceili(line.length() / PROP_SPACING)
	# Small batches allow distance culling instead of an all-track AABB.
	for batch: int in range(ceili(float(count) / 8.0)):
		var mesh: MultiMesh = MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = shape
		mesh.instance_count = mini(8, count - batch * 8)
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.multimesh = mesh
		node.visibility_range_end = PROP_RANGE
		root.add_child(node)
		var origin: Vector3 = line.sample(float(batch * 8) * PROP_SPACING)
		node.global_position = origin
		for index: int in range(mesh.instance_count):
			var offset: float = float(batch * 8 + index) * PROP_SPACING
			var at: Vector3 = line.sample(offset) + line.right_at(offset) * PROP_OFFSET + Vector3.UP * shape.height * 0.5
			mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, at - origin))


static func _markings(root: Node3D, track: Node3D, line: RacingLine) -> void:
	var width: float = float(track.get("road_width")) if track.has_method("bank_at") else 14.0
	var white: SurfaceTool = SurfaceTool.new()
	var red: SurfaceTool = SurfaceTool.new()
	white.begin(Mesh.PRIMITIVE_TRIANGLES)
	red.begin(Mesh.PRIMITIVE_TRIANGLES)
	white.set_material(KartMeshBuilder.material(Color(0.9, 0.95, 1), true))
	red.set_material(KartMeshBuilder.material(Color(0.9, 0.12, 0.06)))
	var count: int = ceili(line.length() / 4.0)
	for index: int in range(count):
		var a: float = line.length() * float(index) / float(count)
		var b: float = line.length() * float(index + 1) / float(count)
		if track.has_method("bank_at") and bool(track.call("is_gap", (line.sample(a) + line.sample(b)) * 0.5)):
			continue
		for side: float in [-1.0, 1.0]:
			_strip(white, root, track, line, a, b, side * (width * 0.5 - 0.3), 0.12)
			_strip(white if index % 2 == 0 else red, root, track, line, a, b, side * width * 0.5, 0.25)
	for lane: int in range(int(width)):
		for row: int in range(2):
			_strip(white if (lane + row) % 2 == 0 else red, root, track, line, float(row), float(row + 1), float(lane) - width * 0.5 + 0.5, 0.5)
	for surface_tool: SurfaceTool in [white, red]:
		surface_tool.generate_normals()
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = surface_tool.commit()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)

static func _strip(surface_tool: SurfaceTool, root: Node3D, track: Node3D, line: RacingLine, a: float, b: float, lateral: float, half: float) -> void:
	var ra: Vector3 = line.right_at(a)
	var rb: Vector3 = line.right_at(b)
	if track.has_method("bank_at"):
		ra = ra.rotated(line.tangent_at(a), float(track.call("bank_at", a)))
		rb = rb.rotated(line.tangent_at(b), float(track.call("bank_at", b)))
	var up: Vector3 = Vector3.UP * 0.23
	var start: Vector3 = line.sample(a) + up
	var end: Vector3 = line.sample(b) + up
	for vertex: Vector3 in [start + ra * (lateral - half), end + rb * (lateral - half), end + rb * (lateral + half), start + ra * (lateral - half), end + rb * (lateral + half), start + ra * (lateral + half)]:
		surface_tool.add_vertex(root.to_local(vertex))


static func _posts(root: Node3D, line: RacingLine) -> void:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = Vector3(0.15, 1.4, 0.15)
	shape.material = KartMeshBuilder.material(Color(0.5, 0.55, 0.6))
	var count: int = ceili(line.length() / 8.0)
	var mesh: MultiMesh = MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = shape
	mesh.instance_count = count * 2
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	for index: int in range(count):
		var offset: float = line.length() * float(index) / float(count)
		for side: int in range(2):
			var at: Vector3 = line.sample(offset) + line.right_at(offset) * (7.5 if side == 0 else -7.5) + Vector3.UP * 0.7
			mesh.set_instance_transform(index * 2 + side, Transform3D(Basis.IDENTITY, root.to_local(at)))
