class_name TutorialController
extends CanvasLayer

## Onboarding HUD: shows a short top-of-screen instruction + input glyph per
## stage, advances `TutorialStageMachine` from real EventBus signals and kart
## input, and restarts the countdown once so the start-boost-timing stage
## (spec §1 item 4) has a countdown to react to. Skippable at any time via the
## on-screen button; never binds `pause`/`ui_cancel` so it cannot fight ESC.

signal tutorial_finished(completed: bool)

const UNBOUND_TEXT: String = "UNBOUND"
const FINISH_DELAY_SECONDS: float = 2.0
const MENU_SCENE_PATH: String = "res://scenes/main.tscn"
## test_loop is a shared asset reused by ~20 other tests; the ramp for stage 5
## is spawned at runtime into this tutorial's own Track instance instead of
## being baked into the shared .tscn, so no other test's track geometry changes.
const JUMP_PAD_SCENE: PackedScene = preload("res://track/elements/jump_pad.tscn")
const JUMP_PAD_NODE_NAME: StringName = &"TutorialRampJump"
const JUMP_PAD_POSITION: Vector3 = Vector3(25.0, 0.15, -22.0)
const JUMP_PAD_ROTATION_DEGREES: Vector3 = Vector3(0.0, 90.0, 0.0)

const STAGE_TEXT: Dictionary = {
	TutorialStageMachine.Stage.ACCELERATE: "ACCELERATE to start moving",
	TutorialStageMachine.Stage.STEER: "STEER through the turn",
	TutorialStageMachine.Stage.DRIFT_RELEASE: "HOLD DRIFT through the corner, then release for a boost",
	TutorialStageMachine.Stage.START_BOOST: "Restarting the line... hold ACCELERATE right before GO for a start boost",
	TutorialStageMachine.Stage.RAMP_TRICK: "Hit the ramp and HOLD DRIFT in the air for a trick boost",
	TutorialStageMachine.Stage.ITEM_PICKUP: "Drive through an ITEM BOX",
	TutorialStageMachine.Stage.ITEM_USE: "USE ITEM to fire it",
}

const STAGE_ACTION: Dictionary = {
	TutorialStageMachine.Stage.ACCELERATE: &"accelerate",
	TutorialStageMachine.Stage.DRIFT_RELEASE: &"drift",
	TutorialStageMachine.Stage.START_BOOST: &"accelerate",
	TutorialStageMachine.Stage.RAMP_TRICK: &"drift",
	TutorialStageMachine.Stage.ITEM_USE: &"use_item",
}

@onready var _instruction_label: Label = $Panel/VBox/InstructionLabel
@onready var _glyph_label: Label = $Panel/VBox/GlyphLabel
@onready var _skip_button: Button = $SkipButton
@onready var _race_manager: RaceManager = get_parent().get_node("Race") as RaceManager

var _machine: TutorialStageMachine = TutorialStageMachine.new()
var _player_kart: KartController
var _finished: bool = false
var _start_boost_restart_triggered: bool = false


func _ready() -> void:
	_skip_button.pressed.connect(_on_skip_pressed)
	EventBus.boost_started.connect(_on_boost_started)
	EventBus.roulette_started.connect(_on_roulette_started)
	EventBus.item_used.connect(_on_item_used)
	_spawn_jump_pad()
	_refresh_instruction()


func _exit_tree() -> void:
	if EventBus.boost_started.is_connected(_on_boost_started):
		EventBus.boost_started.disconnect(_on_boost_started)
	if EventBus.roulette_started.is_connected(_on_roulette_started):
		EventBus.roulette_started.disconnect(_on_roulette_started)
	if EventBus.item_used.is_connected(_on_item_used):
		EventBus.item_used.disconnect(_on_item_used)


func _process(_delta: float) -> void:
	if _finished or _race_manager == null:
		return
	var humans: Array[KartController] = _race_manager.get_human_karts()
	_player_kart = humans[0] if not humans.is_empty() else null
	if _player_kart == null:
		return
	_machine.on_kart_sample(_player_kart.get_speed(), _player_kart.get_throttle_input(), _player_kart.get_steer_input())
	if _machine.current_stage() == TutorialStageMachine.Stage.START_BOOST and not _start_boost_restart_triggered:
		_start_boost_restart_triggered = true
		_race_manager.restart()
		_spawn_jump_pad() # restart() rebuilds the Track instance from scratch.
	_check_progress()


func _on_boost_started(kart: Node, _spec: Resource) -> void:
	if _finished or kart != _player_kart:
		return
	_machine.on_boost_started((kart as KartController).get_boost_source())
	_check_progress()


func _on_roulette_started(kart: Node) -> void:
	if _finished or kart != _player_kart:
		return
	_machine.on_item_box_collected()
	_check_progress()


func _on_item_used(kart: Node, _item_id: StringName) -> void:
	if _finished or kart != _player_kart:
		return
	_machine.on_item_used()
	_check_progress()


func _check_progress() -> void:
	if _machine.is_complete():
		_finish(true)
	else:
		_refresh_instruction()


func _refresh_instruction() -> void:
	var stage: TutorialStageMachine.Stage = _machine.current_stage()
	_instruction_label.text = String(STAGE_TEXT.get(stage, ""))
	_glyph_label.text = _glyph_text(stage)


func _glyph_text(stage: TutorialStageMachine.Stage) -> String:
	if stage == TutorialStageMachine.Stage.STEER:
		return "%s / %s" % [_action_text(&"steer_left"), _action_text(&"steer_right")]
	var action: StringName = STAGE_ACTION.get(stage, &"")
	return _action_text(action) if action != &"" else ""


func _action_text(action: StringName) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return events[0].as_text() if not events.is_empty() else UNBOUND_TEXT


## Adds this tutorial run's ramp into its own Track instance (see the
## JUMP_PAD_SCENE comment above); never touches the shared test_loop asset.
func _spawn_jump_pad() -> void:
	var track: Node = _race_manager.get_node_or_null("Track")
	if track == null or track.has_node(String(JUMP_PAD_NODE_NAME)):
		return
	var pad: Area3D = JUMP_PAD_SCENE.instantiate() as Area3D
	pad.name = JUMP_PAD_NODE_NAME
	pad.position = JUMP_PAD_POSITION
	pad.rotation_degrees = JUMP_PAD_ROTATION_DEGREES
	track.add_child(pad)


func _on_skip_pressed() -> void:
	_finish(false)


func _finish(completed: bool) -> void:
	if _finished:
		return
	_finished = true
	SettingsManager.update_setting(&"tutorial", &"tutorial_done", true)
	GameState.tutorial_active = false
	_instruction_label.text = "TUTORIAL COMPLETE!" if completed else "TUTORIAL SKIPPED"
	_glyph_label.text = ""
	_skip_button.visible = false
	tutorial_finished.emit(completed)
	await get_tree().create_timer(FINISH_DELAY_SECONDS).timeout
	GameState.change_scene(MENU_SCENE_PATH)
