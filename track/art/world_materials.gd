class_name WorldMaterials
extends RefCounted

## Phase 19 themed surface shaders (road, off-road ground, barriers) and the
## pass that re-skins an already-built track. Visual only: it sets
## `material_override`/instance parameters on existing meshes and never touches
## collision shapes, so authored geometry and physics stay byte-identical.

const ROAD_SHADER: Shader = preload("res://assets/shaders/world/road.gdshader")
const TERRAIN_SHADER: Shader = preload("res://assets/shaders/world/terrain.gdshader")
const WALL_SHADER: Shader = preload("res://assets/shaders/world/wall.gdshader")
const ROAD_GROUP: StringName = &"road_visual"
const MAIN_ROAD_META: StringName = &"main_road"
const RIDGELINE: int = 0
const NIGHT: int = 1
const GLACIER: int = 2
const CANYON: int = 3

## Road look per theme: clean asphalt, wet neon asphalt, packed snow, red clay.
const ROAD_PARAMS: Array[Dictionary] = [
	{},
	{
		"base_color": Color(0.15, 0.155, 0.18), "patch_color": Color(0.19, 0.19, 0.22),
		"wear_color": Color(0.05, 0.05, 0.06), "wetness": 0.75, "line_color": Color(0.35, 0.95, 1.0),
		"line_emission": 0.9, "kerb_color_a": Color(0.95, 0.15, 0.6), "kerb_color_b": Color(0.12, 0.12, 0.16),
		"roughness_base": 0.7,
	},
	{
		"base_color": Color(0.8, 0.86, 0.93), "patch_color": Color(0.9, 0.93, 0.97),
		"wear_color": Color(0.55, 0.66, 0.8), "wear_amount": 0.6, "grain": 0.12, "speckle": 0.15,
		"streak_stretch": 6.0, "line_color": Color(0.1, 0.35, 0.85), "kerb_color_a": Color(0.12, 0.38, 0.85),
		"kerb_color_b": Color(0.96, 0.97, 1.0), "roughness_base": 0.6, "ice_sheen": 0.8, "paint_fade": 0.4,
	},
	{
		"base_color": Color(0.56, 0.3, 0.17), "patch_color": Color(0.64, 0.38, 0.21),
		"wear_color": Color(0.42, 0.22, 0.13), "wear_amount": 0.5, "grain": 0.3, "speckle": 0.5,
		"streak_stretch": 4.0, "line_color": Color(0.96, 0.9, 0.78), "paint_fade": 0.55,
		"roughness_base": 0.95, "centre_line": 0.0, "bump_strength": 1.1,
	},
]
## Ground beyond the road: meadow, dark city lot, snowfield, desert sand.
const TERRAIN_PARAMS: Array[Dictionary] = [
	{"mow_stripes": 1.0},
	{
		"color_a": Color(0.07, 0.075, 0.09), "color_b": Color(0.1, 0.1, 0.12),
		"color_accent": Color(0.12, 0.1, 0.16), "roughness_value": 0.6,
	},
	{
		"color_a": Color(0.86, 0.91, 0.97), "color_b": Color(0.95, 0.97, 1.0),
		"color_accent": Color(0.7, 0.8, 0.92), "accent_amount": 0.35, "detail": 0.08, "sparkle": 1.0,
		"roughness_value": 0.75,
	},
	{
		"color_a": Color(0.82, 0.58, 0.36), "color_b": Color(0.88, 0.66, 0.42),
		"color_accent": Color(0.7, 0.42, 0.24), "accent_amount": 0.45, "detail": 0.18, "ripple": 1.0,
	},
]
## Barriers: painted concrete, neon night concrete, glacier ice, canyon rock.
const WALL_PARAMS: Array[Dictionary] = [
	{"style": 0},
	{"style": 1, "color_a": Color(0.07, 0.075, 0.09), "glow_color": Color(0.15, 0.85, 1.0), "glow_energy": 3.0},
	{"style": 2, "color_a": Color(0.78, 0.9, 0.98), "color_b": Color(0.3, 0.58, 0.85), "color_c": Color(0.96, 0.99, 1.0)},
	{
		"style": 3, "color_a": Color(0.66, 0.33, 0.18), "color_b": Color(0.8, 0.46, 0.25),
		"color_c": Color(0.93, 0.74, 0.52), "bump_strength": 1.0,
	},
]

static var _cache: Dictionary = {}


static func road(theme: int) -> ShaderMaterial:
	return _material("road", ROAD_SHADER, ROAD_PARAMS, theme)


static func terrain(theme: int) -> ShaderMaterial:
	return _material("terrain", TERRAIN_SHADER, TERRAIN_PARAMS, theme)


static func wall(theme: int) -> ShaderMaterial:
	return _material("wall", WALL_SHADER, WALL_PARAMS, theme)


## Off-road patch tinted towards its terrain colour (dirt, sand, ice sheets).
static func patch(color: Color) -> ShaderMaterial:
	var key: String = "patch|%s" % color
	if _cache.has(key):
		return _cache[key]
	var paint: ShaderMaterial = ShaderMaterial.new()
	paint.shader = TERRAIN_SHADER
	for pair: Array in [[&"color_a", color.darkened(0.12)], [&"color_b", color.lightened(0.08)], [&"color_accent", color.darkened(0.3)]]:
		paint.set_shader_parameter(pair[0], pair[1])
	paint.set_shader_parameter(&"detail", 0.35)
	_cache[key] = paint
	return paint


## Re-skins road ribbons, barriers, off-road patches and structural slabs.
static func apply(track: Node3D, theme: int) -> void:
	var road_paint: ShaderMaterial = road(theme)
	var wall_paint: ShaderMaterial = wall(theme)
	var grid_lateral: float = ContentTrack.GRID_LATERAL if track is ContentTrack else 1.1
	var line: RacingLine = track.call("get_racing_line") as RacingLine
	for node: Node in track.find_children("*", "MeshInstance3D", true, false):
		if not node.is_in_group(ROAD_GROUP):
			continue
		var visual: MeshInstance3D = node as MeshInstance3D
		visual.material_override = road_paint
		var main: bool = bool(visual.get_meta(MAIN_ROAD_META, false))
		visual.set_instance_shader_parameter(&"track_length", line.length() if main and line != null else 0.0)
		visual.set_instance_shader_parameter(&"grid_lateral", grid_lateral)
	var geometry: Node = track.get_node_or_null("Geometry")
	if geometry != null:
		_skin_geometry(track, geometry, wall_paint, theme)
	var zones: Node = track.get_node_or_null("OffroadZones")
	if zones != null:
		for zone: Node in zones.get_children():
			var surface: MeshInstance3D = zone.get_node_or_null("Surface") as MeshInstance3D
			var data: TerrainData = zone.get("terrain") as TerrainData
			if surface != null and data != null:
				surface.material_override = patch(data.particle_color)


static func _skin_geometry(track: Node3D, geometry: Node, wall_paint: ShaderMaterial, theme: int) -> void:
	var wall_source: Variant = track.get("wall_material")
	var road_source: Variant = track.get("road_material")
	for child: Node in geometry.get_children():
		var visual: MeshInstance3D = child as MeshInstance3D
		if visual == null or visual.mesh == null or visual.is_in_group(ROAD_GROUP):
			continue
		var source: Material = visual.mesh.surface_get_material(0)
		var bounds: AABB = visual.mesh.get_aabb()
		if source != null and source == wall_source:
			visual.material_override = wall_paint
			visual.set_instance_shader_parameter(&"wall_bottom", bounds.position.y)
			visual.set_instance_shader_parameter(&"wall_height", bounds.size.y)
			visual.set_instance_shader_parameter(&"wall_glow", 1.0 if bounds.size.y > 1.0 else 0.0)
		elif source != null and source == road_source:
			# Structural slabs (tunnel roof, canyon basin) read as barrier/ground.
			visual.material_override = terrain(theme) if bounds.size.y <= 2.0 and theme == CANYON else wall_paint
			visual.set_instance_shader_parameter(&"wall_bottom", bounds.position.y)
			visual.set_instance_shader_parameter(&"wall_height", bounds.size.y)
			visual.set_instance_shader_parameter(&"wall_glow", 0.0)


static func _material(kind: String, shader: Shader, table: Array[Dictionary], theme: int) -> ShaderMaterial:
	var index: int = clampi(theme, 0, table.size() - 1)
	var key: String = "%s|%d" % [kind, index]
	if _cache.has(key):
		return _cache[key]
	var paint: ShaderMaterial = ShaderMaterial.new()
	paint.shader = shader
	var params: Dictionary = table[index]
	# Colors stay Color so `source_color` uniforms get their sRGB->linear conversion.
	for name: String in params:
		paint.set_shader_parameter(StringName(name), params[name])
	_cache[key] = paint
	return paint
