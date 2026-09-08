class_name AIInputProvider
extends InputProvider

## Thin frame relay (spec §13.2): `AIController` computes one `InputFrame`
## per AI tick (30 Hz) and stores it here; `KartController` polls `get_frame()`
## every physics tick (60 Hz), so the same frame is served more than once
## between AI ticks.

var _frame: InputFrame = InputFrame.zero()


## Replaces the frame served until the next AI tick overwrites it.
func set_frame(frame: InputFrame) -> void:
	_frame = frame


func get_frame() -> InputFrame:
	return _frame
