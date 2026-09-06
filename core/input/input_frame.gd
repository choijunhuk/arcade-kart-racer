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
