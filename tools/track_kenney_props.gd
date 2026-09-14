class_name TrackKenneyProps
extends RefCounted

## Kenney "Racing Kit" (CC0) trackside dressing (guardrails, gantry, pylons, trees,
## stands, pits). Visual only, batched; collision (`tools/track_builder.gd`) untouched.

const MODEL_DIR: String = "res://assets/kenney/racing_kit/"
## Matches content_track.gd's wall lateral offset formula exactly, so
## guardrail props align with the (untouched) wall collision.
const WALL_LATERAL_MARGIN: float = 1.0
const BARRIER_STEP: float = 1.05
const BARRIER_TARGET_HEIGHT: float = 0.55
const PYLON_STEP: float = 10.0
const PYLON_CURVATURE_MIN: float = 0.02
const PYLON_TARGET_HEIGHT: float = 0.7
const TREE_STEP: float = 22.0
const TREE_OFFSET: float = 15.0
const TREE_LARGE_TARGET_HEIGHT: float = 6.0
const TREE_SMALL_TARGET_HEIGHT: float = 3.5
const LIGHT_POST_TARGET_HEIGHT: float = 4.5
const GANTRY_TARGET_HEIGHT: float = 6.0
const FLAG_TARGET_HEIGHT: float = 1.4
const GRID_TARGET_LENGTH: float = 2.0
const STAND_TARGET_HEIGHT: float = 2.6
const STAND_OUTSET: float = 9.5
const PITS_TARGET_LENGTH: float = 6.0
const PITS_OUTSET: float = 22.0
## Min clearance beyond road half width for scattered props (sightlines).
const PLACEMENT_MARGIN: float = 2.0
const NIGHT_THEME: int = 1
const GLACIER_THEME: int = 2
const OCHRE_THEME: int = 3
## The kit's shared foliage swatch (also its raceCarGreen paint) reads as
## washed-out blue-teal under this project's sky-lit day environment; retint
## it to a properly saturated green per non-Glacier theme (Glacier's icy tint
## is left alone -- it suits the frozen theme).
const KIT_FOLIAGE_COLOR: Color = Color(0.5856, 0.7741, 0.6882)
const KIT_FOLIAGE_EPSILON: float = 0.02
const FOLIAGE_TINTS: Dictionary[int, Color] = {
	0: Color(0.16, 0.4, 0.16),
	1: Color(0.14, 0.3, 0.22),
	3: Color(0.32, 0.36, 0.14),
}

static var _fallback_warned: bool = false
static var _mesh_cache: Dictionary[String, ArrayMesh] = {}


## True when a lateral offset from the racing line clears the road (plus a
## safety margin) on either side -- keeps scattered props out of sightlines.
static func is_clear_of_racing_line(lateral_offset: float, road_half_width: float, margin: float) -> bool:
	return absf(lateral_offset) >= road_half_width + margin


## Adds every Kenney prop pass; called by TrackArt.install() after
## TrackDressing's own procedural dressing is in place.
static func install(root: Node3D, track: Node3D, line: RacingLine, theme: int) -> void:
	var width: float = float(track.get("road_width")) if track.has_method("bank_at") else 14.0
	var half_width: float = width * 0.5
	_guardrails(root, track, line, width)
	_start_finish(root, line, width, theme)
	_pylons(root, track, line, half_width)
	_perimeter(root, track, line, half_width, theme)
	_main_straight(root, line, half_width, theme)
	_pits(root, line, half_width)


## Low guardrail dressing along the outer edge, aligned to the wall's own
## lateral position (content_track.gd: `(road_width + 1.0) * 0.5 * side`).
## Alternates red/white like the existing curb striping.
static func _guardrails(root: Node3D, track: Node3D, line: RacingLine, width: float) -> void:
	var red_mesh: ArrayMesh = _load_prop_mesh("barrierRed", BARRIER_TARGET_HEIGHT)
	var white_mesh: ArrayMesh = _load_prop_mesh("barrierWhite", BARRIER_TARGET_HEIGHT)
	if red_mesh == null or white_mesh == null:
		return
	var lateral_offset: float = (width + WALL_LATERAL_MARGIN) * 0.5
	var count: int = ceili(line.length() / BARRIER_STEP)
	var red_transforms: Array[Transform3D] = []
	var white_transforms: Array[Transform3D] = []
	for index: int in range(count):
		var offset: float = float(index) * BARRIER_STEP
		var center: Vector3 = line.sample(offset)
		if track.has_method("is_gap") and bool(track.call("is_gap", center)):
			continue
		var basis: Basis = Basis.looking_at(line.tangent_at(offset), Vector3.UP)
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = center + line.right_at(offset) * (lateral_offset * side)
			var transforms: Array[Transform3D] = red_transforms if index % 2 == 0 else white_transforms
			transforms.append(Transform3D(basis, root.to_local(at)))
	_batch(root, "KenneyGuardrailRed", red_mesh, red_transforms)
	_batch(root, "KenneyGuardrailWhite", white_mesh, white_transforms)


## Overhead start/finish gantry sized to the road width, checkered flags at
## either side of the line, and start-grid decals along the racing surface.
static func _start_finish(root: Node3D, line: RacingLine, width: float, theme: int) -> void:
	var gantry_model: String = "overheadRoundColored" if theme == NIGHT_THEME else "overheadLights"
	var gantry_mesh: ArrayMesh = _load_prop_mesh(gantry_model, 0.0, true, width)
	if gantry_mesh != null:
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "KenneyStartGantry"
		node.mesh = gantry_mesh
		var basis: Basis = Basis.looking_at(line.tangent_at(0.0), Vector3.UP)
		var at: Vector3 = line.sample(0.0) + Vector3.UP * (GANTRY_TARGET_HEIGHT * 0.5)
		node.transform = Transform3D(basis, root.to_local(at))
		root.add_child(node)
	var flag_mesh: ArrayMesh = _load_prop_mesh("flagCheckers", FLAG_TARGET_HEIGHT)
	if flag_mesh != null:
		var flag_transforms: Array[Transform3D] = []
		var basis: Basis = Basis.looking_at(line.tangent_at(0.0), Vector3.UP)
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = line.sample(0.0) + line.right_at(0.0) * (width * 0.5 + 0.6) * side
			flag_transforms.append(Transform3D(basis, root.to_local(at)))
		_batch(root, "KenneyFinishFlags", flag_mesh, flag_transforms)
	var grid_mesh: ArrayMesh = _load_prop_mesh("roadStartPositions", 0.0, true, width * 0.92, GRID_TARGET_LENGTH)
	if grid_mesh != null:
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "KenneyStartGrid"
		node.mesh = grid_mesh
		var basis: Basis = Basis.looking_at(line.tangent_at(0.0), Vector3.UP)
		var at: Vector3 = line.sample(GRID_TARGET_LENGTH * 0.5) + Vector3.UP * 0.03
		node.transform = Transform3D(basis, root.to_local(at))
		root.add_child(node)


## A pylon at every sharp corner's outside apex, complementing (not
## replacing) TrackDressing's hairpin hazard signs.
static func _pylons(root: Node3D, track: Node3D, line: RacingLine, half_width: float) -> void:
	var mesh: ArrayMesh = _load_prop_mesh("pylon", PYLON_TARGET_HEIGHT)
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	var count: int = ceili(line.length() / PYLON_STEP)
	var last_offset: float = -1000.0
	for index: int in range(count):
		var offset: float = float(index) * PYLON_STEP
		var curvature: float = line.curvature_at(offset)
		if absf(curvature) < PYLON_CURVATURE_MIN or offset - last_offset < PYLON_STEP * 0.9:
			continue
		if track.has_method("is_gap") and bool(track.call("is_gap", line.sample(offset))):
			continue
		last_offset = offset
		var outside: float = signf(curvature)
		var at: Vector3 = line.sample(offset) + line.right_at(offset) * (outside * (half_width + 1.2))
		transforms.append(Transform3D(Basis(), root.to_local(at)))
	_batch(root, "KenneyPylons", mesh, transforms)


## Trees and lampposts scattered outside the racing line's clearance margin;
## density/species follow the track theme (fewer trees on Glacier, lampposts
## emphasized on the night Lumen track).
static func _perimeter(root: Node3D, track: Node3D, line: RacingLine, half_width: float, theme: int) -> void:
	var tree_step: float = TREE_STEP * 1.6 if theme == GLACIER_THEME else TREE_STEP
	var use_small_trees: bool = theme == GLACIER_THEME
	var tree_model: String = "treeSmall" if use_small_trees else "treeLarge"
	var tree_height: float = TREE_SMALL_TARGET_HEIGHT if use_small_trees else TREE_LARGE_TARGET_HEIGHT
	var tree_mesh: ArrayMesh = _load_prop_mesh(tree_model, tree_height, true, 0.0, 0.0, FOLIAGE_TINTS.get(theme, Color(0, 0, 0, 0)))
	var light_mesh: ArrayMesh = _load_prop_mesh("lightPostModern", LIGHT_POST_TARGET_HEIGHT)
	var tree_transforms: Array[Transform3D] = []
	var light_transforms: Array[Transform3D] = []
	var count: int = ceili(line.length() / tree_step)
	for index: int in range(count):
		var offset: float = float(index) * tree_step
		var center: Vector3 = line.sample(offset)
		if track.has_method("is_gap") and bool(track.call("is_gap", center)):
			continue
		for side: float in [-1.0, 1.0]:
			var lateral: float = TREE_OFFSET * side
			if not is_clear_of_racing_line(lateral, half_width, PLACEMENT_MARGIN):
				continue
			var at: Vector3 = center + line.right_at(offset) * lateral
			var xf: Transform3D = Transform3D(Basis(), root.to_local(at))
			if theme == NIGHT_THEME and (index + int(side)) % 2 == 0:
				light_transforms.append(xf)
			else:
				tree_transforms.append(xf)
	if tree_mesh != null:
		_batch(root, "KenneyTrees", tree_mesh, tree_transforms)
	if light_mesh != null:
		_batch(root, "KenneyLightPosts", light_mesh, light_transforms)


## Grandstand/tent/billboard dressing along the lap's longest straight;
## Ochre favors tent/billboard, other themes get the grandstand.
static func _main_straight(root: Node3D, line: RacingLine, half_width: float, theme: int) -> void:
	var straight: Vector2 = _longest_straight(line)
	if straight.y < TREE_STEP:
		return
	var model_name: String = "tent" if theme == OCHRE_THEME else "grandStand"
	var mesh: ArrayMesh = _load_prop_mesh(model_name, STAND_TARGET_HEIGHT)
	var billboard_mesh: ArrayMesh = _load_prop_mesh("billboard", STAND_TARGET_HEIGHT * 0.9) if theme == OCHRE_THEME else null
	if mesh == null:
		return
	var count: int = clampi(int(straight.y / 16.0), 1, 6)
	var transforms: Array[Transform3D] = []
	var billboard_transforms: Array[Transform3D] = []
	for index: int in range(count):
		var offset: float = straight.x + straight.y * (float(index) + 0.5) / float(count)
		var basis: Basis = Basis.looking_at(-line.tangent_at(offset), Vector3.UP)
		var at: Vector3 = line.sample(offset) + line.right_at(offset) * (half_width + STAND_OUTSET)
		transforms.append(Transform3D(basis, root.to_local(at)))
		if billboard_mesh != null and index % 2 == 0:
			var billboard_at: Vector3 = line.sample(offset) + line.right_at(offset) * (half_width + STAND_OUTSET - 3.0) + Vector3.UP * (STAND_TARGET_HEIGHT * 0.35)
			billboard_transforms.append(Transform3D(basis, root.to_local(billboard_at)))
	_batch(root, "KenneyStands", mesh, transforms)
	if billboard_mesh != null:
		_batch(root, "KenneyBillboards", billboard_mesh, billboard_transforms)


## One pits garage, tucked well clear of the racing line near the start.
static func _pits(root: Node3D, line: RacingLine, half_width: float) -> void:
	var mesh: ArrayMesh = _load_prop_mesh("pitsGarage", 0.0, true, PITS_TARGET_LENGTH)
	if mesh == null:
		return
	var lateral: float = half_width + PITS_OUTSET
	var offset: float = line.length() * 0.03
	var at: Vector3 = line.sample(offset) + line.right_at(offset) * lateral
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "KenneyPitsGarage"
	node.mesh = mesh
	var basis: Basis = Basis.looking_at(-line.right_at(offset), Vector3.UP)
	node.transform = Transform3D(basis, root.to_local(at))
	root.add_child(node)


static func _longest_straight(line: RacingLine) -> Vector2:
	const STEP: float = 4.0
	const CURVATURE_MAX: float = 0.006
	var count: int = ceili(line.length() / STEP)
	var best_start: float = 0.0
	var best_len: float = 0.0
	var run_start: float = 0.0
	var in_run: bool = false
	for index: int in range(count):
		var offset: float = float(index) * STEP
		var straight: bool = absf(line.curvature_at(offset)) < CURVATURE_MAX
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


static func _batch(root: Node3D, node_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
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
	root.add_child(node)


## Loads one Kenney model, merges it (grouped by material, so a multi-part
## prop still costs one draw call per distinct material) and bakes it into a
## single origin: horizontally centered, resting on Y=0, at `target_height`
## (uniform scale from the model's own bounding box) or `target_width`/
## `target_length` when a footprint dimension matters more than height (the
## overhead gantry and the start-grid strip). Cached per (model, target) pair.
## Returns null (after a one-time warning) if the asset can't be loaded.
static func _load_prop_mesh(
	model_name: String,
	target_height: float = 0.0,
	recenter_horizontal: bool = true,
	target_width: float = 0.0,
	target_length: float = 0.0,
	foliage_tint: Color = Color(0.0, 0.0, 0.0, 0.0),
) -> ArrayMesh:
	var cache_key: String = "%s|%.3f|%s|%.3f|%.3f|%s" % [model_name, target_height, recenter_horizontal, target_width, target_length, foliage_tint]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
	var path: String = MODEL_DIR + model_name + ".glb"
	if not ResourceLoader.exists(path):
		_warn_fallback(path)
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		_warn_fallback(path)
		return null
	var root: Node3D = scene.instantiate() as Node3D
	var entries: Array[Dictionary] = []
	_collect(root, Transform3D.IDENTITY, entries)
	var combined_min: Vector3 = Vector3.INF
	var combined_max: Vector3 = -Vector3.INF
	for entry: Dictionary in entries:
		combined_min = combined_min.min(entry["min"])
		combined_max = combined_max.max(entry["max"])
	root.free()
	if entries.is_empty():
		return null
	var size: Vector3 = combined_max - combined_min
	var scale: float = 1.0
	if target_height > 0.0 and size.y > 0.0:
		scale = target_height / size.y
	elif target_width > 0.0 and size.x > 0.0:
		scale = target_width / size.x
	elif target_length > 0.0 and size.z > 0.0:
		scale = target_length / size.z
	var base: Vector3 = Vector3(
		(combined_min.x + combined_max.x) * 0.5 if recenter_horizontal else 0.0,
		combined_min.y,
		(combined_min.z + combined_max.z) * 0.5 if recenter_horizontal else 0.0,
	)
	var scale_basis: Basis = Basis().scaled(Vector3.ONE * scale)
	var groups: Dictionary = {}
	var order: Array = []
	for entry: Dictionary in entries:
		var material: Material = entry["material"]
		if not groups.has(material):
			groups[material] = []
			order.append(material)
		groups[material].append(entry)
	var merged: ArrayMesh = null
	for material: Variant in order:
		var surface_tool: SurfaceTool = SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for entry: Dictionary in groups[material]:
			var local_transform: Transform3D = entry["transform"]
			var recentered: Transform3D = Transform3D(local_transform.basis, local_transform.origin - base)
			var final_transform: Transform3D = Transform3D(scale_basis * recentered.basis, scale_basis * recentered.origin)
			surface_tool.append_from(entry["mesh"], entry["surface"], final_transform)
		surface_tool.set_material(_tinted_foliage_material(material as Material, foliage_tint))
		merged = surface_tool.commit(merged)
	_mesh_cache[cache_key] = merged
	return merged


## Walks a model's node tree collecting (mesh, surface, composed local
## transform, material, world-space AABB min/max) per surface. Uses each
## node's own `transform` (not `global_transform`) so it works on an
## instance that was never added to the SceneTree.
static func _collect(node: Node, parent_transform: Transform3D, entries: Array[Dictionary]) -> void:
	var local_transform: Transform3D = parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh != null:
			var local_aabb: AABB = mesh_instance.mesh.get_aabb()
			var aabb_min: Vector3 = Vector3.INF
			var aabb_max: Vector3 = -Vector3.INF
			for corner_index: int in range(8):
				var corner: Vector3 = local_aabb.position + Vector3(
					local_aabb.size.x * float(corner_index & 1),
					local_aabb.size.y * float((corner_index >> 1) & 1),
					local_aabb.size.z * float((corner_index >> 2) & 1),
				)
				var world_corner: Vector3 = local_transform * corner
				aabb_min = aabb_min.min(world_corner)
				aabb_max = aabb_max.max(world_corner)
			for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
				entries.append({
					"mesh": mesh_instance.mesh,
					"surface": surface_index,
					"transform": local_transform,
					"material": mesh_instance.mesh.surface_get_material(surface_index),
					"min": aabb_min,
					"max": aabb_max,
				})
	for child: Node in node.get_children():
		_collect(child, local_transform, entries)


## Returns `material` unchanged unless `tint` is opaque and `material`'s
## albedo closely matches the kit's shared washed-out foliage swatch, in
## which case a duplicate with `tint` as its albedo is returned instead.
static func _tinted_foliage_material(material: Material, tint: Color) -> Material:
	if tint.a <= 0.0 or not material is StandardMaterial3D:
		return material
	var standard: StandardMaterial3D = material as StandardMaterial3D
	var albedo: Color = standard.albedo_color
	var delta: float = (
		absf(albedo.r - KIT_FOLIAGE_COLOR.r)
		+ absf(albedo.g - KIT_FOLIAGE_COLOR.g)
		+ absf(albedo.b - KIT_FOLIAGE_COLOR.b)
	)
	if delta > KIT_FOLIAGE_EPSILON:
		return material
	var tinted: StandardMaterial3D = standard.duplicate() as StandardMaterial3D
	tinted.albedo_color = tint
	return tinted


static func _warn_fallback(path: String) -> void:
	if _fallback_warned:
		return
	_fallback_warned = true
	push_warning("Kenney track prop asset missing or failed to load (%s); skipping that decoration." % path)
