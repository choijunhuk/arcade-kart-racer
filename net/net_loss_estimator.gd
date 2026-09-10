class_name NetLossEstimator
extends RefCounted

## Rolling real packet-loss estimate from sequence gaps (spec item 5: the HUD
## LOSS readout must reflect traffic actually lost in transit, not just
## `NetDebugConditions.dropped`, which counts only the synthetic drops this
## process injected itself). A client feeds snapshot ticks (stride
## SNAPSHOT_INTERVAL), the server feeds each peer's input-packet tick (stride
## 1); both are monotonic sequences sampled at a fixed stride, so a hole in
## the sequence is a packet that never arrived. Pure and time-injected, so it
## is unit-testable against a fake sequence stream without any networking.

const WINDOW_SECONDS: float = 2.0
## Ignore a window with too few samples to say anything meaningful.
const MIN_SAMPLES: int = 3

## Expected distance between consecutive sequence numbers.
var stride: int = 1
var _ticks: Dictionary[int, PackedInt64Array] = {}
var _times: Dictionary[int, PackedFloat64Array] = {}


func _init(sample_stride: int = 1) -> void:
	stride = maxi(1, sample_stride)


## Records that sequence number `tick` from `key` arrived at `now`. Repeats
## and out-of-order arrivals are ignored: a chunked snapshot delivers the same
## tick several times, and only forward progress can reveal a gap.
func observe(key: int, tick: int, now: float) -> void:
	if tick < 0:
		return
	var ticks: PackedInt64Array = _ticks.get(key, PackedInt64Array())
	if not ticks.is_empty() and tick <= ticks[ticks.size() - 1]:
		return
	ticks.append(tick)
	var times: PackedFloat64Array = _times.get(key, PackedFloat64Array())
	times.append(now)
	_ticks[key] = ticks
	_times[key] = times
	_trim(key, now)


## Worst per-key loss fraction (0.0-1.0) over the trailing window, 0.0 while
## no key has enough history to judge.
func loss(now: float) -> float:
	var worst: float = 0.0
	for key: int in _ticks.keys():
		worst = maxf(worst, _key_loss(key, now))
	return worst


## Drops a departed peer's history so its id can be reused cleanly.
func remove(key: int) -> void:
	_ticks.erase(key)
	_times.erase(key)


func _key_loss(key: int, now: float) -> float:
	_trim(key, now)
	var ticks: PackedInt64Array = _ticks.get(key, PackedInt64Array())
	if ticks.size() < MIN_SAMPLES:
		return 0.0
	var span: int = int(ticks[ticks.size() - 1]) - int(ticks[0])
	var expected: int = span / stride + 1
	if expected <= ticks.size():
		return 0.0
	return clampf(1.0 - float(ticks.size()) / float(expected), 0.0, 1.0)


func _trim(key: int, now: float) -> void:
	var times: PackedFloat64Array = _times.get(key, PackedFloat64Array())
	var drop: int = 0
	while drop < times.size() and now - times[drop] > WINDOW_SECONDS:
		drop += 1
	if drop <= 0:
		return
	_times[key] = times.slice(drop)
	_ticks[key] = (_ticks[key] as PackedInt64Array).slice(drop)


## Highest tick in an input packet's batch, or -1 when it carries none: the
## packet's own sequence number for loss purposes, since a client emits
## exactly one input packet per physics tick.
static func batch_tick(data: Dictionary) -> int:
	var frames: Variant = data.get("frames", [data])
	if not frames is Array or (frames as Array).is_empty():
		return -1
	var last: Variant = (frames as Array).back()
	return int((last as Dictionary).get("tick", -1)) if last is Dictionary else -1
