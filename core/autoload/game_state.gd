class_name GameStateService
extends Node

signal scene_change_requested(scene_path: String)

const TRANSITION_SCENE: PackedScene = preload("res://ui/components/transition_overlay.tscn")
const TRANSITION_NODE_NAME: StringName = &"SceneTransition"

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
var pending_race_config: RaceConfig
var is_networked: bool = false


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
	pending_race_config = null
	is_networked = false


## Announces a validated scene transition request for the bootstrap coordinator.
func request_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		push_error("Cannot request missing scene: %s" % scene_path)
		return
	scene_change_requested.emit(scene_path)


## Changes to a validated PackedScene and returns the SceneTree error code.
func change_scene(scene_path: String) -> Error:
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		push_error("Cannot change to missing scene: %s" % scene_path)
		return ERR_FILE_NOT_FOUND
	scene_change_requested.emit(scene_path)
	var root: Window = get_tree().root
	if root.get_node_or_null(NodePath(String(TRANSITION_NODE_NAME))) != null:
		return ERR_BUSY
	var overlay: TransitionOverlay = TRANSITION_SCENE.instantiate() as TransitionOverlay
	overlay.name = TRANSITION_NODE_NAME
	root.add_child(overlay)
	overlay.transition_to(scene_path)
	return OK
