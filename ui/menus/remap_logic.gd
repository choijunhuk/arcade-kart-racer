class_name RemapLogic
extends RefCounted


## Returns remaps with a conflicting action receiving the target's old binding.
static func swap_conflict(
	remaps: Dictionary,
	target_action: StringName,
	new_event: Dictionary,
) -> Dictionary:
	var swapped: Dictionary = remaps.duplicate(true)
	var target_key: String = String(target_action)
	var target_events: Array = swapped.get(target_key, []) as Array
	var previous_event: Dictionary = {}
	if not target_events.is_empty() and target_events[0] is Dictionary:
		previous_event = (target_events[0] as Dictionary).duplicate(true)
	var conflict_key: String = _find_conflict_action(swapped, target_key, new_event)
	swapped[target_key] = [new_event.duplicate(true)]
	if not conflict_key.is_empty():
		swapped[conflict_key] = [] if previous_event.is_empty() else [previous_event]
	return swapped


static func _find_conflict_action(
	remaps: Dictionary,
	target_key: String,
	new_event: Dictionary,
) -> String:
	for action_key_value: Variant in remaps:
		var action_key: String = str(action_key_value)
		if action_key == target_key:
			continue
		var events: Array = remaps[action_key_value] as Array
		for event_value: Variant in events:
			if event_value is Dictionary and _events_match(event_value as Dictionary, new_event):
				return action_key
	return ""


static func _events_match(first: Dictionary, second: Dictionary) -> bool:
	var event_type: String = str(first.get("type", ""))
	if event_type != str(second.get("type", "")):
		return false
	match event_type:
		"key":
			return (
				int(first.get("physical_keycode", 0)) == int(second.get("physical_keycode", 0))
				and int(first.get("keycode", 0)) == int(second.get("keycode", 0))
			)
		"joy_button":
			return int(first.get("button_index", -1)) == int(second.get("button_index", -1))
		"joy_motion":
			return (
				int(first.get("axis", -1)) == int(second.get("axis", -1))
				and signf(float(first.get("axis_value", 0.0)))
				== signf(float(second.get("axis_value", 0.0)))
			)
	return false
