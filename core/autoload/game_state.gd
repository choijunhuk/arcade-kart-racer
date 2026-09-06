class_name GameStateService
extends Node

signal scene_change_requested(scene_path: String)

enum Mode {
	BOOT,
	SANDBOX,
	MENU,
	RACE,
}

var current_mode: Mode = Mode.BOOT
var selected_driver_id: StringName = &""
var selected_kart_id: StringName = &""
var selected_track_id: StringName = &""


## Stores the content identifiers selected for the next race session.
func set_selection(driver_id: StringName, kart_id: StringName, track_id: StringName) -> void:
	selected_driver_id = driver_id
	selected_kart_id = kart_id
	selected_track_id = track_id


## Clears transient session selections and returns to bootstrap mode.
func reset_session() -> void:
	current_mode = Mode.BOOT
	selected_driver_id = &""
	selected_kart_id = &""
	selected_track_id = &""


## Announces a validated scene transition request for the bootstrap coordinator.
func request_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		push_error("Cannot request missing scene: %s" % scene_path)
		return
	scene_change_requested.emit(scene_path)
