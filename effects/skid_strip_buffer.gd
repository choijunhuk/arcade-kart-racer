class_name SkidStripBuffer
extends RefCounted

## Fixed-capacity chronological point buffer for one continuous skid strip.

var _points: Array[Vector3] = []
var _capacity: int = 1
var _head: int = 0
var _count: int = 0


## Resets storage for at most `max_segments + 1` joined edge points.
func configure(max_segments: int) -> void:
	_capacity = maxi(max_segments, 0) + 1
	_points.resize(_capacity)
	_head = 0
	_count = 0


## Appends one point, overwriting the oldest when the ring is full.
func add_point(point: Vector3) -> void:
	if _count < _capacity:
		_points[(_head + _count) % _capacity] = point
		_count += 1
	else:
		_points[_head] = point
		_head = (_head + 1) % _capacity


## Returns points oldest-to-newest without exposing ring storage order.
func get_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	result.resize(_count)
	for index: int in range(_count):
		result[index] = _points[(_head + index) % _capacity]
	return result


## Returns the number of drawable joined quads.
func get_segment_count() -> int:
	return maxi(_count - 1, 0)
