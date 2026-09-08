class_name AIController
extends Node3D

## Ticks its Sensors -> Navigator -> Driver -> ItemBrain pipeline (spec §13.2)
## at `profile.ai_tick_hz` with a per-kart phase offset (spec §26) and writes
## the result into its own `AIInputProvider`. Extends Node3D (not a plain
## Node) purely so `AISensors`'s `ShapeCast3D` children inherit the owning
## kart's transform correctly (Node3D only looks at its *direct* parent).
## Never touches kart physics directly.

var _kart: KartController
var _track: TrackRoot
var _context: AIRaceContext
var _profile: AIDifficultyProfile
var _rng: RandomNumberGenerator
var _sensors: AISensors
var _navigator: AINavigator
var _driver: AIDriver
var _item_brain: AIItemBrain
var _input_provider: AIInputProvider = AIInputProvider.new()
var _tick_interval: float = 1.0 / 30.0
var _tick_accumulator: float = 0.0
var _last_lane_offset: float = 0.0


## Wires every dependency and rolls this kart's fixed random seed. Call once
## right after `add_child()`. `phase_offset` (seconds, spec §26) staggers AI
## ticks across karts so they do not all re-shapecast on the same frame.
func setup(kart: KartController, track: TrackRoot, context: AIRaceContext, profile: AIDifficultyProfile, rng: RandomNumberGenerator, phase_offset: float = 0.0) -> void:
	if not AIDifficulty.validate(profile):
		return
	_kart = kart
	_track = track
	_context = context
	_profile = profile
	_rng = rng
	_tick_interval = AIDifficulty.tick_interval(profile)
	_tick_accumulator = phase_offset
	_sensors = AISensors.new()
	add_child(_sensors)
	_sensors.setup(kart)
	var base_lane_offset: float = AIDifficulty.sample_base_lane_offset(profile, rng)
	_navigator = AINavigator.new(context.racing_line, base_lane_offset, _item_box_anchors(), _shortcuts())
	_driver = AIDriver.new(rng)
	_driver.plan_start_boost(kart, profile)
	_item_brain = AIItemBrain.new(rng)
	kart.set_input_provider(_input_provider)


func _physics_process(delta: float) -> void:
	if _kart == null or not is_instance_valid(_kart):
		return
	_tick_accumulator += delta
	if _tick_accumulator < _tick_interval:
		return
	_tick_accumulator -= _tick_interval
	_run_tick(_tick_interval)


## Returns the input provider driving this AI's kart.
func get_input_provider() -> AIInputProvider:
	return _input_provider


## Returns the current rubber-band multiplier for debug overlays (spec §13.7).
func get_rubber_band_mult() -> float:
	return _driver.get_rubber_band_mult() if _driver != null else 1.0


## Returns the current smoothed lane offset for debug overlays.
func get_lane_offset() -> float:
	return _last_lane_offset


## Returns the most recent target speed estimate for debug overlays.
func get_target_speed() -> float:
	return _driver.get_last_target_speed() if _driver != null else 0.0


func _run_tick(dt: float) -> void:
	var sensor_report: AISensors.SensorReport = _sensors.tick()
	var avoid_bias: float = AIDriver.compute_avoid_bias(sensor_report, AIDriver.AVOID_STRENGTH)
	var overtake_bias: float = AIDriver.compute_overtake_bias(sensor_report, _profile, _navigator.get_last_curvature_ahead())
	var bias: float = clampf(avoid_bias + overtake_bias, _profile.lane_offset_min, _profile.lane_offset_max)
	var nav: AINavigator.NavResult = _navigator.compute(_kart.global_position, _kart.get_speed(), _profile, bias, dt, _rng)
	var frame: InputFrame = _driver.compute_frame(_kart, _profile, nav, sensor_report, _context, dt)
	_evaluate_item_use(frame, sensor_report, nav)
	_input_provider.set_frame(frame)
	_last_lane_offset = nav.lane_offset


## PLACEHOLDER(phase-7): `ItemSlotView`/`AIItemUseProfile` are stand-ins until
## a real `ItemSlot` exists; `view.has_item()` is always false so this never
## actually fires, but the full Sensors->Navigator->Driver->ItemBrain pipeline
## from spec §13.2 is exercised structurally.
func _evaluate_item_use(frame: InputFrame, sensor_report: AISensors.SensorReport, nav: AINavigator.NavResult) -> void:
	var view: ItemSlotView = ItemSlotView.new()
	var use_profile: AIItemUseProfile = AIItemUseProfile.new()
	var decision_context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	decision_context.kart_ahead_distance = sensor_report.kart_ahead_distance
	decision_context.kart_ahead_in_fire_cone = sensor_report.kart_ahead_side == AISensors.Side.CENTER and sensor_report.kart_ahead_distance <= use_profile.fire_range
	decision_context.rear_kart_distance = sensor_report.rear_kart_distance
	decision_context.curvature_ahead = nav.curvature_ahead
	decision_context.is_boosting = _kart.is_boosting()
	decision_context.incoming_projectile = sensor_report.incoming_projectile
	decision_context.rank = _context.position_tracker.get_position(_kart) if _context.position_tracker != null else 8
	frame.item = _item_brain.should_use(view, use_profile, _profile, decision_context, _tick_interval)


func _item_box_anchors() -> Array[Node3D]:
	return _track.get_item_box_anchors() if _track != null else []


func _shortcuts() -> Array[TrackShortcut]:
	var result: Array[TrackShortcut] = []
	if _track == null:
		return result
	var container: Node = _track.get_node_or_null("Shortcuts")
	if container == null:
		return result
	for child: Node in container.get_children():
		if child is TrackShortcut:
			result.append(child as TrackShortcut)
	return result
