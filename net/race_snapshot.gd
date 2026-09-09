class_name RaceSnapshot
extends RefCounted

## Server-to-client snapshot, with grid indices instead of process-local object ids.
const VERSION: int = 3
const WIRE_HEADER_BYTES: int = 5
const HEADER_BYTES: int = 26
const ROW_TAIL_BYTES: int = 25
const PROJECTILE_BYTES: int = 25
const MAX_KARTS: int = 12
## Raw (pre-compression) payload budget per chunk, used only once the whole
## snapshot has already been measured to not fit as one packet. Deliberately
## conservative (assumes worst-case near-incompressible data plus a small
## zstd frame overhead) so every produced chunk is comfortably inside
## `NetTuning.MAX_UNRELIABLE_BYTES` once compressed and wire-framed.
const CHUNK_RAW_BUDGET: int = 900

var tick: int = 0
var server_seconds: float = 0.0
var race_state: int = RaceState.LOADING
var race_seconds: float = 0.0
var countdown_seconds: float = 0.0
## 0-based position of this chunk among `chunk_count` siblings sharing `tick`.
var chunk_index: int = 0
## Total chunks this snapshot's tick was split across; 1 when it fit whole.
var chunk_count: int = 1
var karts: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []

## Losslessly compresses the fixed layout as a single, whole packet.
func pack() -> PackedByteArray:
	return _pack_chunk(0, 1, karts, projectiles)

## Splits this snapshot into one or more independently-decodable packets so
## a busy race (many karts/items) never exceeds the unreliable transport's
## size budget: each chunk carries the full header plus its own kart/item
## subset (karts keep an explicit `slot` so the receiver can place rows
## without assuming a contiguous full roster) and never gets dropped for size.
## The common case (whole snapshot already fits after compression, exactly
## as `NetSession._deliver` would measure it) stays a single unsplit packet.
func pack_chunked() -> Array[PackedByteArray]:
	var whole: PackedByteArray = _pack_chunk(0, 1, karts, projectiles)
	if var_to_bytes([whole]).size() + NetTuning.RPC_OVERHEAD_BYTES <= NetTuning.MAX_UNRELIABLE_BYTES:
		return [whole]
	var groups: Array[Dictionary] = _chunk_groups()
	var result: Array[PackedByteArray] = []
	for index: int in range(groups.size()):
		result.append(_pack_chunk(index, groups.size(), groups[index]["karts"], groups[index]["projectiles"]))
	return result

func _chunk_groups() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var current: Dictionary = {"karts": [], "projectiles": []}
	var current_size: int = HEADER_BYTES
	var kart_row_size: int = NetStateCodec.byte_size() + ROW_TAIL_BYTES
	for index: int in range(karts.size()):
		if not _chunk_is_empty(current) and current_size + kart_row_size > CHUNK_RAW_BUDGET:
			groups.append(current)
			current = {"karts": [], "projectiles": []}
			current_size = HEADER_BYTES
		var row: Dictionary = karts[index].duplicate()
		row["slot"] = index
		(current["karts"] as Array).append(row)
		current_size += kart_row_size
	for row: Dictionary in projectiles:
		if not _chunk_is_empty(current) and current_size + PROJECTILE_BYTES > CHUNK_RAW_BUDGET:
			groups.append(current)
			current = {"karts": [], "projectiles": []}
			current_size = HEADER_BYTES
		(current["projectiles"] as Array).append(row)
		current_size += PROJECTILE_BYTES
	groups.append(current)
	return groups

static func _chunk_is_empty(group: Dictionary) -> bool:
	return (group["karts"] as Array).is_empty() and (group["projectiles"] as Array).is_empty()

func _pack_chunk(chunk_index_value: int, chunk_count_value: int, kart_rows: Array, projectile_rows: Array) -> PackedByteArray:
	var raw: PackedByteArray = _pack_records(chunk_index_value, chunk_count_value, kart_rows, projectile_rows)
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var wire: StreamPeerBuffer = StreamPeerBuffer.new()
	wire.put_u8(VERSION)
	wire.put_u16(raw.size())
	wire.put_u16(compressed.size())
	wire.put_data(compressed)
	return wire.data_array

func _pack_records(chunk_index_value: int, chunk_count_value: int, kart_rows: Array, projectile_rows: Array) -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(VERSION)
	buffer.put_u32(tick)
	buffer.put_double(server_seconds)
	buffer.put_u8(race_state)
	buffer.put_float(race_seconds)
	buffer.put_float(countdown_seconds)
	buffer.put_u8(chunk_index_value)
	buffer.put_u8(chunk_count_value)
	buffer.put_u8(kart_rows.size())
	buffer.put_u8(projectile_rows.size())
	for row: Dictionary in kart_rows:
		NetStateCodec.write(buffer, row["state"])
		buffer.put_u8(int(row.get("slot", 0)))
		buffer.put_u32(int(row.get("ack", 0)))
		buffer.put_u8(int(row.get("lap", 0)))
		buffer.put_u8(int(row.get("rank", 0)))
		buffer.put_u8(int(row.get("checkpoint", 0)))
		buffer.put_u8(int(row.get("item", 0)))
		buffer.put_float(float(row.get("roulette", -1.0)))
		buffer.put_float(float(row.get("cooldown", 0.0)))
		buffer.put_float(float(row.get("finish", -1.0)))
		buffer.put_float(float(row.get("progress", 0.0)))
	for row: Dictionary in projectile_rows:
		buffer.put_u32(int(row["id"]))
		buffer.put_u8(int(row["item"]))
		var pose: Transform3D = row["pose"]
		for value: float in [pose.origin.x, pose.origin.y, pose.origin.z]:
			buffer.put_32(roundi(value * NetTuning.POSITION_SCALE))
		for value: float in [pose.basis.get_euler().x, pose.basis.get_euler().y, pose.basis.get_euler().z]:
			buffer.put_16(roundi(wrapf(value, -PI, PI) * NetTuning.ANGLE_SCALE))
		buffer.put_u16(int(row.get("owner", 0)))
	return buffer.data_array

## Rejects versions, counts, truncated/trailing bytes and nonfinite state data.
static func unpack(bytes: PackedByteArray) -> RaceSnapshot:
	if bytes.size() < WIRE_HEADER_BYTES or bytes.size() > NetTuning.MAX_PACKET_BYTES:
		return null
	if bytes[0] != VERSION or bytes.decode_u16(3) != bytes.size() - WIRE_HEADER_BYTES:
		return null
	var raw_size: int = bytes.decode_u16(1)
	var max_size: int = HEADER_BYTES + MAX_KARTS * (NetStateCodec.byte_size() + ROW_TAIL_BYTES) + NetTuning.MAX_PROJECTILES * PROJECTILE_BYTES
	if raw_size < HEADER_BYTES or raw_size > max_size:
		return null
	var raw: PackedByteArray = bytes.slice(WIRE_HEADER_BYTES).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return null
	return _unpack_records(raw)

static func _unpack_records(bytes: PackedByteArray) -> RaceSnapshot:
	if bytes.size() < HEADER_BYTES or bytes.size() > NetTuning.MAX_PACKET_BYTES:
		return null
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.data_array = bytes
	if buffer.get_u8() != VERSION:
		return null
	var result: RaceSnapshot = RaceSnapshot.new()
	result.tick = buffer.get_u32()
	result.server_seconds = buffer.get_double()
	result.race_state = buffer.get_u8()
	result.race_seconds = buffer.get_float()
	result.countdown_seconds = buffer.get_float()
	result.chunk_index = buffer.get_u8()
	result.chunk_count = buffer.get_u8()
	var count: int = buffer.get_u8()
	var projectile_count: int = buffer.get_u8()
	if count > MAX_KARTS or projectile_count > NetTuning.MAX_PROJECTILES or result.race_state > RaceState.PAUSED:
		return null
	if result.chunk_count < 1 or result.chunk_index < 0 or result.chunk_index >= result.chunk_count:
		return null
	var expected: int = HEADER_BYTES + count * (NetStateCodec.byte_size() + ROW_TAIL_BYTES) + projectile_count * PROJECTILE_BYTES
	if bytes.size() != expected or not is_finite(result.server_seconds) or not is_finite(result.race_seconds) or not is_finite(result.countdown_seconds):
		return null
	for _index: int in range(count):
		var state: Dictionary = NetStateCodec.read(buffer)
		var slot: int = buffer.get_u8()
		var row: Dictionary = {"state": state, "slot": slot, "ack": buffer.get_u32(),
			"lap": buffer.get_u8(), "rank": buffer.get_u8(), "checkpoint": buffer.get_u8(), "item": buffer.get_u8(),
			"roulette": buffer.get_float(), "cooldown": buffer.get_float(), "finish": buffer.get_float(), "progress": buffer.get_float()}
		if slot < 0 or slot >= MAX_KARTS or not KartReplayState.is_valid(row["state"]):
			return null
		for key: String in ["roulette", "cooldown", "finish", "progress"]:
			if not is_finite(float(row[key])):
				return null
		for key: String in ["slip_charge", "slip_exit"]:
			if not is_finite(float(row["state"][key])):
				return null
		result.karts.append(row)
	for _index: int in range(projectile_count):
		var id: int = buffer.get_u32()
		var item: int = buffer.get_u8()
		var pos: Vector3 = Vector3(buffer.get_32(), buffer.get_32(), buffer.get_32()) / NetTuning.POSITION_SCALE
		var angles: Vector3 = Vector3(buffer.get_16(), buffer.get_16(), buffer.get_16()) / NetTuning.ANGLE_SCALE
		result.projectiles.append({"id": id, "item": item, "pose": Transform3D(Basis.from_euler(angles), pos), "owner": buffer.get_u16()})
	return result
