class_name NetInputBuffer
extends RefCounted

## Bounded per-peer tick buffer; missing ticks repeat levels, never one-shot edges.
var last_processed_tick: int = 0
var _pending: Dictionary[int, InputFrame] = {}
var _last: InputFrame = InputFrame.zero()

## Accepts unique future ticks within a bounded window, copying caller-owned input.
func insert(frame: InputFrame) -> bool:
	if frame.tick <= last_processed_tick or frame.tick > last_processed_tick + NetTuning.HISTORY_TICKS:
		return false
	if _pending.has(frame.tick) or not is_finite(frame.throttle) or not is_finite(frame.brake) or not is_finite(frame.steer):
		return false
	var copy: InputFrame = frame.clone()
	copy.throttle = clampf(copy.throttle, 0.0, 1.0)
	copy.brake = clampf(copy.brake, 0.0, 1.0)
	copy.steer = clampf(copy.steer, -1.0, 1.0)
	_pending[copy.tick] = copy
	return true

## Advances through one decided tick. A missed tick is acknowledged as repeated.
func consume(tick: int) -> InputFrame:
	if tick <= last_processed_tick:
		return _last.clone()
	var frame: InputFrame = _pending.get(tick) as InputFrame
	if frame == null:
		frame = _last.clone()
		frame.item = false
		frame.drift_pressed = false
	frame.tick = tick
	last_processed_tick = tick
	_last = frame.clone()
	for key: int in _pending.keys():
		if key <= tick:
			_pending.erase(key)
	return frame.clone()
