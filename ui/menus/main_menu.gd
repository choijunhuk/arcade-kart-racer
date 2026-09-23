class_name MainMenu
extends MenuScreen

const MODE_SELECT_PATH: String = "res://ui/menus/mode_select.tscn"
const SETTINGS_PATH: String = "res://ui/menus/settings_menu.tscn"
const INTRO_OFFSET: float = -80.0
const INTRO_SECONDS: float = 0.36
const INTRO_STAGGER: float = 0.055

@onready var _play_button: Button = $Panel/VBox/PlayButton
@onready var _time_trial_button: Button = $Panel/VBox/TimeTrialButton
@onready var _online_button: Button = $Panel/VBox/OnlineButton
@onready var _settings_button: Button = $Panel/VBox/SettingsButton
@onready var _quit_button: Button = $Panel/VBox/QuitButton
@onready var _tutorial_prompt: PanelContainer = $TutorialPrompt
@onready var _start_tutorial_button: Button = $TutorialPrompt/VBox/StartTutorialButton
@onready var _skip_tutorial_button: Button = $TutorialPrompt/VBox/SkipTutorialButton


func _ready() -> void:
	super._ready()
	GameState.reset_session()
	GameState.current_mode = GameState.Mode.MENU
	($Footer/Version as Label).text = "v%s" % str(ProjectSettings.get_setting("application/config/version", ""))
	_play_intro.call_deferred()
	_play_button.pressed.connect(go_to.bind(MODE_SELECT_PATH))
	_time_trial_button.pressed.connect(_start_time_trial)
	_settings_button.pressed.connect(go_to.bind(SETTINGS_PATH))
	_online_button.pressed.connect(go_to.bind("res://ui/menus/online_lobby.tscn"))
	($Panel/VBox/NetworkMessage as Label).text = GameState.network_message
	GameState.network_message = ""
	_quit_button.pressed.connect(_quit_game)
	wire_vertical_focus([_play_button, _time_trial_button, _online_button, _settings_button, _quit_button])
	focus_initial(_play_button)
	_start_tutorial_button.pressed.connect(_on_start_tutorial_pressed)
	_skip_tutorial_button.pressed.connect(_on_skip_tutorial_pressed)
	_maybe_show_first_run_prompt()


## Shows the first-run tutorial offer; never seen by automated/headless runs
## (GUT tests, snapshot/perf probes, the sim harness) or once already handled.
func _maybe_show_first_run_prompt() -> void:
	if DisplayServer.get_name() == "headless" or GameState.automation_mode:
		return
	if bool(SettingsManager.get_setting(&"tutorial", &"tutorial_done", false)):
		return
	_tutorial_prompt.visible = true
	for button: Button in [_play_button, _time_trial_button, _online_button, _settings_button, _quit_button]:
		button.disabled = true
	wire_vertical_focus([_start_tutorial_button, _skip_tutorial_button])
	focus_initial(_start_tutorial_button)


func _on_start_tutorial_pressed() -> void:
	TutorialLauncher.start(self)


func _on_skip_tutorial_pressed() -> void:
	SettingsManager.update_setting(&"tutorial", &"tutorial_done", true)
	_tutorial_prompt.visible = false
	for button: Button in [_play_button, _time_trial_button, _online_button, _settings_button, _quit_button]:
		button.disabled = false
	wire_vertical_focus([_play_button, _time_trial_button, _online_button, _settings_button, _quit_button])
	focus_initial(_play_button)


func _quit_game() -> void:
	GameState.request_quit() # Spec item 2: lets NetUpnp veto for a live worker/permanent-lease removal, instead of quitting outright.


## Logo and buttons sweep in from the left, staggered (after layout, so the
## container has already placed them).
func _play_intro() -> void:
	var index: int = 0
	for child: Node in $Panel/VBox.get_children():
		var control: Control = child as Control
		if control == null or not control.visible:
			continue
		var rest_x: float = control.position.x
		control.position.x = rest_x + INTRO_OFFSET
		control.modulate.a = 0.0
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(control, "position:x", rest_x, INTRO_SECONDS).set_delay(INTRO_STAGGER * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(control, "modulate:a", 1.0, INTRO_SECONDS).set_delay(INTRO_STAGGER * index)
		index += 1


func _start_time_trial() -> void:
	GameState.selected_race_mode = RaceConfig.RaceMode.TIME_TRIAL
	go_to("res://ui/menus/driver_select.tscn")
