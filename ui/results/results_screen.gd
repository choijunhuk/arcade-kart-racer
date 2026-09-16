class_name ResultsScreen
extends CanvasLayer

const POSITION_WIDTH: float = 70.0
const NAME_WIDTH: float = 175.0
const TIME_WIDTH: float = 145.0
const RECORD_WIDTH: float = 125.0
const ROW_SEPARATION: int = 8
const MILLISECONDS_PER_MINUTE: int = 60_000
const MILLISECONDS_PER_SECOND: int = 1_000
const SECONDS_PER_MINUTE: int = 60

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _rows: VBoxContainer = $Panel/VBox/Rows
@onready var _record_badge: Label = $Panel/VBox/NewRecordBadge
@onready var _restart_button: Button = $Panel/VBox/Actions/RestartButton
@onready var _track_select_button: Button = $Panel/VBox/Actions/TrackSelectButton
@onready var _menu_button: Button = $Panel/VBox/Actions/MenuButton
@onready var _back_to_lobby_button: Button = $Panel/VBox/Actions/BackToLobbyButton

var _manager: RaceManager
var _gp_label: Label
var _class_label: Label
var _is_grand_prix: bool = false
## True once MENU has been pressed once as a listen host with other players
## present (mirrors PauseMenu's networked overlay): the next press actually
## ends the session. Reset whenever results are (re)shown.
var _pending_end_session_confirm: bool = false


func _ready() -> void:
	UiAudio.attach($Panel)
	ButtonMotion.attach($Panel)
	_restart_button.pressed.connect(_on_restart_pressed)
	_track_select_button.pressed.connect(_on_track_select_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_back_to_lobby_button.pressed.connect(_on_back_to_lobby_pressed)
	_wire_action_focus()
	visible = false


## Populates sorted driver/kart/time rows, record status, and action focus.
func show_results(entries: Array[RaceResults.Entry], manager: RaceManager) -> void:
	_manager = manager
	_is_grand_prix = GameState.grand_prix_state != null
	_rows.custom_minimum_size.y = 0.0 if _is_grand_prix else 420.0
	_rows.add_theme_constant_override("separation", 4 if _is_grand_prix else 7)
	_clear_rows()
	_record_badge.visible = false
	var ordered: Array[RaceResults.Entry] = ResultsOrdering.by_rank(entries)
	for index: int in range(ordered.size()):
		var entry: RaceResults.Entry = ordered[index]
		var row: HBoxContainer = _create_row(entry)
		_rows.add_child(row)
		_animate_row(row, index)
		_record_badge.visible = _record_badge.visible or entry.is_new_record
	_show_grand_prix()
	_show_speed_class()
	_back_to_lobby_button.visible = is_instance_valid(GameState.net_session)
	_pending_end_session_confirm = false
	_menu_button.text = "END SESSION" if _ends_session_for_everyone() else "MAIN MENU"
	_wire_action_focus()
	visible = true
	_restart_button.call_deferred("grab_focus")


## Hides and clears stale rows before a restart.
func hide_results() -> void:
	visible = false
	_clear_rows()


func _create_row(entry: RaceResults.Entry) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row%d" % entry.rank
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	if entry.is_human:
		row.modulate = Color(1.0, 0.88, 0.42, 1.0)
	_add_cell(row, &"Position", str(entry.rank), POSITION_WIDTH)
	_add_cell(row, &"Driver", entry.driver_name, NAME_WIDTH)
	var kart_name: String = entry.kart_display_name if not entry.kart_display_name.is_empty() else entry.kart_name
	_add_cell(row, &"Kart", kart_name, NAME_WIDTH)
	_add_cell(row, &"Total", _format_time(entry.total_time_seconds), TIME_WIDTH)
	_add_cell(row, &"BestLap", _format_time(entry.best_lap_seconds), TIME_WIDTH)
	_add_cell(row, &"Record", "NEW RECORD" if entry.is_new_record else "", RECORD_WIDTH)
	return row


func _add_cell(row: HBoxContainer, cell_name: StringName, text: String, width: float) -> void:
	var label: Label = Label.new()
	label.name = cell_name
	label.custom_minimum_size.x = width
	label.text = text
	if _is_grand_prix:
		label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(label)


func _format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "DNF"
	var milliseconds: int = roundi(seconds * float(MILLISECONDS_PER_SECOND))
	var minutes: int = milliseconds / MILLISECONDS_PER_MINUTE
	var whole_seconds: int = (milliseconds / MILLISECONDS_PER_SECOND) % SECONDS_PER_MINUTE
	var remainder: int = milliseconds % MILLISECONDS_PER_SECOND
	return "%02d:%02d.%03d" % [minutes, whole_seconds, remainder]


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		child.free()


func _animate_row(row: Control, row_index: int) -> void:
	row.modulate.a = 0.0
	row.position.x += tuning.results_row_offset
	var tween: Tween = create_tween()
	tween.tween_interval(tuning.results_row_delay * float(row_index))
	tween.set_parallel(true)
	tween.tween_property(row, "position:x", 0.0, tuning.results_row_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "modulate:a", 1.0, tuning.results_row_duration)


## Shows the race's speed class (spec §18e step 7); hidden outside a race
## session (e.g. a headless sim that never populates GameState).
func _show_speed_class() -> void:
	var config: RaceConfig = GameState.pending_race_config
	if _class_label == null:
		_class_label = Label.new()
		_class_label.name = "SpeedClassLabel"
		_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		$Panel/VBox.add_child(_class_label)
		$Panel/VBox.move_child(_class_label, 1)
	_class_label.visible = config != null
	if config != null:
		var text: String = "CLASS: %s" % SpeedClassStats.display_name(config.speed_class)
		_class_label.text = "%s • MIRROR" % text if config.mirror else text


## Wraps left/right focus over the buttons that are actually shown; a hidden
## BACK TO LOBBY in the chain would otherwise dead-end gamepad navigation.
func _wire_action_focus() -> void:
	var buttons: Array[Button] = []
	for button: Button in [_restart_button, _track_select_button, _menu_button, _back_to_lobby_button]:
		if button.visible:
			buttons.append(button)
	for index: int in range(buttons.size()):
		var previous: Button = buttons[(index - 1 + buttons.size()) % buttons.size()]
		var next: Button = buttons[(index + 1) % buttons.size()]
		buttons[index].focus_neighbor_left = buttons[index].get_path_to(previous)
		buttons[index].focus_neighbor_right = buttons[index].get_path_to(next)


func _on_restart_pressed() -> void:
	if _manager != null:
		visible = false
		if _is_grand_prix:
			if RaceModes.next_grand_prix_race():
				GameState.change_scene("res://race/race.tscn")
			else:
				_manager.back_to_menu()
		else:
			_manager.restart()


func _on_track_select_pressed() -> void:
	if _manager != null:
		GameState.grand_prix_state = null
		GameState.selected_race_mode = RaceConfig.RaceMode.SINGLE_RACE
		_manager.back_to_track_select()


## Reuses PauseMenu's "ends session for everyone" predicate and confirm
## flow (review finding 3): a listen host on RESULTS with other players
## still connected must not end everyone's session from a single press —
## `back_to_menu()` closes the session unconditionally. Plain clients (and
## an offline race) never satisfy the predicate, so MENU stays single-press.
func _on_menu_pressed() -> void:
	if _manager == null:
		return
	if _ends_session_for_everyone() and not _pending_end_session_confirm:
		_pending_end_session_confirm = true
		_menu_button.text = "CONFIRM END SESSION?"
		return
	_manager.back_to_menu()

## Same predicate as `PauseMenu._ends_session_for_everyone()`: true only for
## a listen host with other players still in the session.
func _ends_session_for_everyone() -> bool:
	var session: NetSession = GameState.net_session
	return is_instance_valid(session) and session.multiplayer.is_server() and session.players.size() > 1


## Networked-only (spec item 3): unlike the other actions, this neither
## closes the session nor touches the race state machine — it reopens the
## shared online lobby scene, re-bound to the still-alive NetSession, so
## host and clients regroup instead of the client sitting on RESULTS forever.
## Every peer clears its own local race state unconditionally (review
## finding 2): a non-host that skipped this kept a dangling `session.race`,
## which made its next `_prepare_race` bail out and ack a race it never
## loaded, corrupting the host's loaded count. A non-host only clears its
## own `race`/`preparing` (`NetSession.clear_local_race_state()`) — `started`
## stays true until the host's own `restart_to_lobby()` broadcast clears it
## for everyone, so the lobby's `mid_race` gate keeps showing the waiting
## state instead of a stale "choose driver/kart" while the server is still
## mid-race. Only the host additionally rebroadcasts the lobby, since it
## alone owns the authoritative roster.
func _on_back_to_lobby_pressed() -> void:
	var session: NetSession = GameState.net_session
	if not is_instance_valid(session):
		return
	visible = false
	if session.multiplayer.is_server():
		session.restart_to_lobby()
	else:
		session.clear_local_race_state()
	GameState.change_scene("res://ui/menus/online_lobby.tscn")


func _show_grand_prix() -> void:
	var gp: GrandPrix = GameState.grand_prix_state
	_is_grand_prix = gp != null
	_restart_button.text = "RESTART"
	if _gp_label == null:
		_gp_label = Label.new()
		_gp_label.name = "GrandPrixStandings"
		_gp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_gp_label.add_theme_font_size_override("font_size", 18)
		$Panel/VBox.add_child(_gp_label)
		$Panel/VBox.move_child(_gp_label, _rows.get_index() + 1)
	_gp_label.visible = _is_grand_prix
	if not _is_grand_prix:
		return
	var standings: Array[GrandPrix.Standing] = gp.standings()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("GP PODIUM • HORIZON CUP" if gp.is_complete() else "GP STANDINGS • ROUND %d/%d" % [gp.round_index + 1, gp.tracks.size()])
	if gp.is_complete():
		var podium: PackedStringArray = PackedStringArray()
		for index: int in range(mini(3, standings.size())):
			podium.append("%d  %s" % [index + 1, standings[index].driver_name])
		lines.append("  |  ".join(podium))
	for index: int in range(0, standings.size(), 2):
		var row: PackedStringArray = PackedStringArray()
		for slot: int in range(index, mini(index + 2, standings.size())):
			row.append("%d. %s  %d pts" % [slot + 1, standings[slot].driver_name, standings[slot].points])
		lines.append("     •     ".join(row))
	_gp_label.text = "\n".join(lines)
	_restart_button.text = "FINISH CUP" if gp.is_complete() else "NEXT RACE"
