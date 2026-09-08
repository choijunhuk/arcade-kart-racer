class_name RaceHud
extends CanvasLayer

## Plain Phase 5 HUD. It observes EventBus and read-only kart/race APIs only.
## TODO(phase-9): Replace the placeholder typography/layout with final HUD art.

const GO_DISPLAY_SECONDS: float = 1.0

@onready var _position_label: Label = $PositionLabel
@onready var _lap_label: Label = $LapLabel
@onready var _countdown_label: Label = $CountdownLabel
@onready var _wrong_way_label: Label = $WrongWayLabel
@onready var _message_label: Label = $MessageLabel
@onready var _drift_meter: DriftMeter = $DriftMeter

var _player_kart: KartController
var _lap_tracker: LapTracker
var _position_tracker: PositionTracker
var _kart_count: int = 1
var _total_laps: int = 1
var _go_display_remaining: float = 0.0


func _ready() -> void:
	EventBus.countdown_tick.connect(_on_countdown_tick)
	EventBus.race_started.connect(_on_race_started)
	EventBus.wrong_way.connect(_on_wrong_way)
	EventBus.lap_completed.connect(_on_lap_completed)
	EventBus.kart_finished.connect(_on_kart_finished)
	_wrong_way_label.visible = false
	_message_label.text = ""


func _process(delta: float) -> void:
	if _player_kart != null and _lap_tracker != null and _position_tracker != null:
		var race_position: int = maxi(1, _position_tracker.get_position(_player_kart))
		var lap: int = mini(_lap_tracker.get_lap(_player_kart) + 1, _total_laps)
		_position_label.text = "%d/%d" % [race_position, _kart_count]
		_lap_label.text = "%d/%d" % [lap, _total_laps]
	if _go_display_remaining > 0.0:
		_go_display_remaining = maxf(0.0, _go_display_remaining - delta)
		if _go_display_remaining <= 0.0:
			_countdown_label.visible = false


## Binds the HUD to read-only race participants and tracker APIs.
func bind(
	player_kart: KartController, lap_tracker: LapTracker,
	position_tracker: PositionTracker, kart_count: int, total_laps: int,
) -> void:
	_player_kart = player_kart
	_lap_tracker = lap_tracker
	_position_tracker = position_tracker
	_kart_count = maxi(1, kart_count)
	_total_laps = maxi(1, total_laps)
	_drift_meter.set_controller(player_kart.drift_controller)


func _exit_tree() -> void:
	if EventBus.countdown_tick.is_connected(_on_countdown_tick):
		EventBus.countdown_tick.disconnect(_on_countdown_tick)
	if EventBus.race_started.is_connected(_on_race_started):
		EventBus.race_started.disconnect(_on_race_started)
	if EventBus.wrong_way.is_connected(_on_wrong_way):
		EventBus.wrong_way.disconnect(_on_wrong_way)
	if EventBus.lap_completed.is_connected(_on_lap_completed):
		EventBus.lap_completed.disconnect(_on_lap_completed)
	if EventBus.kart_finished.is_connected(_on_kart_finished):
		EventBus.kart_finished.disconnect(_on_kart_finished)


func _on_countdown_tick(value: int) -> void:
	_countdown_label.text = "GO" if value == 0 else str(value)
	_countdown_label.visible = true
	if value == 0:
		_go_display_remaining = GO_DISPLAY_SECONDS


func _on_race_started() -> void:
	_countdown_label.text = "GO"
	_countdown_label.visible = true
	_go_display_remaining = GO_DISPLAY_SECONDS


func _on_wrong_way(kart: Node, active: bool) -> void:
	if kart == _player_kart:
		_wrong_way_label.visible = active


func _on_lap_completed(kart: Node, lap: int, _lap_time_seconds: float) -> void:
	if kart == _player_kart and lap == _total_laps - 1:
		_message_label.text = "FINAL LAP"


func _on_kart_finished(kart: Node, _finish_time_seconds: float) -> void:
	if kart == _player_kart:
		_message_label.text = "FINISH"

