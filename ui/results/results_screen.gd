class_name ResultsScreen
extends CanvasLayer

## Temporary result table with keyboard/gamepad-focused flow actions.

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _rows: VBoxContainer = $Panel/VBox/Rows
@onready var _restart_button: Button = $Panel/VBox/Actions/RestartButton
@onready var _menu_button: Button = $Panel/VBox/Actions/MenuButton

var _manager: RaceManager


func _ready() -> void:
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	visible = false


## Populates rank/time/best-lap rows and focuses Restart.
func show_results(entries: Array[RaceResults.Entry], manager: RaceManager) -> void:
	_manager = manager
	_clear_rows()
	var row_index: int = 0
	for entry: RaceResults.Entry in entries:
		var row: Label = Label.new()
		row.text = "%d  %-14s  %s  Best %s  Hits %d  Items %d" % [
			entry.rank, entry.kart_name, _format_time(entry.total_time_seconds),
			_format_time(entry.best_lap_seconds), entry.hit_count, entry.item_use_count,
		]
		_rows.add_child(row)
		_animate_row(row, row_index)
		row_index += 1
	visible = true
	_restart_button.call_deferred("grab_focus")


## Hides and clears stale rows before a restart.
func hide_results() -> void:
	visible = false
	_clear_rows()


func _format_time(seconds: float) -> String:
	return "DNF" if seconds < 0.0 else "%.3fs" % seconds


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		child.free()


func _animate_row(row: Label, row_index: int) -> void:
	row.modulate.a = 0.0
	row.position.x += tuning.results_row_offset
	var tween: Tween = create_tween()
	tween.tween_interval(tuning.results_row_delay * float(row_index))
	tween.set_parallel(true)
	tween.tween_property(row, "position:x", 0.0, tuning.results_row_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "modulate:a", 1.0, tuning.results_row_duration)


func _on_restart_pressed() -> void:
	if _manager != null:
		visible = false
		_manager.restart()


func _on_menu_pressed() -> void:
	if _manager != null:
		_manager.back_to_menu()
