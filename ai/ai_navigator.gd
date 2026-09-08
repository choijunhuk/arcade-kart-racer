class_name AINavigator
extends RefCounted

## Steering-target computation (spec §13.3): look-ahead point on the racing
## line, a smoothed per-kart lane offset, shortcut entry/following, and a
## light item-box seek bias. Never decides throttle/brake/drift (AIDriver's
## job) and never writes to the kart.

const MIN_LOOK_AHEAD: float = 6.0
const MAX_LOOK_AHEAD: float = 25.0
## Exponential approach rate (1/s) for the dynamic avoid/overtake lane bias.
const LANE_SMOOTHING_RATE: float = 3.0
## Metres before `entry_offset` at which the AI commits to a shortcut go/no-go.
const SHORTCUT_DECISION_DISTANCE: float = 15.0
## Once past this far behind `entry_offset` a stale decision is discarded.
const SHORTCUT_APPROACH_RESET_DISTANCE: float = 5.0
const SHORTCUT_ALT_LOOKAHEAD: float = 8.0
const SHORTCUT_EXIT_MARGIN: float = 2.0
const ITEM_SEEK_RANGE: float = 18.0
const ITEM_SEEK_CURVATURE_MAX: float = 0.02

class NavResult extends RefCounted:
	var target_point: Vector3
	var offset: float = 0.0
	var curvature_ahead: float = 0.0
	var lane_offset: float = 0.0
	var on_shortcut: bool = false


var _racing_line: RacingLine
var _item_boxes: Array[Node3D]
var _shortcuts: Array[TrackShortcut]
var _base_lane_offset: float
var _dynamic_lane_offset: float = 0.0
var _cached_offset: float = -1.0
var _active_shortcut: TrackShortcut
var _shortcut_decision_made_for: TrackShortcut
var _shortcut_decision: bool = false
var _last_curvature_ahead: float = 0.0


func _init(racing_line: RacingLine, base_lane_offset: float, item_boxes: Array[Node3D], shortcuts: Array[TrackShortcut]) -> void:
	_racing_line = racing_line
	_base_lane_offset = base_lane_offset
	_item_boxes = item_boxes
	_shortcuts = shortcuts


## Clamp-and-scale look-ahead distance from current speed (spec §13.3).
static func compute_look_ahead(speed: float, look_ahead_time: float) -> float:
	return clampf(speed * look_ahead_time, MIN_LOOK_AHEAD, MAX_LOOK_AHEAD)


## Pure shortcut entry decision (unit-testable with a seeded RNG). Below the
## shortcut's required speed the AI never attempts it regardless of skill.
static func decide_shortcut(take_prob: float, kart_speed: float, required_speed: float, rng: RandomNumberGenerator) -> bool:
	if kart_speed < required_speed:
		return false
	return rng.randf() < take_prob


## Returns the curvature-ahead estimate from the most recent `compute()` call
## (one tick stale is fine at 30 Hz); lets AIDriver gate overtakes near apexes
## without forcing a second racing-line query the same tick.
func get_last_curvature_ahead() -> float:
	return _last_curvature_ahead


## Computes this tick's steering target, folding in lane bias/shortcuts/item-seek.
func compute(kart_pos: Vector3, speed: float, profile: AIDifficultyProfile, desired_bias: float, dt: float, rng: RandomNumberGenerator) -> NavResult:
	var result: NavResult = NavResult.new()
	if _racing_line == null:
		result.target_point = kart_pos
		return result
	var offset: float = _racing_line.offset_at(kart_pos, _cached_offset)
	_cached_offset = offset
	result.offset = offset
	result.curvature_ahead = _racing_line.max_curvature_in(offset, profile.brake_look_ahead)
	_last_curvature_ahead = result.curvature_ahead
	_update_shortcut_state(kart_pos, offset, speed, profile, rng)
	_advance_lane_offset(profile, desired_bias, dt)
	result.lane_offset = _base_lane_offset + _dynamic_lane_offset
	if _active_shortcut != null:
		result.on_shortcut = true
		result.target_point = _sample_shortcut_ahead(kart_pos)
		return result
	var look_ahead: float = compute_look_ahead(speed, profile.look_ahead_time)
	var seek_bias: float = _compute_item_seek_bias(kart_pos, offset, result.curvature_ahead)
	var right: Vector3 = _racing_line.right_at(offset + look_ahead)
	result.target_point = _racing_line.sample(offset + look_ahead) + right * (result.lane_offset + seek_bias)
	return result


func _advance_lane_offset(profile: AIDifficultyProfile, desired_bias: float, dt: float) -> void:
	var target_lane: float = clampf(_base_lane_offset + desired_bias, profile.lane_offset_min, profile.lane_offset_max)
	var smoothing: float = clampf(LANE_SMOOTHING_RATE * dt, 0.0, 1.0)
	_dynamic_lane_offset = lerpf(_dynamic_lane_offset, target_lane - _base_lane_offset, smoothing)


func _update_shortcut_state(kart_pos: Vector3, offset: float, speed: float, profile: AIDifficultyProfile, rng: RandomNumberGenerator) -> void:
	if _active_shortcut != null:
		if _reached_shortcut_exit(kart_pos):
			_active_shortcut = null
		return
	for shortcut: TrackShortcut in _shortcuts:
		var distance_to_entry: float = shortcut.entry_offset - offset
		var approaching: bool = distance_to_entry >= -SHORTCUT_APPROACH_RESET_DISTANCE and distance_to_entry <= SHORTCUT_DECISION_DISTANCE
		if not approaching:
			if _shortcut_decision_made_for == shortcut:
				_shortcut_decision_made_for = null
			continue
		if _shortcut_decision_made_for != shortcut:
			_shortcut_decision_made_for = shortcut
			_shortcut_decision = decide_shortcut(profile.shortcut_take_prob, speed, shortcut.required_speed, rng)
		if _shortcut_decision and distance_to_entry <= 0.0:
			_active_shortcut = shortcut
		return


func _reached_shortcut_exit(kart_pos: Vector3) -> bool:
	var alt: Path3D = _active_shortcut.alt_curve
	if alt == null or alt.curve == null:
		return true
	var progress: float = alt.curve.get_closest_offset(alt.to_local(kart_pos))
	return progress >= alt.curve.get_baked_length() - SHORTCUT_EXIT_MARGIN


func _sample_shortcut_ahead(kart_pos: Vector3) -> Vector3:
	var alt: Path3D = _active_shortcut.alt_curve
	if alt == null or alt.curve == null:
		return kart_pos
	var local_pos: Vector3 = alt.to_local(kart_pos)
	var closest: float = alt.curve.get_closest_offset(local_pos)
	var length: float = alt.curve.get_baked_length()
	var target_offset: float = clampf(closest + SHORTCUT_ALT_LOOKAHEAD, 0.0, length)
	return alt.to_global(alt.curve.sample_baked(target_offset))


func _compute_item_seek_bias(kart_pos: Vector3, offset: float, curvature_ahead: float) -> float:
	if absf(curvature_ahead) > ITEM_SEEK_CURVATURE_MAX or _item_boxes.is_empty():
		return 0.0
	var nearest: Node3D = null
	var nearest_dist: float = ITEM_SEEK_RANGE
	for box: Node3D in _item_boxes:
		if not is_instance_valid(box):
			continue
		var dist: float = kart_pos.distance_to(box.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = box
	if nearest == null:
		return 0.0
	# TODO(phase-7): gate this on ItemSlot.has_item() being false once ItemSlot exists.
	var right: Vector3 = _racing_line.right_at(offset)
	return clampf((nearest.global_position - kart_pos).dot(right), -1.0, 1.0)
