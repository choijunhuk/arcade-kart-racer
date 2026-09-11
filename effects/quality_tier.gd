class_name QualityTier
extends RefCounted

const SCALES: Array[float] = [0.65, 0.85, 1.0]
const DETAIL_DISTANCE: float = 45.0
const FAR_DISTANCE: float = 100.0
## Directional shadow reach and cascade split count, indexed by tier.
const SHADOW_MAX_DISTANCE: Array[float] = [0.0, 70.0, 140.0]
const SHADOW_SPLITS: Array[int] = [0, 2, 4]
## Decorative instance-count multiplier for crowd/curb/prop batches (perf guard).
const DRESSING_DENSITY: Array[float] = [0.5, 0.75, 1.0]
## Group tag applied to lamp `OmniLight3D`s that are real lights only on the
## highest tier; lower tiers keep only their always-visible glow sprite.
const DRESSING_LAMP_GROUP: StringName = &"dressing_lamp"

## Maps the particle selector to a complete rendering budget.
static func settings(tier: int) -> Dictionary:
	var level: int = clampi(tier, 0, 2)
	return {
		"render_scale": SCALES[level],
		"msaa": level,
		"shadows": level > 0,
		"fog": level > 0,
		"glow": level == 2,
		"ssao": level == 2,
		"shadow_splits": SHADOW_SPLITS[level],
		"shadow_max_distance": SHADOW_MAX_DISTANCE[level],
		"real_lamps": level == 2,
		"dressing_density": DRESSING_DENSITY[level],
	}

## Selects near, simplified or distant visual detail by camera distance.
static func lod(distance: float) -> int:
	return 0 if distance < DETAIL_DISTANCE else (1 if distance < FAR_DISTANCE else 2)

## Applies presentation settings to an explicitly supplied scene subtree.
static func apply_scene(node: Node, tier: int) -> void:
	var values: Dictionary = settings(tier)
	if node is DirectionalLight3D:
		var sun: DirectionalLight3D = node as DirectionalLight3D
		sun.shadow_enabled = values["shadows"]
		if values["shadows"]:
			sun.directional_shadow_mode = (
				DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(values["shadow_splits"]) >= 4
				else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			)
			sun.directional_shadow_max_distance = float(values["shadow_max_distance"])
	elif node is Light3D:
		(node as Light3D).shadow_enabled = values["shadows"]
	if node is OmniLight3D and node.is_in_group(DRESSING_LAMP_GROUP):
		node.visible = bool(values["real_lamps"])
	if node is WorldEnvironment:
		var environment: Environment = (node as WorldEnvironment).environment
		if environment != null:
			environment.fog_enabled = values["fog"]
			environment.glow_enabled = values["glow"]
			environment.ssao_enabled = values["ssao"]
	for child: Node in node.get_children():
		apply_scene(child, tier)
