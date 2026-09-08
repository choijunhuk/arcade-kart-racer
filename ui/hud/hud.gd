class_name RaceHud
extends CanvasLayer

## Plain Phase 5 HUD. It observes EventBus and read-only kart/race APIs only.
## TODO(phase-9): Replace the placeholder typography/layout with final HUD art.

const GO_DISPLAY_SECONDS: float = 1.0
const SHIELD_FULL_SECONDS: float = 8.0

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _position_label: Label = $PositionLabel
@onready var _lap_label: Label = $LapLabel
@onready var _countdown_label: Label = $CountdownLabel
@onready var _wrong_way_label: Label = $WrongWayLabel
@onready var _message_label: Label = $MessageLabel
@onready var _drift_meter: DriftMeter = $DriftMeter
@onready var _item_icon: TextureRect = $ItemPanel/Icon
@onready var _item_name: Label = $ItemPanel/ItemName
@onready var _roulette_label: Label = $ItemPanel/RouletteLabel
@onready var _threat_warning: Label = $ThreatWarning
@onready var _shield_timer: TextureProgressBar = $ShieldTimer

var _player_kart: KartController
var _lap_tracker: LapTracker
var _position_tracker: PositionTracker
var _kart_count: int = 1
var _total_laps: int = 1
var _go_display_remaining: float = 0.0
var _item_manager: ItemManager
var _position_tween: Tween
var _lap_tween: Tween
var _roulette_tween: Tween
var _roulette_was_active: bool = false
var _lap_base_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	EventBus.countdown_tick.connect(_on_countdown_tick)
	EventBus.race_started.connect(_on_race_started)
	EventBus.wrong_way.connect(_on_wrong_way)
	EventBus.lap_completed.connect(_on_lap_completed)
	EventBus.kart_finished.connect(_on_kart_finished)
	EventBus.threat_warning.connect(_on_threat_warning)
	EventBus.position_changed.connect(_on_position_changed)
	_wrong_way_label.visible = false
	_message_label.text = ""
	_threat_warning.visible = false
	_shield_timer.visible = false
	_position_label.pivot_offset = _position_label.size * 0.5
	_lap_base_position = _lap_label.position


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
	_update_item_hud(delta)


## Binds the HUD to read-only race participants and tracker APIs. `player_kart`
## is null when `RaceConfig.player_slot == -1` (spec §14.2: an AI-only race,
## e.g. the headless sim), in which case the HUD simply shows nothing player-specific.
func bind(
	player_kart: KartController, lap_tracker: LapTracker,
	position_tracker: PositionTracker, kart_count: int, total_laps: int,
	item_manager: ItemManager = null,
) -> void:
	_player_kart = player_kart
	_lap_tracker = lap_tracker
	_position_tracker = position_tracker
	_kart_count = maxi(1, kart_count)
	_total_laps = maxi(1, total_laps)
	_item_manager = item_manager
	if player_kart != null:
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
	if EventBus.threat_warning.is_connected(_on_threat_warning):
		EventBus.threat_warning.disconnect(_on_threat_warning)
	if EventBus.position_changed.is_connected(_on_position_changed):
		EventBus.position_changed.disconnect(_on_position_changed)


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
	if kart != _player_kart:
		return
	_animate_lap_slide()
	if lap == _total_laps - 1:
		_message_label.text = "FINAL LAP"


func _on_kart_finished(kart: Node, _finish_time_seconds: float) -> void:
	if kart == _player_kart:
		_message_label.text = "FINISH"


func _on_threat_warning(target_kart: Node, item_id: StringName, _seconds: float) -> void:
	if target_kart != _player_kart:
		return
	var item: ItemData = _item_manager.get_item_data(item_id) if _item_manager != null else null
	var display_name: String = item.display_name if item != null else String(item_id).replace("_", " ")
	_threat_warning.text = "%s INCOMING" % display_name.to_upper()
	_threat_warning.visible = true


func _on_position_changed(kart: Node, _old_position: int, _new_position: int) -> void:
	if kart != _player_kart:
		return
	if _position_tween != null:
		_position_tween.kill()
	_position_label.scale = Vector2.ONE * tuning.position_punch_scale
	_position_tween = create_tween()
	_position_tween.tween_property(
		_position_label, "scale", Vector2.ONE, tuning.position_punch_seconds,
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_lap_slide() -> void:
	if _lap_tween != null:
		_lap_tween.kill()
	_lap_label.position = _lap_base_position - Vector2(tuning.lap_slide_distance, 0.0)
	_lap_tween = create_tween()
	_lap_tween.tween_property(
		_lap_label, "position", _lap_base_position, tuning.lap_slide_seconds,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_item_hud(_delta: float) -> void:
	if _player_kart == null:
		return
	var slot: ItemSlot = _player_kart.item_slot
	if slot.roulette_active:
		var result: ItemData = slot.get_roulette_result()
		_item_icon.texture = result.icon if result != null else null
		_start_roulette_tween()
		_roulette_label.text = "ROULETTE"
		_item_name.text = "???"
	else:
		_stop_roulette_tween()
		_roulette_label.text = ""
		var held: ItemData = slot.get_item_data()
		_item_icon.texture = held.icon if held != null else null
		_item_name.text = held.display_name if held != null else "EMPTY"
	var shield_remaining: float = _player_kart.get_shield_remaining()
	_shield_timer.visible = shield_remaining > 0.0
	_shield_timer.value = clampf(shield_remaining / SHIELD_FULL_SECONDS, 0.0, 1.0) * 100.0
	_roulette_was_active = slot.roulette_active


func _start_roulette_tween() -> void:
	if _roulette_was_active:
		return
	if _roulette_tween != null:
		_roulette_tween.kill()
	_roulette_tween = create_tween().set_loops()
	_roulette_tween.tween_property(
		_item_icon, "rotation", _item_icon.rotation + TAU, tuning.roulette_turn_seconds,
	).as_relative().set_trans(Tween.TRANS_LINEAR)


func _stop_roulette_tween() -> void:
	if not _roulette_was_active:
		return
	if _roulette_tween != null:
		_roulette_tween.kill()
	_roulette_tween = null
	_item_icon.rotation = 0.0
