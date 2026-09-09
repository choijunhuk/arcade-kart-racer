class_name RecordingInputProvider
extends InputProvider

## Decorates the real driver input at its consumption boundary, one frame per tick.

var source: InputProvider
var recording: GhostRecording
var pending_events: Array[Dictionary] = []
var movers: Array[MovingObstacle] = []


func _init(provider: InputProvider) -> void:
	source = provider


## Samples once and records an independent value before the kart filters input.
func get_frame() -> InputFrame:
	var frame: InputFrame = source.get_frame()
	if recording != null and recording.frames.size() < GhostRecording.MAX_TICKS:
		var data: Dictionary = frame.to_dict()
		data["events"] = pending_events.duplicate(true)
		data["movers"] = GhostWorldReplay.capture(movers)
		recording.frames.append(data)
	pending_events.clear()
	return frame


## Queues a track effect for the next input tick without recording it twice.
func record_event(event: Dictionary) -> void:
	if recording != null:
		pending_events.append(event.duplicate(true))
