class_name RaceHud
extends CanvasLayer

## Final race HUD. It observes EventBus and read-only kart/race APIs only.

const GO_DISPLAY_SECONDS: float = 1.0
const SHIELD_FULL_SECONDS: float = 8.0
const METRES_PER_SECOND_TO_KPH: float = 3.6
const PERCENT_MAX: float = 100.0
const COMPACT_MAX_WIDTH: float = HudLayout.COMPACT_MAX_WIDTH
const COMPACT_MAX_HEIGHT: float = HudLayout.COMPACT_MAX_HEIGHT
const COUNTDOWN_COLORS: Array[Color] = [
	Color(0.3, 1.0, 0.45), Color(1.0, 0.82, 0.12), Color(1.0, 0.55, 0.12), Color(1.0, 0.25, 0.2),
]
const COUNTDOWN_POP_SCALE: float = 1.9
const COUNTDOWN_POP_SECONDS: float = 0.32
const BANNER_POP_SECONDS: float = 0.28
const WRONG_WAY_PULSE_SECONDS: float = 0.45
const RESULTS_FADE_SECONDS: float = 0.3

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _position_label: Label = $PositionLabel
@onready var _ordinal_label: Label = $OrdinalLabel
@onready var _position_count_label: Label = $PositionCountLabel
@onready var _lap_label: Label = $LapLabel
@onready var _timer_label: Label = $TimerLabel
@onready var _split_label: Label = $SplitLabel
@onready var _countdown_label: Label = $CountdownLabel
@onready var _wrong_way_label: Label = $WrongWayLabel
@onready var _message_label: Label = $MessageLabel
@onready var _drift_meter: DriftMeter = $DriftMeter
@onready var _item_panel: HudItemSlot = $ItemPanel
@onready var _threat_warning: Label = $ThreatWarning
@onready var _shield_timer: TextureProgressBar = $ShieldTimer
@onready var _minimap: RaceMinimap = $Minimap
@onready var _speedometer: SpeedGauge = $Speedometer
@onready var _speed_label: Label = $Speedometer/SpeedLabel
@onready var _net_quality_label: Label = $NetQualityLabel
@onready var _reconnecting_overlay: Control = $ReconnectingOverlay
## Layer-wide tint: its alpha fades the whole HUD canvas (per viewport).
@onready var _fade: CanvasModulate = $Fade

var _net_quality: RaceHudNetQuality = RaceHudNetQuality.new()
var _readout: HudReadout = HudReadout.new()
var _player_kart: KartController
var _lap_tracker: LapTracker
var _position_tracker: PositionTracker
var _kart_count: int = 1
var _total_laps: int = 1
var _go_display_remaining: float = 0.0
var _item_manager: ItemManager
var _position_tween: Tween
var _lap_tween: Tween
var _countdown_tween: Tween
var _message_tween: Tween
var _wrong_way_tween: Tween
var _results_fade_tween: Tween
var _shown_position: int = 0
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
	EventBus.race_state_changed.connect(_on_race_state_changed)
	_wrong_way_label.visible = false
	_message_label.text = ""
	_threat_warning.visible = false
	_shield_timer.visible = false
	_countdown_label.visible = false
	for label: Label in [_position_label, _ordinal_label, _countdown_label, _message_label, _wrong_way_label]:
		label.pivot_offset = label.size * 0.5
	_lap_base_position = _lap_label.position
	_item_panel.layout(false)


func _process(delta: float) -> void:
	if _player_kart != null and _lap_tracker != null and _position_tracker != null:
		_update_race_readout()
		var speed: float = absf(_player_kart.get_speed())
		_speed_label.text = str(roundi(speed * METRES_PER_SECOND_TO_KPH))
		_speedometer.ratio = _player_kart.get_speed_ratio()
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


func _update_race_readout() -> void:
	var race_position: int = maxi(1, _position_tracker.get_position(_player_kart))
	var lap: int = mini(_lap_tracker.get_lap(_player_kart) + 1, _total_laps)
	if race_position != _shown_position:
		_shown_position = race_position
		var color: Color = HudReadout.position_color(race_position)
		_position_label.add_theme_color_override("font_color", color)
		_ordinal_label.add_theme_color_override("font_color", color)
	_position_label.text = str(race_position)
	_ordinal_label.text = HudReadout.ordinal_suffix(race_position)
	_position_count_label.text = "/%d" % _kart_count
	_lap_label.text = "LAP %d/%d" % [lap, _total_laps]
	var finished: bool = _lap_tracker.is_finished(_player_kart)
	var seconds: float = _lap_tracker.get_finish_time(_player_kart) if finished else _lap_tracker.network_race_seconds()
	_timer_label.text = HudReadout.format_time(seconds)
	_split_label.text = _readout.split_text()


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
	_readout.reset()
	if player_kart != null:
		_drift_meter.set_controller(player_kart.drift_controller)
	_minimap.bind(racing_line, karts, player_kart)
	($Celebration as FinishCelebration).bind(player_kart, lap_tracker, karts)
	($NameTags as RaceNameTags).bind(player_kart, position_tracker, karts)


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
	var compact: bool = HudLayout.is_compact(viewport_size)
	return {
		"compact": compact,
		"speedometer_visible": not compact,
		"regions": HudLayout.regions(viewport_size),
	}


## Applies a full or compact layout after the owning SubViewport is resized.
func apply_viewport_layout(viewport_size: Vector2) -> void:
	var layout: Dictionary = layout_for_viewport(viewport_size)
	var regions: Dictionary = layout["regions"] as Dictionary
	_compact_layout = bool(layout["compact"])
	HudLayout.set_rect($PositionPanel, regions["position"])
	HudLayout.set_rect(_minimap, regions["minimap"])
	HudLayout.set_rect(_drift_meter, regions["drift"])
	HudLayout.set_rect(_item_panel, regions["item"])
	HudLayout.set_rect(_speedometer, regions["speedometer"])
	HudLayout.apply_text(self, viewport_size, _compact_layout)
	_minimap.custom_minimum_size = (regions["minimap"] as Rect2).size
	_drift_meter.custom_minimum_size = (regions["drift"] as Rect2).size
	_item_panel.layout(_compact_layout)
	var item_rect: Rect2 = regions["item"] as Rect2
	var disc: float = minf(item_rect.size.x, item_rect.size.y - maxf(16.0, item_rect.size.y * HudItemSlot.LABEL_HEIGHT_RATIO)) - 8.0
	HudLayout.set_rect(_shield_timer, Rect2(item_rect.position + Vector2((item_rect.size.x - disc) * 0.5, 4.0), Vector2.ONE * disc).grow(10.0))
	_split_label.visible = not _compact_layout and _time_trial == null
	_speedometer.visible = not _compact_layout and _speedometer_enabled
	_lap_base_position = _lap_label.position
	_minimap.refresh_layout()
	set_mirrored(_mirrored)


## Returns the kart observed by this HUD for integration checks and adapters.
func get_bound_kart() -> KartController:
	return _player_kart


## Displays time-trial timing independently of the standard rank/item panels.
func bind_time_trial(trial: TimeTrialGhost) -> void:
	_time_trial = trial
	if _time_label == null:
		_time_label = Label.new()
		_time_label.name = "TimeTrialTiming"
		_time_label.theme = _lap_label.theme
		_time_label.theme_type_variation = &"HudText"
		_time_label.position = Vector2(36.0, 158.0)
		_time_label.add_theme_font_size_override("font_size", 24)
		add_child(_time_label)
	_time_label.visible = trial != null
	$ItemPanel.visible = trial == null
	for label: Label in [_position_label, _ordinal_label, _position_count_label, _timer_label, _split_label]:
		label.visible = trial == null


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
	if EventBus.race_state_changed.is_connected(_on_race_state_changed):
		EventBus.race_state_changed.disconnect(_on_race_state_changed)
	_net_quality.unbind()


## Fades every HUD element out while the results screen owns the view (both
## the authoritative and the network-replica RESULTS paths emit this), and
## back in for any other state, e.g. a restart's countdown. Per viewport, so
## each split-screen HUD fades on its own.
func _on_race_state_changed(_old_state: int, new_state: int) -> void:
	var target: Color = Color(1.0, 1.0, 1.0, 0.0 if new_state == RaceState.RESULTS else 1.0)
	if _results_fade_tween != null:
		_results_fade_tween.kill()
	_results_fade_tween = create_tween()
	_results_fade_tween.tween_property(_fade, "color", target, RESULTS_FADE_SECONDS)


func _on_countdown_tick(value: int) -> void:
	_countdown_label.text = "GO" if value == 0 else str(value)
	_countdown_label.visible = true
	_pop_countdown(value)
	if value == 0:
		_go_display_remaining = GO_DISPLAY_SECONDS
	else:
		_readout.reset()
		_message_label.text = ""


func _on_race_started() -> void:
	_countdown_label.text = "GO"
	_countdown_label.visible = true
	_pop_countdown(0)
	_go_display_remaining = GO_DISPLAY_SECONDS


func _pop_countdown(value: int) -> void:
	_countdown_label.add_theme_color_override("font_color", COUNTDOWN_COLORS[clampi(value, 0, COUNTDOWN_COLORS.size() - 1)])
	if _countdown_tween != null:
		_countdown_tween.kill()
	_countdown_label.scale = Vector2.ONE * COUNTDOWN_POP_SCALE
	_countdown_label.modulate.a = 0.0
	_countdown_tween = create_tween().set_parallel(true)
	_countdown_tween.tween_property(_countdown_label, "scale", Vector2.ONE, COUNTDOWN_POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_countdown_tween.tween_property(_countdown_label, "modulate:a", 1.0, COUNTDOWN_POP_SECONDS * 0.5)
	if value == 0:
		_countdown_tween.chain().tween_property(_countdown_label, "scale", Vector2.ONE * 1.25, GO_DISPLAY_SECONDS * 0.6)
		_countdown_tween.tween_property(_countdown_label, "modulate:a", 0.0, GO_DISPLAY_SECONDS * 0.6)


func _on_wrong_way(kart: Node, active: bool) -> void:
	if kart != _player_kart:
		return
	_wrong_way_label.visible = active
	if _wrong_way_tween != null:
		_wrong_way_tween.kill()
		_wrong_way_tween = null
	_wrong_way_label.modulate.a = 1.0
	if active:
		_wrong_way_tween = create_tween().set_loops()
		_wrong_way_tween.tween_property(_wrong_way_label, "modulate:a", 0.45, WRONG_WAY_PULSE_SECONDS)
		_wrong_way_tween.tween_property(_wrong_way_label, "modulate:a", 1.0, WRONG_WAY_PULSE_SECONDS)


func _on_lap_completed(kart: Node, lap: int, lap_time_seconds: float) -> void:
	if kart != _player_kart:
		return
	_readout.record_lap(lap_time_seconds)
	_animate_lap_slide()
	if lap == _total_laps - 1:
		_show_banner("FINAL LAP")


func _on_kart_finished(kart: Node, _finish_time_seconds: float) -> void:
	if kart == _player_kart:
		_show_banner("FINISH")


func _show_banner(text: String) -> void:
	_message_label.text = text
	if _message_tween != null:
		_message_tween.kill()
	_message_label.scale = Vector2(1.6, 0.4)
	_message_label.modulate.a = 0.0
	_message_tween = create_tween().set_parallel(true)
	_message_tween.tween_property(_message_label, "scale", Vector2.ONE, BANNER_POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_message_tween.tween_property(_message_label, "modulate:a", 1.0, BANNER_POP_SECONDS * 0.6)


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
	_ordinal_label.scale = Vector2.ONE * tuning.position_punch_scale
	_position_tween = create_tween().set_parallel(true)
	for label: Label in [_position_label, _ordinal_label]:
		_position_tween.tween_property(
			label, "scale", Vector2.ONE, tuning.position_punch_seconds * 2.5,
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_lap_slide() -> void:
	if _lap_tween != null:
		_lap_tween.kill()
	_lap_label.position = _lap_base_position - Vector2(tuning.lap_slide_distance, 0.0)
	_lap_tween = create_tween()
	_lap_tween.tween_property(
		_lap_label, "position", _lap_base_position, tuning.lap_slide_seconds,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_item_hud(delta: float) -> void:
	if _player_kart == null:
		return
	var cooldown: float = _item_manager.get_cooldown_ratio(_player_kart) if _item_manager != null else 0.0
	_item_panel.observe(_player_kart.item_slot, cooldown, delta)
	var shield_remaining: float = _player_kart.get_shield_remaining()
	_shield_timer.visible = shield_remaining > 0.0
	_shield_timer.value = clampf(shield_remaining / SHIELD_FULL_SECONDS, 0.0, 1.0) * PERCENT_MAX
