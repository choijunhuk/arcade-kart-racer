class_name TrackArt
extends RefCounted

## Original procedural surfaces and batched scenery; never changes collisions.
const TEXTURE_SIZE: int = 128
const PROP_SPACING: float = 24.0
const PROP_OFFSET: float = 15.0
const PROP_RANGE: float = 160.0
const THEMES: Array[Color] = [Color(0.18, 0.42, 0.18), Color(0.06, 0.12, 0.25), Color(0.65, 0.83, 0.9), Color(0.65, 0.36, 0.15)]
## Fog density per theme (index matches THEMES): clear day, underpass haze, alpine haze, dusty haze.
const FOG_DENSITY: Array[float] = [0.0009, 0.006, 0.0022, 0.0028]
## Sky gradient per theme (index matches THEMES). THEMES are ground/terrain tints; reusing them for
## the sky turned the clear-day circuit green. Ochre keeps its dusty dusk look.
const SKY_TOP: Array[Color] = [Color(0.24, 0.47, 0.82), Color(0.02, 0.03, 0.09), Color(0.36, 0.58, 0.86), Color(0.36, 0.2, 0.08)]
const SKY_HORIZON: Array[Color] = [Color(0.7, 0.83, 0.95), Color(0.16, 0.1, 0.28), Color(0.86, 0.92, 0.98), Color(0.79, 0.62, 0.49)]
## Lamp glow sprite: soft radial falloff, additive, so it reads as light rather than a solid tile.
const LAMP_GLOW_SIZE: float = 2.4
const LAMP_GLOW_TEXTURE_SIZE: int = 64
## The underpass theme reads as night: dim ambient plus batched lamp glow.
const NIGHT_THEME: int = 1
const LAMP_SPACING: float = 26.0
const LAMP_HEIGHT: float = 4.2
const LAMP_LATERAL: float = 8.2
const LAMP_REAL_LIGHT_EVERY: int = 3

## Makes tiled noise with optional bump normals, using an original fixed seed.
static func surface(color: Color, bump: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = PrimitiveArt.material(color)
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
	if theme == NIGHT_THEME:
		_lamps(root, line)
	TrackDressing.install(root, track, line, theme)
	# A track swapped out before its deferred art install runs is no longer in the tree
	# (sandbox/snapshot track switching); skip the quality pass instead of dereferencing null.
	var tree: SceneTree = track.get_tree()
	var settings: Node = tree.root.get_node_or_null("SettingsManager") if tree != null else null
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
	paint.sky_top_color = SKY_TOP[theme]
	paint.sky_horizon_color = SKY_HORIZON[theme]
	paint.ground_bottom_color = THEMES[theme].darkened(0.7)
	paint.sun_angle_max = 3.5
	paint.sun_curve = 0.15
	sky.sky_material = paint
	var environment: Environment = world.environment
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	# Sky-derived ambient/reflections replace the greybox flat/color fallback.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.glow_intensity = 0.85
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 1.6
	environment.ssao_power = 1.0
	environment.fog_light_color = THEMES[theme].lightened(0.3)
	environment.fog_density = FOG_DENSITY[theme]

## Batches lamp posts for the underpass "night" theme: an always-visible
## billboard glow sprite per post plus a real `OmniLight3D` every third post,
## kept out of low/medium tiers by `QualityTier.apply_scene`'s group toggle.
static func _lamps(root: Node3D, line: RacingLine) -> void:
	var shape: QuadMesh = QuadMesh.new()
	shape.size = Vector2(LAMP_GLOW_SIZE, LAMP_GLOW_SIZE)
	var falloff: Gradient = Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var radial: GradientTexture2D = GradientTexture2D.new()
	radial.gradient = falloff
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(0.5, 0.5)
	radial.fill_to = Vector2(0.5, 0.0)
	radial.width = LAMP_GLOW_TEXTURE_SIZE
	radial.height = LAMP_GLOW_TEXTURE_SIZE
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_texture = radial
	glow.emission_enabled = true
	glow.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
	glow.emission = Color(1.0, 0.8, 0.45)
	glow.emission_energy_multiplier = 3.0
	shape.material = glow
	var count: int = ceili(line.length() / LAMP_SPACING)
	var mesh: MultiMesh = MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = shape
	mesh.instance_count = count * 2
	var sprites: MultiMeshInstance3D = MultiMeshInstance3D.new()
	sprites.name = "LampGlowSprites"
	sprites.multimesh = mesh
	sprites.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sprites)
	var lights: Node3D = Node3D.new()
	lights.name = "LampLights"
	root.add_child(lights)
	for index: int in range(count):
		var offset: float = line.length() * float(index) / float(count)
		for side: int in range(2):
			var lateral: float = LAMP_LATERAL if side == 0 else -LAMP_LATERAL
			var at: Vector3 = line.sample(offset) + line.right_at(offset) * lateral + Vector3.UP * LAMP_HEIGHT
			mesh.set_instance_transform(index * 2 + side, Transform3D(Basis.IDENTITY, root.to_local(at)))
			if (index * 2 + side) % LAMP_REAL_LIGHT_EVERY == 0:
				var lamp: OmniLight3D = OmniLight3D.new()
				lamp.light_color = glow.emission
				lamp.light_energy = 1.4
				lamp.omni_range = 11.0
				lamp.add_to_group(QualityTier.DRESSING_LAMP_GROUP)
				lamp.visible = false
				lights.add_child(lamp)
				lamp.global_position = at

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
	white.set_material(PrimitiveArt.material(Color(0.9, 0.95, 1), true))
	red.set_material(PrimitiveArt.material(Color(0.9, 0.12, 0.06)))
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
	shape.material = PrimitiveArt.material(Color(0.5, 0.55, 0.6))
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
