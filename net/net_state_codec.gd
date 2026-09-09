class_name NetStateCodec
extends RefCounted

## Fixed allowlist binary layout; cm positions and milliradian yaw, float32 timers.
const BYTE_BYTES: int = 1
const SHORT_BYTES: int = 2
const POSITION_AXIS_BYTES: int = 4
const FLOAT_BYTES: int = 4
const VECTOR_AXES: int = 3
const BOOST_FLOAT_FIELDS: Array[String] = ["speed_mult", "accel_mult", "duration", "remaining"]
const SLIP_FLOAT_FIELDS: Array[String] = ["slip_charge", "slip_exit"]
const VECTORS: Array[String] = ["ground_normal", "up", "velocity"]
const BOOST_SOURCES: Array[StringName] = [&"", &"start_boost", &"slipstream_exit", &"mini_turbo_1", &"mini_turbo_2", &"mini_turbo_3", &"trick", &"boost_pad", &"item_boost"]

## Writes a complete deterministic state with compact component values.
static func write(buffer: StreamPeerBuffer, state: Dictionary) -> void:
	for axis: int in range(VECTOR_AXES):
		_write_integer(buffer, roundi(float(state["position"][axis]) * NetTuning.POSITION_SCALE), POSITION_AXIS_BYTES)
	_write_integer(buffer, roundi(wrapf(float(state["rotation"][1]), -PI, PI) * NetTuning.ANGLE_SCALE), SHORT_BYTES)
	for key: String in VECTORS:
		for axis: int in range(VECTOR_AXES):
			buffer.put_float(float(state[key][axis]))
	for key: String in KartReplayState.KART_STATS:
		buffer.put_float(float(state["stats"][key]))
	for path: String in KartReplayState.COMPONENT_FIELDS:
		for field: String in KartReplayState.COMPONENT_FIELDS[path]:
			var value: Variant = state["components"][path][field]
			if KartReplayState.BOOLEAN_FIELDS.has(field):
				_write_integer(buffer, 1 if bool(value) else 0, BYTE_BYTES)
			elif KartReplayState.INTEGER_FIELDS.has(field):
				_write_integer(buffer, int(value), SHORT_BYTES)
			else:
				buffer.put_float(float(value))
	var boost: Dictionary = state["boost"]
	_write_integer(buffer, 0 if boost.is_empty() else 1, BYTE_BYTES)
	# Fixed-width boost tail keeps malformed packet validation unambiguous.
	for key: String in BOOST_FLOAT_FIELDS:
		buffer.put_float(float(boost.get(key, 0.0)))
	_write_integer(buffer, int(boost.get("priority", 0)), SHORT_BYTES)
	_write_integer(buffer, 1 if bool(boost.get("ignores_offroad", false)) else 0, BYTE_BYTES)
	_write_integer(buffer, maxi(0, BOOST_SOURCES.find(StringName(boost.get("source", "")))), BYTE_BYTES)
	for key: String in SLIP_FLOAT_FIELDS:
		buffer.put_float(float(state.get(key, 0.0)))
	_write_integer(buffer, 1 if bool(state.get("slip_active", false)) else 0, BYTE_BYTES)

## Reads only after the enclosing snapshot has validated fixed record lengths.
static func read(buffer: StreamPeerBuffer) -> Dictionary:
	var position: Array[float] = []
	for _axis: int in range(VECTOR_AXES):
		position.append(float(_read_integer(buffer, POSITION_AXIS_BYTES)) / NetTuning.POSITION_SCALE)
	var yaw: float = float(_read_integer(buffer, SHORT_BYTES)) / NetTuning.ANGLE_SCALE
	var basis: Basis = Basis(Vector3.UP, yaw)
	var state: Dictionary = {"position": position, "rotation": [0.0, yaw, 0.0],
		"basis_x": _vector(basis.x), "basis_y": _vector(basis.y), "basis_z": _vector(basis.z),
		"stats": {}, "components": {}, "boost": {}}
	for key: String in VECTORS:
		state[key] = []
		for _axis: int in range(VECTOR_AXES):
			state[key].append(buffer.get_float())
	for key: String in KartReplayState.KART_STATS:
		state["stats"][key] = buffer.get_float()
	for path: String in KartReplayState.COMPONENT_FIELDS:
		state["components"][path] = {}
		for field: String in KartReplayState.COMPONENT_FIELDS[path]:
			if KartReplayState.BOOLEAN_FIELDS.has(field):
				state["components"][path][field] = _read_integer(buffer, BYTE_BYTES) != 0
			elif KartReplayState.INTEGER_FIELDS.has(field):
				state["components"][path][field] = _read_integer(buffer, SHORT_BYTES)
			else:
				state["components"][path][field] = buffer.get_float()
	var active: bool = _read_integer(buffer, BYTE_BYTES) != 0
	var boost: Dictionary = {"type": "boost"}
	for key: String in BOOST_FLOAT_FIELDS:
		boost[key] = buffer.get_float()
	boost["priority"] = _read_integer(buffer, SHORT_BYTES)
	boost["ignores_offroad"] = _read_integer(buffer, BYTE_BYTES) != 0
	var source: int = _read_integer(buffer, BYTE_BYTES)
	boost["source"] = String(BOOST_SOURCES[source]) if source < BOOST_SOURCES.size() else ""
	state["boost"] = boost if active else {}
	for key: String in SLIP_FLOAT_FIELDS:
		state[key] = buffer.get_float()
	state["slip_active"] = _read_integer(buffer, BYTE_BYTES) != 0
	return state

## Computes the fixed record size from the shared replay allowlist.
static func byte_size() -> int:
	var result: int = VECTOR_AXES * POSITION_AXIS_BYTES + SHORT_BYTES # Position and yaw.
	result += VECTORS.size() * VECTOR_AXES * FLOAT_BYTES + KartReplayState.KART_STATS.size() * FLOAT_BYTES
	result += BYTE_BYTES + BOOST_FLOAT_FIELDS.size() * FLOAT_BYTES + SHORT_BYTES + 2 * BYTE_BYTES
	result += SLIP_FLOAT_FIELDS.size() * FLOAT_BYTES + BYTE_BYTES
	for path: String in KartReplayState.COMPONENT_FIELDS:
		for field: String in KartReplayState.COMPONENT_FIELDS[path]:
			result += BYTE_BYTES if KartReplayState.BOOLEAN_FIELDS.has(field) else (SHORT_BYTES if KartReplayState.INTEGER_FIELDS.has(field) else FLOAT_BYTES)
	return result

static func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

static func _write_integer(buffer: StreamPeerBuffer, value: int, width: int) -> void:
	match width:
		BYTE_BYTES: buffer.put_u8(value)
		SHORT_BYTES: buffer.put_16(value)
		POSITION_AXIS_BYTES: buffer.put_32(value)

static func _read_integer(buffer: StreamPeerBuffer, width: int) -> int:
	match width:
		BYTE_BYTES: return buffer.get_u8()
		SHORT_BYTES: return buffer.get_16()
		POSITION_AXIS_BYTES: return buffer.get_32()
	return 0
