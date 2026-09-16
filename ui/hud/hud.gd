class_name RaceHud
extends CanvasLayer

## Final race HUD. It observes EventBus and read-only kart/race APIs only.

const GO_DISPLAY_SECONDS: float = 1.0
const SHIELD_FULL_SECONDS: float = 8.0
const METRES_PER_SECOND_TO_KPH: float = 3.6
const PERCENT_MAX: float = 100.0
const COMPACT_MAX_WIDTH: float = 900.0
const COMPACT_MAX_HEIGHT: float = 520.0

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _position_label: Label = $PositionLabel
@onready var _position_count_label: Label = $PositionCountLabel
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
@onready var _cooldown_bar: ProgressBar = $ItemPanel/CooldownBar
@onready var _minimap: RaceMinimap = $Minimap
@onready var _speedometer: PanelContainer = $Speedometer
@onready var _speed_label: Label = $Speedometer/SpeedLabel
@onready var _net_quality_label: Label = $NetQualityLabel
@onready var _reconnecting_overlay: Control = $ReconnectingOverlay

var _net_quality: RaceHudNetQuality = RaceHudNetQuality.new()
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
var _threat_remaining: float = 0.0
var _time_trial: TimeTrialGhost
var _time_label: Label
var _compact_layout: bool = false
var _mirrored: bool = false
## Cached `gameplay.speedometer`; refreshed from settings_changed instead of re-reading SettingsManager every _process frame.
var _speedometer_enabled: bool = true


func _ready() -> void:
	_refresh_speedometer_setting(&"gameplay")
	SettingsManager.settings_changed.connect(_refresh_speedometer_setting)
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
		_position_label.text = str(race_position)
		_position_count_label.text = "/%d" % _kart_count
		_lap_label.text = "LAP %d/%d" % [lap, _total_laps]
		_speed_label.text = "%03d km/h" % roundi(absf(_player_kart.get_speed()) * METRES_PER_SECOND_TO_KPH)
	_speedometer.visible = not _compact_layout and _speedometer_enabled
	if _go_display_remaining > 0.0:
		_go_display_remaining = maxf(0.0, _go_display_remaining - delta)
		if _go_display_remaining <= 0.0:
			_countdown_label.visible = false
	if _threat_remaining > 0.0:
		_threat_remaining = maxf(0.0, _threat_remaining - delta)
		if _threat_remaining <= 0.0:
			_threat_warning.visible = false
	_update_item_hud(delta)
	if _time_trial != null and _time_label != null:
		var best: String = "--" if _time_trial.best_seconds() < 0.0 else "%.3f" % _time_trial.best_seconds()
		var ghost_delta: String = "--" if _time_trial.best == null else "%+.3f" % _time_trial.delta_seconds()
		_time_label.text = "TIME %.3f\nBEST %s\nGHOST %s" % [_time_trial.current_seconds(), best, ghost_delta]
	if _net_quality.is_bound():
		_net_quality.update()


## Shows ping/loss and a "reconnecting" overlay for a networked client (spec item 5).
func bind_network(session: NetSession) -> void:
	_net_quality.bind(session, _net_quality_label, _reconnecting_overlay)


## Binds the HUD to read-only race participants and tracker APIs. `player_kart` is null when `RaceConfig.player_slot == -1` (spec §14.2: an AI-only
## race, e.g. the headless sim), in which case the HUD simply shows nothing player-specific.
func bind(
	player_kart: KartController, lap_tracker: LapTracker,
	position_tracker: PositionTracker, kart_count: int, total_laps: int,
	item_manager: ItemManager = null,
	racing_line: RacingLine = null,
	karts: Array[KartController] = [],
) -> void:
	_player_kart = player_kart
	_lap_tracker = lap_tracker
	_position_tracker = position_tracker
	_kart_count = maxi(1, kart_count)
	_total_laps = maxi(1, total_laps)
	_item_manager = item_manager
	if player_kart != null:
		_drift_meter.set_controller(player_kart.drift_controller)
	_minimap.bind(racing_line, karts, player_kart)


## Selects whether this player's viewport pays the minimap rendering cost.
func set_minimap_visible(minimap_visible: bool) -> void:
	_minimap.visible = minimap_visible


## Re-flips the minimap so it reads mirrored with the world while SplitScreen's own counter-flip keeps everything else legible (spec §18e).
func set_mirrored(mirrored: bool) -> void:
	_mirrored = mirrored
	_minimap.scale = Vector2(-1.0, 1.0) if _mirrored else Vector2.ONE
	_minimap.pivot_offset = _minimap.size * 0.5


## Pure viewport-local geometry used by split-screen and headless tests.
static func layout_for_viewport(viewport_size: Vector2) -> Dictionary:
	var compact: bool = viewport_size.x <= COMPACT_MAX_WIDTH or viewport_size.y <= COMPACT_MAX_HEIGHT
	if compact:
		return {
			"compact": true,
			"speedometer_visible": false,
			"regions": {
				"position": Rect2(12.0, 12.0, 150.0, 88.0),
				"minimap": Rect2(12.0, viewport_size.y - 120.0, 140.0, 108.0),
				"drift": Rect2(viewport_size.x * 0.5 - 120.0, viewport_size.y - 60.0, 240.0, 44.0),
				"item": Rect2(viewport_size.x - 152.0, 12.0, 140.0, 100.0),
				"speedometer": Rect2(),
			},
		}
	return {
		"compact": false,
		"speedometer_visible": true,
		"regions": {
			"position": Rect2(24.0, 20.0, 190.0, 122.0),
			"minimap": Rect2(24.0, viewport_size.y - 224.0, 260.0, 200.0),
			"drift": Rect2(viewport_size.x * 0.5 - 210.0, viewport_size.y - 98.0, 420.0, 72.0),
			"item": Rect2(viewport_size.x - 244.0, 238.0, 220.0, 160.0),
			"speedometer": Rect2(viewport_size.x * 0.5 + 228.0, viewport_size.y - 98.0, 170.0, 72.0),
		},
	}


## Applies a full or compact layout after the owning SubViewport is resized.
func apply_viewport_layout(viewport_size: Vector2) -> void:
	var layout: Dictionary = layout_for_viewport(viewport_size)
	var regions: Dictionary = layout["regions"] as Dictionary
	_compact_layout = bool(layout["compact"])
	_set_rect($PositionPanel, regions["position"])
	_set_rect(_minimap, regions["minimap"])
	_set_rect(_drift_meter, regions["drift"])
	_set_rect($ItemPanel, regions["item"])
	_set_rect(_shield_timer, (regions["item"] as Rect2).grow(6.0))
	_set_rect(_speedometer, regions["speedometer"])
	_apply_text_layout(viewport_size)
	_apply_panel_contents()
	_speedometer.visible = not _compact_layout and _speedometer_enabled
	_lap_base_position = _lap_label.position
	_position_label.pivot_offset = _position_label.size * 0.5
	_minimap.refresh_layout()
	set_mirrored(_mirrored)


func _apply_text_layout(viewport_size: Vector2) -> void:
	if _compact_layout:
		_set_rect(_position_label, Rect2(22.0, 14.0, 60.0, 48.0))
		_set_rect(_position_count_label, Rect2(82.0, 28.0, 68.0, 32.0))
		_set_rect(_lap_label, Rect2(22.0, 64.0, 128.0, 24.0))
		_set_rect(_countdown_label, Rect2(viewport_size * 0.5 - Vector2(90.0, 60.0), Vector2(180.0, 120.0)))
		_set_rect(_wrong_way_label, Rect2(viewport_size * 0.5 + Vector2(-140.0, 48.0), Vector2(280.0, 40.0)))
		_set_rect(_message_label, Rect2(0.0, 72.0, viewport_size.x, 36.0))
		_set_rect(_threat_warning, Rect2(viewport_size.x * 0.5 - 180.0, 18.0, 360.0, 34.0))
	else:
		_set_rect(_position_label, Rect2(42.0, 26.0, 82.0, 78.0))
		_set_rect(_position_count_label, Rect2(124.0, 56.0, 70.0, 44.0))
		_set_rect(_lap_label, Rect2(42.0, 104.0, 152.0, 32.0))
		_set_rect(_countdown_label, Rect2(viewport_size * 0.5 - Vector2(180.0, 130.0), Vector2(360.0, 260.0)))
		_set_rect(_wrong_way_label, Rect2(viewport_size * 0.5 + Vector2(-260.0, 110.0), Vector2(520.0, 60.0)))
		_set_rect(_message_label, Rect2(0.0, 94.0, viewport_size.x, 56.0))
		_set_rect(_threat_warning, Rect2(viewport_size.x * 0.5 - 350.0, 24.0, 700.0, 54.0))
	_position_label.add_theme_font_size_override("font_size", 40 if _compact_layout else 64)
	_position_count_label.add_theme_font_size_override("font_size", 20 if _compact_layout else 28)
	_lap_label.add_theme_font_size_override("font_size", 16 if _compact_layout else 22)
	_countdown_label.add_theme_font_size_override("font_size", 64 if _compact_layout else 112)
	_wrong_way_label.add_theme_font_size_override("font_size", 28 if _compact_layout else 42)
	_message_label.add_theme_font_size_override("font_size", 24 if _compact_layout else 38)
	_threat_warning.add_theme_font_size_override("font_size", 20 if _compact_layout else 30)


func _apply_panel_contents() -> void:
	_minimap.custom_minimum_size = Vector2(140.0, 108.0) if _compact_layout else Vector2(260.0, 200.0)
	_drift_meter.custom_minimum_size = Vector2(240.0, 44.0) if _compact_layout else Vector2(420.0, 72.0)
	var charge_bar: ProgressBar = _drift_meter.get_node("Panel/ChargeBar") as ProgressBar
	charge_bar.custom_minimum_size = Vector2(220.0, 26.0) if _compact_layout else Vector2(400.0, 42.0)
	if _compact_layout:
		_set_rect(_item_icon, Rect2(47.0, 5.0, 46.0, 46.0))
		_set_rect(_item_name, Rect2(0.0, 54.0, 140.0, 18.0))
		_set_rect(_roulette_label, Rect2(0.0, 71.0, 140.0, 16.0))
		_set_rect(_cooldown_bar, Rect2(10.0, 88.0, 120.0, 9.0))
	else:
		_set_rect(_item_icon, Rect2(74.0, 10.0, 72.0, 72.0))
		_set_rect(_item_name, Rect2(0.0, 86.0, 220.0, 28.0))
		_set_rect(_roulette_label, Rect2(0.0, 110.0, 220.0, 24.0))
		_set_rect(_cooldown_bar, Rect2(16.0, 136.0, 188.0, 15.0))
	_item_icon.pivot_offset = _item_icon.size * 0.5
	_item_name.add_theme_font_size_override("font_size", 14 if _compact_layout else 22)
	_roulette_label.add_theme_font_size_override("font_size", 12 if _compact_layout else 16)
	_speed_label.add_theme_font_size_override("font_size", 18 if _compact_layout else 24)


func _set_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size


## Returns the kart observed by this HUD for integration checks and adapters.
func get_bound_kart() -> KartController:
	return _player_kart


## Displays time-trial timing independently of the standard rank/item panels.
func bind_time_trial(trial: TimeTrialGhost) -> void:
	_time_trial = trial
	if _time_label == null:
		_time_label = Label.new()
		_time_label.name = "TimeTrialTiming"
		_time_label.position = Vector2(35.0, 180.0)
		_time_label.add_theme_font_size_override("font_size", 24)
		add_child(_time_label)
	_time_label.visible = trial != null
	$ItemPanel.visible = trial == null
	_position_label.visible = trial == null
	_position_count_label.visible = trial == null


func _refresh_speedometer_setting(section: StringName) -> void:
	if section == &"gameplay":
		_speedometer_enabled = bool(SettingsManager.get_setting(&"gameplay", &"speedometer", true))


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_refresh_speedometer_setting):
		SettingsManager.settings_changed.disconnect(_refresh_speedometer_setting)
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
	_net_quality.unbind()


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


func _on_threat_warning(target_kart: Node, item_id: StringName, seconds: float) -> void:
	if target_kart != _player_kart:
		return
	var item: ItemData = _item_manager.get_item_data(item_id) if _item_manager != null else null
	var display_name: String = item.display_name if item != null else String(item_id).replace("_", " ")
	_threat_warning.text = "%s INCOMING" % display_name.to_upper()
	_threat_warning.visible = true
	_threat_remaining = maxf(seconds, 0.0)


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
	_shield_timer.value = clampf(shield_remaining / SHIELD_FULL_SECONDS, 0.0, 1.0) * PERCENT_MAX
	_cooldown_bar.value = _item_manager.get_cooldown_ratio(_player_kart) * PERCENT_MAX if _item_manager != null else 0.0
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
