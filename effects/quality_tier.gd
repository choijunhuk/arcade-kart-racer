class_name QualityTier
extends RefCounted

const SCALES: Array[float] = [0.65, 0.85, 1.0]
const DETAIL_DISTANCE: float = 45.0
const FAR_DISTANCE: float = 100.0

## Maps the particle selector to a complete rendering budget.
static func settings(tier: int) -> Dictionary:
	var level: int = clampi(tier, 0, 2)
	return {"render_scale": SCALES[level], "msaa": level, "shadows": level > 0, "fog": level > 0, "glow": level == 2}

## Selects near, simplified or distant visual detail by camera distance.
static func lod(distance: float) -> int:
	return 0 if distance < DETAIL_DISTANCE else (1 if distance < FAR_DISTANCE else 2)

## Applies presentation settings to an explicitly supplied scene subtree.
static func apply_scene(node: Node, tier: int) -> void:
	var values: Dictionary = settings(tier)
	if node is Light3D:
		(node as Light3D).shadow_enabled = values["shadows"]
	if node is WorldEnvironment:
		var environment: Environment = (node as WorldEnvironment).environment
		if environment != null:
			environment.fog_enabled = values["fog"]
			environment.glow_enabled = values["glow"]
	for child: Node in node.get_children():
		apply_scene(child, tier)
