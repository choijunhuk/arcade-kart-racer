class_name ParticleBudget
extends RefCounted

## Pure particle-count and camera-distance helpers shared by tests and LOD.


## Counts every GPUParticles3D node below a kart or race root.
static func count_gpu_particles(root: Node) -> int:
	if root == null:
		return 0
	var count: int = 1 if root is GPUParticles3D else 0
	count += root.find_children("*", "GPUParticles3D", true, false).size()
	return count


## Checks both the per-kart maximum and aggregate GPU emitter cap.
static func counts_fit(counts: PackedInt32Array, maximum_per_kart: int, maximum_total: int) -> bool:
	var total: int = 0
	for count: int in counts:
		if count > maximum_per_kart:
			return false
		total += count
	return total <= maximum_total


## Returns true through the inclusive LOD boundary.
static func within_lod_distance(camera_position: Vector3, kart_position: Vector3, maximum_distance: float) -> bool:
	return camera_position.distance_squared_to(kart_position) <= maximum_distance * maximum_distance
