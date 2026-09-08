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

var _manager: RaceManager


func _ready() -> void:
	_restart_button.pressed.connect(_on_restart_pressed)
	_track_select_button.pressed.connect(_on_track_select_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_wire_action_focus()
	visible = false


## Populates sorted driver/kart/time rows, record status, and action focus.
func show_results(entries: Array[RaceResults.Entry], manager: RaceManager) -> void:
	_manager = manager
	_clear_rows()
	_record_badge.visible = false
	var ordered: Array[RaceResults.Entry] = ResultsOrdering.by_rank(entries)
	for index: int in range(ordered.size()):
		var entry: RaceResults.Entry = ordered[index]
		var row: HBoxContainer = _create_row(entry)
		_rows.add_child(row)
		_animate_row(row, index)
		_record_badge.visible = _record_badge.visible or entry.is_new_record
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


func _wire_action_focus() -> void:
	_restart_button.focus_neighbor_left = _restart_button.get_path_to(_menu_button)
	_restart_button.focus_neighbor_right = _restart_button.get_path_to(_track_select_button)
	_track_select_button.focus_neighbor_left = _track_select_button.get_path_to(_restart_button)
	_track_select_button.focus_neighbor_right = _track_select_button.get_path_to(_menu_button)
	_menu_button.focus_neighbor_left = _menu_button.get_path_to(_track_select_button)
	_menu_button.focus_neighbor_right = _menu_button.get_path_to(_restart_button)


func _on_restart_pressed() -> void:
	if _manager != null:
		visible = false
		_manager.restart()


func _on_track_select_pressed() -> void:
	if _manager != null:
		_manager.back_to_track_select()


func _on_menu_pressed() -> void:
	if _manager != null:
		_manager.back_to_menu()
