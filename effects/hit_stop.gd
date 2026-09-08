class_name HitStop
extends Node

## Optional local-only item hit-stop restored after a fixed physics-tick count.

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

var _remaining_ticks: int = 0
var _previous_time_scale: float = 1.0
var _active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not EventBus.item_hit.is_connected(_on_item_hit):
		EventBus.item_hit.connect(_on_item_hit)


func _exit_tree() -> void:
	if EventBus.item_hit.is_connected(_on_item_hit):
		EventBus.item_hit.disconnect(_on_item_hit)
	_restore()


func _physics_process(_delta: float) -> void:
	step_tick()


## Rebinds tuning for isolated tests or scene overrides.
func configure(value: FeelTuning) -> void:
	tuning = value


## Starts or extends hit-stop unless disabled or in network mode.
func request(is_networked: bool) -> bool:
	if tuning == null or not tuning.hit_stop_enabled or is_networked:
		return false
	if not _active:
		_previous_time_scale = Engine.time_scale
		_active = true
	Engine.time_scale = tuning.hit_stop_time_scale
	_remaining_ticks = maxi(
		_remaining_ticks,
		ticks_for_duration(tuning.hit_stop_duration, Engine.physics_ticks_per_second),
	)
	return true


## Advances one physics tick and restores the prior scale on the boundary.
func step_tick() -> void:
	if not _active or _remaining_ticks <= 0:
		return
	_remaining_ticks -= 1
	if _remaining_ticks <= 0:
		_restore()


## Converts seconds to a conservative fixed-tick duration.
static func ticks_for_duration(duration: float, ticks_per_second: int) -> int:
	return maxi(1, ceili(maxf(duration, 0.0) * float(maxi(ticks_per_second, 1))))


func _restore() -> void:
	if not _active:
		return
	Engine.time_scale = _previous_time_scale
	_remaining_ticks = 0
	_active = false


func _on_item_hit(_source_kart: Node, _target_kart: Node, _item_id: StringName) -> void:
	request(GameState.is_networked)
