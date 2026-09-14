class_name KartKenneyArt
extends RefCounted

## Kenney "Racing Kit" (CC0) kart visuals: nearest-color model pick, scale-fit
## to the kart's target footprint, and mesh baking so Body/wheels stay single
## MeshInstance3D nodes. Physics/collision are never touched from here.
##
## Body is merged to ONE surface/material because `KartVisuals` always drives
## Body through a single `material_override` shader (hit-flash); a multi-
## material body mesh would just get flattened to one color at runtime anyway,
## so merging keeps the same look while cutting the draw call to one.
## Wheels are not behind that shader, so their two source materials (rim/tire)
## are kept separate.

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


## Builds (and caches, per kart id) the merged single-surface body mesh, tinted
## to `data.body_color` and scaled to `KartMeshBuilder.target_body_size(data)`.
## Returns null if the source asset can't be loaded, so callers can fall back
## to the procedural chassis.
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
	var local_aabb: AABB = source.get_aabb()
	var target: Vector3 = KartMeshBuilder.target_body_size(data)
	var scale: Vector3 = fit_scale(local_aabb.size, target)
	var center_x: float = local_aabb.position.x + local_aabb.size.x * 0.5
	var center_z: float = local_aabb.position.z + local_aabb.size.z * 0.5
	var translate_y: float = ground_offset(local_aabb.position.y, scale.y, 0.0)
	var transform: Transform3D = Transform3D(
		Basis().scaled(scale),
		Vector3(-center_x * scale.x, translate_y, -center_z * scale.z),
	)
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface_index: int in range(source.get_surface_count()):
		surface_tool.append_from(source, surface_index, transform)
	surface_tool.set_material(PrimitiveArt.material(data.body_color))
	var merged: ArrayMesh = surface_tool.commit()
	root.free()
	_body_cache[data.id] = merged
	return merged


## Builds (and caches) one wheel's merged mesh, recentered on its own rolling
## axis (so spinning the pivot node doesn't make it orbit) and scaled to
## `WHEEL_VISUAL_RADIUS`. Wheel geometry/material is identical across paint
## variants, so any one source model works for all four wheel pivots.
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
	var transform: Transform3D = Transform3D(Basis().scaled(Vector3.ONE * scale), center * -scale)
	var merged: ArrayMesh = null
	for surface_index: int in range(source.get_surface_count()):
		var surface_tool: SurfaceTool = SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tool.append_from(source, surface_index, transform)
		surface_tool.set_material(source.surface_get_material(surface_index))
		merged = surface_tool.commit(merged)
	root.free()
	_wheel_cache[cache_key] = merged
	return merged


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
