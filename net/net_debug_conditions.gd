class_name NetDebugConditions
extends RefCounted

## Seeded transport delay/loss; reliable traffic is delayed but never discarded.
class Delivery extends RefCounted:
	var due: float
	var callback: Callable

var latency_seconds: float = 0.0
var loss: float = 0.0
var dropped: int = 0
var delivered: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _queue: Array[Delivery] = []
const MAX_QUEUED: int = 4096

func _init() -> void:
	_rng.seed = 15

## Queues a transport operation using an injected monotonic time.
func enqueue(now: float, reliable: bool, callback: Callable) -> void:
	if not reliable and _rng.randf() < loss:
		dropped += 1
		return
	if _queue.size() >= MAX_QUEUED:
		push_error("Network delay queue exhausted")
		return
	var delivery: Delivery = Delivery.new()
	delivery.due = now + latency_seconds
	delivery.callback = callback
	_queue.append(delivery)

## Delivers due operations in enqueue order, including zero-delay traffic.
func advance(now: float) -> void:
	while not _queue.is_empty() and _queue[0].due <= now:
		var delivery: Delivery = _queue.pop_front()
		if delivery.callback.is_valid():
			delivery.callback.call()
			delivered += 1

## Releases callbacks on disconnect so old sessions cannot send into new ones.
func clear() -> void:
	_queue.clear()
