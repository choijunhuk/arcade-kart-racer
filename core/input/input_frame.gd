class_name InputFrame
extends RefCounted

var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var drift: bool = false
var drift_pressed: bool = false
var item: bool = false
var look_back: bool = false
var tick: int = 0


## Creates a neutral input snapshot suitable for disabled gameplay states.
static func zero() -> InputFrame:
	return InputFrame.new()


## Returns an independent copy for replay, testing, or network buffering.
func clone() -> InputFrame:
	var copy: InputFrame = InputFrame.new()
	copy.throttle = throttle
	copy.brake = brake
	copy.steer = steer
	copy.drift = drift
	copy.drift_pressed = drift_pressed
	copy.item = item
	copy.look_back = look_back
	copy.tick = tick
	return copy


## Serializes only the deterministic input contract, including one-shot edges.
func to_dict() -> Dictionary:
	return {"throttle": throttle, "brake": brake, "steer": steer, "drift": drift,
		"drift_pressed": drift_pressed, "item": item, "look_back": look_back, "tick": tick}


## Restores a previously validated recording frame without polling live input.
static func from_dict(data: Dictionary) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.throttle = float(data.get("throttle", 0.0))
	frame.brake = float(data.get("brake", 0.0))
	frame.steer = float(data.get("steer", 0.0))
	frame.drift = bool(data.get("drift", false))
	frame.drift_pressed = bool(data.get("drift_pressed", false))
	frame.item = bool(data.get("item", false))
	frame.look_back = bool(data.get("look_back", false))
	frame.tick = int(data.get("tick", 0))
	return frame
