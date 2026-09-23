class_name KartKenneyArt
extends RefCounted

## Kenney "Racing Kit" (CC0) kart visuals: nearest-color model pick, scale-fit
## to the kart's target footprint, and mesh baking so Body/wheels stay single
## MeshInstance3D nodes. Physics/collision are never touched from here.
##
## Body is merged to ONE surface driven by the car-paint `material_override`
## shader (livery + hit flash); the source surfaces survive as vertex-colour
## roles (paint/glass/trim), so the car keeps its two-tone look in one draw.
## Wheels are not behind that shader, so tyre and rim stay separate surfaces
## (rim is surface 1, recoloured per driver by KartLivery).

const MODEL_DIR: String = "res://assets/kenney/racing_kit/"
## Paint-surface reference colors per race car variant (geometry is identical
## across all four; only this surface's albedo differs), used to pick the
## closest match to a kart's `body_color` before we tint it anyway.
const CAR_MODEL_COLORS: Dictionary[StringName, Color] = {
	&"raceCarRed": Color(0.9593, 0.6125, 0.6059),
	&"raceCarGreen": Color(0.5856, 0.7741, 0.6882),
	&"raceCarWhite": Color(0.9755, 0.9772, 0.9843),
	&"raceCarOrange": Color(0.9826, 0.868, 0.5457),
}
const BODY_NODE_NAME: String = "body"
## kart.tscn wheel pivot name -> matching node name inside the source model.
const WHEEL_NODE_NAMES: Dictionary[StringName, String] = {
	&"WheelFL": "wheelFrontLeft",
	&"WheelFR": "wheelFrontRight",
	&"WheelRL": "wheelBackLeft",
	&"WheelRR": "wheelBackRight",
}
## Matches KartVisuals.WHEEL_RADIUS so the existing spin-speed math still
## reads correctly against the new wheel mesh's visual size.
const WHEEL_VISUAL_RADIUS: float = 0.28
## Local Y where the visual body should rest so wheels touch the ground,
## matching PhysicsTuning.hover_height's default (0.35m above the ground
## probe origin at the kart's local Y=0).
const GROUND_CONTACT_Y: float = -0.35

static var _fallback_warned: bool = false
static var _body_cache: Dictionary[StringName, ArrayMesh] = {}
static var _wheel_cache: Dictionary[String, ArrayMesh] = {}
static var _wheel_layout_cache: Dictionary[StringName, Dictionary] = {}
static var _tyre_material: StandardMaterial3D = _make_wheel_material(Color(0.055, 0.055, 0.065), 0.88, 0.0)
static var _rim_material: StandardMaterial3D = _make_wheel_material(Color(0.78, 0.8, 0.83), 0.3, 0.8)


static func _make_wheel_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


## Nearest CC0 paint variant to a kart's body color, by squared RGB distance.
static func pick_car_model(body_color: Color) -> StringName:
	var best_name: StringName = &"raceCarRed"
	var best_distance: float = INF
	for model_name: StringName in CAR_MODEL_COLORS:
		var reference: Color = CAR_MODEL_COLORS[model_name]
		var distance: float = (
			(body_color.r - reference.r) * (body_color.r - reference.r)
			+ (body_color.g - reference.g) * (body_color.g - reference.g)
			+ (body_color.b - reference.b) * (body_color.b - reference.b)
		)
		if distance < best_distance:
			best_distance = distance
			best_name = model_name
	return best_name


## Per-axis scale that fits `source_size` onto `target_size`; degenerate
## (zero-length) source axes fall back to a scale of 1 instead of dividing by zero.
static func fit_scale(source_size: Vector3, target_size: Vector3) -> Vector3:
	return Vector3(
		target_size.x / source_size.x if source_size.x > 0.0 else 1.0,
		target_size.y / source_size.y if source_size.y > 0.0 else 1.0,
		target_size.z / source_size.z if source_size.z > 0.0 else 1.0,
	)


## Local Y to place a mesh's parent node at so its lowest (scaled) point lands on `ground_y`.
static func ground_offset(source_min_y: float, scale_y: float, ground_y: float) -> float:
	return ground_y - source_min_y * scale_y


## Builds (and caches, per kart id) the merged single-surface body mesh, scaled
## to `KartMeshBuilder.target_body_size(data)` and turned 180 degrees so the
## source model's nose (+Z) matches the kart's forward (-Z). Each source
## surface's role is baked into vertex COLOR (r = paint, g = glass, else trim)
## so the one car-paint shader can draw livery, cockpit glass and dark trim in
## a single draw call. Returns null if the source asset can't be loaded, so
## callers can fall back to the procedural chassis.
static func build_body_mesh(data: KartData) -> ArrayMesh:
	if _body_cache.has(data.id):
		return _body_cache[data.id]
	var root: Node3D = _instantiate_model(pick_car_model(data.body_color))
	if root == null:
		return null
	var body_node: MeshInstance3D = root.find_child(BODY_NODE_NAME, true, false) as MeshInstance3D
	if body_node == null or body_node.mesh == null:
		root.free()
		return null
	var source: Mesh = body_node.mesh
	var transform: Transform3D = body_transform(source.get_aabb(), KartMeshBuilder.target_body_size(data))
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	for surface_index: int in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface_index)
		var role: Color = _surface_role(source.surface_get_material(surface_index))
		var base: int = vertices.size()
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var surface_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		for index: int in range(surface_vertices.size()):
			vertices.append(transform * surface_vertices[index])
			normals.append((transform.basis * surface_normals[index]).normalized())
			colors.append(role)
		var surface_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if surface_indices is PackedInt32Array and not (surface_indices as PackedInt32Array).is_empty():
			for index: int in surface_indices as PackedInt32Array:
				indices.append(base + index)
		else:
			for index: int in range(surface_vertices.size()):
				indices.append(base + index)
	var merged_arrays: Array = []
	merged_arrays.resize(Mesh.ARRAY_MAX)
	merged_arrays[Mesh.ARRAY_VERTEX] = vertices
	merged_arrays[Mesh.ARRAY_NORMAL] = normals
	merged_arrays[Mesh.ARRAY_COLOR] = colors
	merged_arrays[Mesh.ARRAY_INDEX] = indices
	var merged: ArrayMesh = ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged_arrays)
	merged.surface_set_material(0, PrimitiveArt.material(data.body_color))
	merged.set_meta(&"vertex_roles", true)
	_wheel_layout_cache[data.id] = _wheel_layout(root, body_node, transform)
	root.free()
	_body_cache[data.id] = merged
	return merged


## Scale-to-footprint, centre on X/Z, rest on Y=0, and face the nose to -Z.
static func body_transform(source_aabb: AABB, target: Vector3) -> Transform3D:
	var scale: Vector3 = fit_scale(source_aabb.size, target)
	var center: Vector3 = source_aabb.position + source_aabb.size * 0.5
	var fit: Transform3D = Transform3D(
		Basis().scaled(scale),
		Vector3(-center.x * scale.x, ground_offset(source_aabb.position.y, scale.y, 0.0), -center.z * scale.z),
	)
	return Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * fit


## Kart-local wheel pivot X/Z (keyed by kart.tscn pivot name) matching the
## source model's wheel wells, captured when that kart's body mesh was built.
static func wheel_layout(data: KartData) -> Dictionary:
	return _wheel_layout_cache.get(data.id, {})


## Builds (and caches) one wheel's mesh, recentered on its own rolling axis
## (so spinning the pivot node doesn't make it orbit), turned like the body and
## scaled to `WHEEL_VISUAL_RADIUS`. Tyres get dark rubber; surface 1 (rim)
## keeps a neutral metal that KartLivery overrides per driver.
static func build_wheel_mesh(pivot_name: StringName) -> ArrayMesh:
	var cache_key: String = String(pivot_name)
	if _wheel_cache.has(cache_key):
		return _wheel_cache[cache_key]
	var node_name: String = WHEEL_NODE_NAMES.get(pivot_name, "")
	if node_name.is_empty():
		return null
	var root: Node3D = _instantiate_model(&"raceCarRed")
	if root == null:
		return null
	var wheel_node: MeshInstance3D = root.find_child(node_name, true, false) as MeshInstance3D
	if wheel_node == null or wheel_node.mesh == null:
		root.free()
		return null
	var source: Mesh = wheel_node.mesh
	var local_aabb: AABB = source.get_aabb()
	var source_radius: float = maxf(local_aabb.size.y, local_aabb.size.z) * 0.5
	var scale: float = WHEEL_VISUAL_RADIUS / source_radius if source_radius > 0.0 else 1.0
	var center: Vector3 = local_aabb.position + local_aabb.size * 0.5
	var transform: Transform3D = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * Transform3D(
		Basis().scaled(Vector3.ONE * scale), center * -scale,
	)
	var merged: ArrayMesh = null
	for surface_index: int in range(source.get_surface_count()):
		var surface_tool: SurfaceTool = SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tool.append_from(source, surface_index, transform)
		surface_tool.set_material(_tyre_material if surface_index == 0 else _rim_material)
		merged = surface_tool.commit(merged)
	root.free()
	_wheel_cache[cache_key] = merged
	return merged


static func _surface_role(material: Material) -> Color:
	var name: String = material.resource_name if material != null else ""
	if name == "glass":
		return Color(0.0, 1.0, 0.0)
	if name == "carTire":
		return Color(0.0, 0.0, 0.0)
	return Color(1.0, 0.0, 0.0)


## Source wheel/body nodes are direct children of the model root.
static func _wheel_layout(root: Node3D, body_node: MeshInstance3D, transform: Transform3D) -> Dictionary:
	var layout: Dictionary = {}
	var to_body: Transform3D = body_node.transform.affine_inverse()
	for pivot_name: StringName in WHEEL_NODE_NAMES:
		var wheel: MeshInstance3D = root.find_child(WHEEL_NODE_NAMES[pivot_name], true, false) as MeshInstance3D
		if wheel == null or wheel.mesh == null:
			continue
		var wheel_aabb: AABB = wheel.mesh.get_aabb()
		var center_in_root: Vector3 = wheel.transform * (wheel_aabb.position + wheel_aabb.size * 0.5)
		var kart_local: Vector3 = transform * (to_body * center_in_root)
		layout[pivot_name] = Vector2(kart_local.x, kart_local.z)
	return layout


static func _instantiate_model(model_name: StringName) -> Node3D:
	var path: String = MODEL_DIR + String(model_name) + ".glb"
	if not ResourceLoader.exists(path):
		_warn_fallback(path)
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		_warn_fallback(path)
		return null
	return scene.instantiate() as Node3D


static func _warn_fallback(path: String) -> void:
	if _fallback_warned:
		return
	_fallback_warned = true
	push_warning("Kenney kart art asset missing or failed to load (%s); falling back to procedural kart visuals." % path)
