class_name InputProvider
extends RefCounted


## Returns the input snapshot for the next physics tick.
func get_frame() -> InputFrame:
	return InputFrame.zero()
