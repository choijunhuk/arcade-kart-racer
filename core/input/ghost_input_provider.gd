class_name GhostInputProvider
extends InputProvider

## Replays a saved input stream once, with neutral input after its final tick.

var cursor: int = 0
var recording: GhostRecording
var kart: KartController
var before_frame: Callable


func _init(source: GhostRecording = null, target: KartController = null) -> void:
	recording = source
	kart = target


## Consumes one independent frame and its external effects, never live user input.
func get_frame() -> InputFrame:
	if recording == null or cursor >= recording.frames.size():
		return InputFrame.zero()
	var data: Dictionary = recording.frames[cursor]
	cursor += 1
	if before_frame.is_valid():
		before_frame.call(data)
	if kart != null:
		for event: Dictionary in data.get("events", []):
			KartReplayState.apply_event(kart, event)
	return InputFrame.from_dict(data)
