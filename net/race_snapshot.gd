class_name RaceSnapshot
extends RefCounted

## Server-to-client snapshot, with grid indices instead of process-local object ids.
const VERSION: int = 1
const HEADER_BYTES: int = 24
const ROW_TAIL_BYTES: int = 24
const PROJECTILE_BYTES: int = 25
const MAX_KARTS: int = 12

var tick: int = 0
var server_seconds: float = 0.0
var race_state: int = RaceState.LOADING
var race_seconds: float = 0.0
var countdown_seconds: float = 0.0
var karts: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []

## Encodes fixed-width records into a PackedByteArray using StreamPeerBuffer.
func pack() -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8(VERSION)
	buffer.put_u32(tick)
	buffer.put_double(server_seconds)
	buffer.put_u8(race_state)
	buffer.put_float(race_seconds)
	buffer.put_float(countdown_seconds)
	buffer.put_u8(karts.size())
	buffer.put_u8(projectiles.size())
	for row: Dictionary in karts:
		NetStateCodec.write(buffer, row["state"])
		buffer.put_u32(int(row.get("ack", 0)))
		buffer.put_u8(int(row.get("lap", 0)))
		buffer.put_u8(int(row.get("rank", 0)))
		buffer.put_u8(int(row.get("checkpoint", 0)))
		buffer.put_u8(int(row.get("item", 0)))
		buffer.put_float(float(row.get("roulette", -1.0)))
		buffer.put_float(float(row.get("cooldown", 0.0)))
		buffer.put_float(float(row.get("finish", -1.0)))
		buffer.put_float(float(row.get("progress", 0.0)))
	for row: Dictionary in projectiles:
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
	var count: int = buffer.get_u8()
	var projectile_count: int = buffer.get_u8()
	if count > MAX_KARTS or projectile_count > NetTuning.MAX_PROJECTILES or result.race_state > RaceState.PAUSED:
		return null
	var expected: int = HEADER_BYTES + count * (NetStateCodec.byte_size() + ROW_TAIL_BYTES) + projectile_count * PROJECTILE_BYTES
	if bytes.size() != expected or not is_finite(result.server_seconds) or not is_finite(result.race_seconds) or not is_finite(result.countdown_seconds):
		return null
	for _index: int in range(count):
		var row: Dictionary = {"state": NetStateCodec.read(buffer), "ack": buffer.get_u32(),
			"lap": buffer.get_u8(), "rank": buffer.get_u8(), "checkpoint": buffer.get_u8(), "item": buffer.get_u8(),
			"roulette": buffer.get_float(), "cooldown": buffer.get_float(), "finish": buffer.get_float(), "progress": buffer.get_float()}
		if not KartReplayState.is_valid(row["state"]):
			return null
		result.karts.append(row)
	for _index: int in range(projectile_count):
		var id: int = buffer.get_u32()
		var item: int = buffer.get_u8()
		var pos: Vector3 = Vector3(buffer.get_32(), buffer.get_32(), buffer.get_32()) / NetTuning.POSITION_SCALE
		var angles: Vector3 = Vector3(buffer.get_16(), buffer.get_16(), buffer.get_16()) / NetTuning.ANGLE_SCALE
		result.projectiles.append({"id": id, "item": item, "pose": Transform3D(Basis.from_euler(angles), pos), "owner": buffer.get_u16()})
	return result
