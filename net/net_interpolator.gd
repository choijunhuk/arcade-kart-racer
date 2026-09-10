class_name NetInterpolator
extends RefCounted

## Two authoritative samples, shortest-arc yaw and bounded extrapolation.
var _times: Array[float] = []
var _poses: Array[Transform3D] = []

## Inserts newer samples only; network duplicates cannot rewind rendering.
func push(time: float, pose: Transform3D) -> void:
	if not _times.is_empty() and time <= _times.back():
		return
	_times.append(time)
	_poses.append(pose)
	if _times.size() > 2:
		_times.pop_front()
		_poses.pop_front()

## Samples an already-delayed render timestamp (server now minus 100 ms).
func sample(time: float) -> Transform3D:
	if _poses.is_empty():
		return Transform3D.IDENTITY
	if _poses.size() == 1:
		return _poses[0]
	var span: float = _times[1] - _times[0]
	var elapsed: float = clampf(time - _times[0], 0.0, span + NetTuning.EXTRAPOLATION_SECONDS)
	var weight: float = elapsed / span
	var yaw: float = lerp_angle(_poses[0].basis.get_euler().y, _poses[1].basis.get_euler().y, weight)
	return Transform3D(Basis(Vector3.UP, yaw), _poses[0].origin.lerp(_poses[1].origin, weight))
