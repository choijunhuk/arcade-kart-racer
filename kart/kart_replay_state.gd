class_name KartReplayState
extends RefCounted

## Explicit snapshot schema for same-build deterministic single-player lap replay.
## Only allowlisted fields are restored; JSON never selects objects or properties.

const COMPONENT_FIELDS: Dictionary[String, Array] = {
	".": ["state", "_ungrounded_ticks", "_race_frozen", "_finished", "_respawning", "_start_wheelspin_remaining"],
	"KartPhysics": ["speed", "lateral", "grounded", "air_time", "last_yaw_rate",
		"_vertical_speed", "_was_grounded", "_wall_contact_active", "_ground_ignore_ticks"],
	"DriftController": ["_state", "_direction", "_charge", "_tier", "_released_tier", "_hop_elapsed",
		"_low_speed_elapsed", "_opposite_elapsed", "_cooldown_remaining", "_trick_armed", "_was_grounded"],
	"HitReactor": ["_hit_type", "_duration", "_remaining", "_invulnerability_remaining",
		"_bump_from_item", "_bump_item_speed_factor"],
}
const KART_STATS: Array[String] = ["max_speed", "acceleration", "handling", "drift_factor",
	"drift_charge_mult", "weight", "traction", "boost_power", "offroad_resistance"]
const BOOST_FIELDS: Array[String] = ["speed_mult", "accel_mult", "duration", "priority", "ignores_offroad"]
const INTEGER_FIELDS: Array[String] = ["state", "_ungrounded_ticks", "_ground_ignore_ticks",
	"_state", "_direction", "_tier", "_released_tier", "_hit_type"]
const BOOLEAN_FIELDS: Array[String] = ["_race_frozen", "_finished", "_respawning", "grounded",
	"_was_grounded", "_wall_contact_active", "_trick_armed", "_bump_from_item"]


## Captures all physics-affecting lap-boundary state, including an active turbo.
static func capture(kart: KartController) -> Dictionary:
	var result: Dictionary = {"position": _vector(kart.global_position), "rotation": _vector(kart.global_rotation),
		"basis_x": _vector(kart.global_basis.x), "basis_y": _vector(kart.global_basis.y), "basis_z": _vector(kart.global_basis.z),
		"ground_normal": _vector(kart.get_ground_normal()), "up": _vector(kart.up_direction),
		"velocity": _vector(kart.velocity), "stats": {}, "components": {}, "boost": {}}
	for stat: String in KART_STATS:
		result["stats"][stat] = kart.kart_data.get(stat)
	for path: String in COMPONENT_FIELDS:
		var component: Node = kart if path == "." else kart.get_node(path)
		var values: Dictionary = {}
		for field: String in COMPONENT_FIELDS[path]:
			values[field] = component.get(field)
		result["components"][path] = values
	var boost: KartPhysics.BoostResult = kart.boost_controller.get_result()
	if boost.active:
		result["boost"] = boost_dict(boost.spec, boost.source)
		result["boost"]["remaining"] = boost.remaining
	return result


## Restores a validated snapshot after the kart's component setup has run.
static func restore(kart: KartController, data: Dictionary) -> void:
	var kart_data: KartData = kart.kart_data.duplicate(true) as KartData
	for stat: String in KART_STATS:
		kart_data.set(stat, data["stats"][stat])
	kart.set_kart_data(kart_data)
	kart.global_transform = Transform3D(Basis(_from_vector(data["basis_x"]),
		_from_vector(data["basis_y"]), _from_vector(data["basis_z"])), _from_vector(data["position"]))
	kart.velocity = _from_vector(data["velocity"])
	kart.up_direction = _from_vector(data["up"])
	for path: String in COMPONENT_FIELDS:
		var component: Node = kart if path == "." else kart.get_node(path)
		for field: String in COMPONENT_FIELDS[path]:
			component.set(field, data["components"][path][field])
	var physics: KartPhysics = kart.get_node("KartPhysics") as KartPhysics
	physics.ground_normal = _from_vector(data["ground_normal"])
	physics.set("_current_up", kart.up_direction)
	kart.boost_controller.set("_active_spec", null)
	var boost: Dictionary = data["boost"]
	if not boost.is_empty():
		kart.boost_controller.request(_boost_spec(boost), StringName(boost["source"]))
		kart.boost_controller.set("_remaining", float(boost["remaining"]))


## JSON numbers are floats; restore integer state fields before comparison/replay.
static func normalize_json(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	for path: String in COMPONENT_FIELDS:
		for field: String in COMPONENT_FIELDS[path]:
			if INTEGER_FIELDS.has(field):
				result["components"][path][field] = int(result["components"][path][field])
	if not result["boost"].is_empty():
		result["boost"]["priority"] = int(result["boost"]["priority"])
	return result


## Serializes external pad boosts independently of in-kart drift/trick requests.
static func boost_dict(spec: BoostSpecData, source: StringName) -> Dictionary:
	var result: Dictionary = {"type": "boost", "source": String(source)}
	for field: String in BOOST_FIELDS:
		result[field] = spec.get(field)
	return result


## Replays external track effects at their recorded input boundary.
static func apply_event(kart: KartController, event: Dictionary) -> void:
	match event["type"]:
		"boost":
			kart.request_boost(_boost_spec(event), StringName(event["source"]))
		"launch":
			kart.launch(_from_vector(event["velocity"]))
		"hit":
			kart.apply_hit(int(event["hit_type"]) as HitReactor.HitType)


## Checks the complete schema before any state reaches component setters.
static func is_valid(data: Dictionary) -> bool:
	for key: String in ["position", "rotation", "basis_x", "basis_y", "basis_z", "ground_normal", "up", "velocity"]:
		if not _valid_vector(data.get(key)):
			return false
	for key: String in ["stats", "components", "boost"]:
		if not data.get(key) is Dictionary:
			return false
	for stat: String in KART_STATS:
		if not _number(data["stats"].get(stat)):
			return false
	for path: String in COMPONENT_FIELDS:
		if not data["components"].get(path) is Dictionary:
			return false
		for field: String in COMPONENT_FIELDS[path]:
			var value: Variant = data["components"][path].get(field)
			if BOOLEAN_FIELDS.has(field):
				if not value is bool:
					return false
			elif not _number(value):
				return false
			elif INTEGER_FIELDS.has(field) and float(value) != floorf(float(value)):
				return false
	var boost: Dictionary = data["boost"]
	return boost.is_empty() or (valid_event(boost) and _number(boost.get("remaining")))


## Rejects unknown effect types and malformed external-event payloads.
static func valid_event(event: Dictionary) -> bool:
	match event.get("type"):
		"launch":
			return _valid_vector(event.get("velocity"))
		"hit":
			return _number(event.get("hit_type")) and int(event["hit_type"]) in range(4)
		"boost":
			if not event.get("source") is String or not event.get("ignores_offroad") is bool:
				return false
			for field: String in ["speed_mult", "accel_mult", "duration", "priority"]:
				if not _number(event.get(field)):
					return false
			return true
	return false


static func _boost_spec(data: Dictionary) -> BoostSpecData:
	var spec: BoostSpecData = BoostSpecData.new()
	for field: String in BOOST_FIELDS:
		spec.set(field, data[field])
	return spec


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _valid_vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _number(value[0]) and _number(value[1]) and _number(value[2])


static func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


static func _from_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
