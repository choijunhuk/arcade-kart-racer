class_name FlowInputProvider
extends ScriptedInputProvider

## Drives the player through real kart physics and slot cooldowns during flow tests.

var _tick: int = 0


func get_frame() -> InputFrame:
	var frame: InputFrame = super.get_frame()
	_tick += 1
	frame.tick = _tick
	frame.item = (_kart as KartController).item_slot.has_item()
	return frame
