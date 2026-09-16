class_name GameStateService
extends Node

signal scene_change_requested(scene_path: String)

const TRANSITION_SCENE: PackedScene = preload("res://ui/components/transition_overlay.tscn")
const TRANSITION_NODE_NAME: StringName = &"SceneTransition"
## A TransitionOverlay renames itself to this once its load failed, so it no
## longer counts as the busy marker and the next change_scene() can replace it.
const LOAD_ERROR_NODE_NAME: StringName = &"LoadErrorOverlay"

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
var selected_race_mode: RaceConfig.RaceMode = RaceConfig.RaceMode.SINGLE_RACE
var selected_items_enabled: bool = true
var selected_speed_class: RaceConfig.SpeedClass = RaceConfig.SpeedClass.STANDARD
var grand_prix_state: GrandPrix
## Set by automated tools (snapshot/perf probes): disables focus-loss pause and
## other human-only conveniences so unattended windows keep running, and mutes
## the master bus so windowed harness runs never play sound at the developer.
var automation_mode: bool = false:
	set(value):
		automation_mode = value
		_mute_audio(value)
## True while a TutorialController-driven onboarding race is active; gates the
## first-race contextual hints so they never fire during the tutorial itself.
var tutorial_active: bool = false
var is_networked: bool = false
var net_session: NetSession
var network_message: String = ""


## Stores the content identifiers selected for the next race session.
func set_selection(driver_id: StringName, kart_id: StringName, track_id: StringName) -> void:
	selected_driver_id = driver_id
	selected_kart_id = kart_id
	selected_track_id = track_id


## Clears transient session selections and returns to bootstrap mode.
func reset_session() -> void:
	if net_session != null:
		net_session.close()
	current_mode = Mode.BOOT
	selected_driver_id = &""
	selected_kart_id = &""
	selected_track_id = &""
	pending_race_config = null
	selected_race_mode = RaceConfig.RaceMode.SINGLE_RACE
	selected_items_enabled = true
	selected_speed_class = RaceConfig.SpeedClass.STANDARD
	grand_prix_state = null
	is_networked = false
	tutorial_active = false


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
	var root: Window = get_tree().root
	if root.get_node_or_null(NodePath(String(TRANSITION_NODE_NAME))) != null:
		return ERR_BUSY
	# Only announce a request that is actually going to run.
	scene_change_requested.emit(scene_path)
	var stale_error: Node = root.get_node_or_null(NodePath(String(LOAD_ERROR_NODE_NAME)))
	if stale_error != null:
		root.remove_child(stale_error)
		stale_error.queue_free()
	var overlay: TransitionOverlay = TRANSITION_SCENE.instantiate() as TransitionOverlay
	overlay.name = TRANSITION_NODE_NAME
	root.add_child(overlay)
	overlay.transition_to(scene_path)
	return OK


## Mutes/unmutes the master bus; used by automation_mode so unattended windowed
## tools stay silent. No-ops when the bus is missing (bare test harnesses).
func _mute_audio(muted: bool) -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, muted)
