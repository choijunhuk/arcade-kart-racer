class_name NetStateCodec
extends RefCounted

## Fixed allowlist binary layout; cm positions and milliradian yaw, float32 timers.
const VECTORS: Array[String] = ["ground_normal", "up", "velocity"]
const BOOST_SOURCES: Array[StringName] = [&"", &"start_boost", &"slipstream_exit", &"drift", &"trick", &"boost_pad", &"nitro"]

## Writes a complete deterministic state with compact component values.
static func write(buffer: StreamPeerBuffer, state: Dictionary) -> void:
	for value: float in state["position"]:
		buffer.put_32(roundi(value * NetTuning.POSITION_SCALE))
	buffer.put_16(roundi(wrapf(float(state["rotation"][1]), -PI, PI) * NetTuning.ANGLE_SCALE))
	for key: String in VECTORS:
		for value: float in state[key]:
			buffer.put_float(value)
	for key: String in KartReplayState.KART_STATS:
		buffer.put_float(float(state["stats"][key]))
	for path: String in KartReplayState.COMPONENT_FIELDS:
		for field: String in KartReplayState.COMPONENT_FIELDS[path]:
			var value: Variant = state["components"][path][field]
			if KartReplayState.BOOLEAN_FIELDS.has(field):
				buffer.put_u8(1 if bool(value) else 0)
			elif KartReplayState.INTEGER_FIELDS.has(field):
				buffer.put_16(int(value))
			else:
				buffer.put_float(float(value))
	var boost: Dictionary = state["boost"]
	buffer.put_u8(0 if boost.is_empty() else 1)
	# Fixed-width boost tail keeps malformed packet validation unambiguous.
	for key: String in ["speed_mult", "accel_mult", "duration", "remaining"]:
		buffer.put_float(float(boost.get(key, 0.0)))
	buffer.put_16(int(boost.get("priority", 0)))
	buffer.put_u8(1 if bool(boost.get("ignores_offroad", false)) else 0)
	buffer.put_u8(maxi(0, BOOST_SOURCES.find(StringName(boost.get("source", "")))))
	buffer.put_float(float(state.get("slip_charge", 0.0)))
	buffer.put_float(float(state.get("slip_exit", 0.0)))
	buffer.put_u8(1 if bool(state.get("slip_active", false)) else 0)

## Reads only after the enclosing snapshot has validated fixed record lengths.
static func read(buffer: StreamPeerBuffer) -> Dictionary:
	var position: Array[float] = []
	for _axis: int in range(3):
		position.append(float(buffer.get_32()) / NetTuning.POSITION_SCALE)
	var yaw: float = float(buffer.get_16()) / NetTuning.ANGLE_SCALE
	var basis: Basis = Basis(Vector3.UP, yaw)
	var state: Dictionary = {"position": position, "rotation": [0.0, yaw, 0.0],
		"basis_x": _vector(basis.x), "basis_y": _vector(basis.y), "basis_z": _vector(basis.z),
		"stats": {}, "components": {}, "boost": {}}
	for key: String in VECTORS:
		state[key] = [buffer.get_float(), buffer.get_float(), buffer.get_float()]
	for key: String in KartReplayState.KART_STATS:
		state["stats"][key] = buffer.get_float()
	for path: String in KartReplayState.COMPONENT_FIELDS:
		state["components"][path] = {}
		for field: String in KartReplayState.COMPONENT_FIELDS[path]:
			if KartReplayState.BOOLEAN_FIELDS.has(field):
				state["components"][path][field] = buffer.get_u8() != 0
			elif KartReplayState.INTEGER_FIELDS.has(field):
				state["components"][path][field] = buffer.get_16()
			else:
				state["components"][path][field] = buffer.get_float()
	var active: bool = buffer.get_u8() != 0
	var boost: Dictionary = {"type": "boost"}
	for key: String in ["speed_mult", "accel_mult", "duration", "remaining"]:
		boost[key] = buffer.get_float()
	boost["priority"] = buffer.get_16()
	boost["ignores_offroad"] = buffer.get_u8() != 0
	var source: int = buffer.get_u8()
	boost["source"] = String(BOOST_SOURCES[source]) if source < BOOST_SOURCES.size() else ""
	state["boost"] = boost if active else {}
	state["slip_charge"] = buffer.get_float()
	state["slip_exit"] = buffer.get_float()
	state["slip_active"] = buffer.get_u8() != 0
	return state

## Computes the fixed record size from the shared replay allowlist.
static func byte_size() -> int:
	var result: int = 14 + VECTORS.size() * 12 + KartReplayState.KART_STATS.size() * 4 + 30
	for path: String in KartReplayState.COMPONENT_FIELDS:
		for field: String in KartReplayState.COMPONENT_FIELDS[path]:
			result += 1 if KartReplayState.BOOLEAN_FIELDS.has(field) else (2 if KartReplayState.INTEGER_FIELDS.has(field) else 4)
	return result

static func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
