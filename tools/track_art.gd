class_name TrackArt
extends RefCounted

## Original procedural surfaces and batched scenery; never changes collisions.
const TEXTURE_SIZE: int = 128
const THEMES: Array[Color] = [Color(0.18, 0.42, 0.18), Color(0.06, 0.12, 0.25), Color(0.65, 0.83, 0.9), Color(0.65, 0.36, 0.15)]
## The underpass theme reads as night: emissive lamp heads plus a few real lights.
const NIGHT_THEME: int = 1
const LAMP_SPACING: float = 22.0
const LAMP_HEIGHT: float = 6.0
## Pole stands just outside the wall; the arm reaches back over the road edge.
const LAMP_POLE_OUTSET: float = 1.4
const LAMP_ARM_LENGTH: float = 2.6
const LAMP_REAL_LIGHT_EVERY: int = 4
const LAMP_COLOR: Color = Color(1.0, 0.78, 0.48)

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
	# A track swapped out before its deferred art install runs is no longer in the tree
	# (sandbox/snapshot track switching); without settings, skip the quality/CC0-art passes.
	var tree: SceneTree = track.get_tree()
	var settings: Node = tree.root.get_node_or_null("SettingsManager") if tree != null else null
	var kenney: bool = settings != null and String(settings.call("get_setting", &"video", &"art_style", "kenney")) == "kenney"
	TrackSky.apply(track, theme)
	TrackBackdrop.install(root, line, theme)
	ThemeProps.install(root, track, line, theme, kenney)
	WorldMaterials.apply(track, theme)
	if theme == NIGHT_THEME:
		_lamps(root, track, line)
	TrackDressing.install(root, track, line, theme)
	if settings == null:
		return
	if kenney:
		TrackKenneyProps.install(root, track, line, theme)
	QualityTier.apply_scene(track, int(settings.call("get_setting", &"video", &"particle_quality", 2)))

## Night street lamps: pole + arm + emissive head batched in three draws, and a
## real `OmniLight3D` under every fourth head, shown only on the highest tier
## (`QualityTier.apply_scene` toggles the group). Staggered left/right.
static func _lamps(root: Node3D, track: Node3D, line: RacingLine) -> void:
	var width: float = float(track.get("road_width")) if track.has_method("bank_at") else 14.0
	var pole_lateral: float = width * 0.5 + LAMP_POLE_OUTSET
	var metal: StandardMaterial3D = PrimitiveArt.material(Color(0.16, 0.17, 0.2))
	var head_paint: StandardMaterial3D = PrimitiveArt.material(LAMP_COLOR, true)
	head_paint.emission_energy_multiplier = 6.0
	var pole: BoxMesh = BoxMesh.new()
	pole.size = Vector3(0.2, LAMP_HEIGHT, 0.2)
	var arm: BoxMesh = BoxMesh.new()
	arm.size = Vector3(LAMP_ARM_LENGTH, 0.14, 0.14)
	var head: BoxMesh = BoxMesh.new()
	head.size = Vector3(1.1, 0.12, 0.42)
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var lights: Node3D = Node3D.new()
	lights.name = "LampLights"
	root.add_child(lights)
	var count: int = ceili(line.length() / LAMP_SPACING)
	for index: int in range(count):
		var offset: float = line.length() * float(index) / float(count)
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var right: Vector3 = line.right_at(offset) * side
		var basis: Basis = Basis.looking_at(-right, Vector3.UP)
		var foot: Vector3 = line.sample(offset) + right * pole_lateral
		var arm_at: Vector3 = foot - right * (LAMP_ARM_LENGTH * 0.5) + Vector3.UP * LAMP_HEIGHT
		var head_at: Vector3 = foot - right * LAMP_ARM_LENGTH + Vector3.UP * (LAMP_HEIGHT - 0.12)
		poles.append(Transform3D(basis, root.to_local(foot + Vector3.UP * LAMP_HEIGHT * 0.5)))
		arms.append(Transform3D(basis.rotated(Vector3.UP, PI * 0.5), root.to_local(arm_at)))
		heads.append(Transform3D(basis.rotated(Vector3.UP, PI * 0.5), root.to_local(head_at)))
		if index % LAMP_REAL_LIGHT_EVERY == 0:
			var lamp: OmniLight3D = OmniLight3D.new()
			lamp.light_color = LAMP_COLOR
			lamp.light_energy = 3.0
			lamp.omni_range = 16.0
			lamp.omni_attenuation = 1.2
			lamp.add_to_group(QualityTier.DRESSING_LAMP_GROUP)
			lamp.visible = false
			lights.add_child(lamp)
			lamp.global_position = head_at + Vector3.DOWN * 0.6
	TrackDressing.batch(root, "LampPoles", pole, metal, poles)
	TrackDressing.batch(root, "LampArms", arm, metal, arms)
	TrackDressing.batch(root, "LampHeads", head, head_paint, heads)
