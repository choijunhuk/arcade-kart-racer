class_name NetRateLimiter
extends RefCounted

## Per-key token bucket guarding server RPC handlers against a runaway or
## malicious peer flooding input packets (spec item 6: rate-limit input
## packets per client). Pure and time-injected so it stays unit-testable.
var capacity: float
var refill_per_second: float
var _tokens: Dictionary[int, float] = {}
var _last_seen: Dictionary[int, float] = {}


func _init(bucket_capacity: float = 90.0, per_second: float = 75.0) -> void:
	capacity = bucket_capacity
	refill_per_second = per_second


## Returns true and consumes `cost` tokens if `key` may act at time `now`;
## otherwise returns false without consuming anything. `cost` defaults to 1
## (one call = one token); a caller whose single RPC does proportionally more
## work — e.g. an input batch carrying several ticks in one packet — should
## charge its real size instead, so a full batch cannot cost the same single
## token a lone frame would (review finding 5).
func allow(key: int, now: float, cost: float = 1.0) -> bool:
	var last: float = _last_seen.get(key, now)
	var tokens: float = minf(capacity, float(_tokens.get(key, capacity)) + maxf(0.0, now - last) * refill_per_second)
	_last_seen[key] = now
	if tokens < cost:
		_tokens[key] = tokens
		return false
	_tokens[key] = tokens - cost
	return true


## Drops bookkeeping for a departed peer so its id can be reused cleanly.
func remove(key: int) -> void:
	_tokens.erase(key)
	_last_seen.erase(key)
