class_name FinishCelebration
extends Control

## Finish-line presentation by rank (19-D item 2): a podium finish (1st-3rd)
## gets confetti rain and firework bursts in the rank colour, any other finish
## stays plain (the HUD's FINISH banner only). 2D particles on this viewport's
## HUD canvas, so split screen celebrates per player and gameplay is untouched.

const PODIUM_RANKS: int = 3
const CONFETTI_AMOUNT: int = 170
const FIREWORK_AMOUNT: int = 72
const FIREWORK_COUNT: int = 4
const FIREWORK_INTERVAL: float = 0.32
const CONFETTI_SECONDS: float = 3.2
const CONFETTI_COLORS: Array[Color] = [
	Color(1.0, 0.82, 0.12), Color(1.0, 0.46, 0.08), Color(0.3, 0.85, 1.0),
	Color(1.0, 0.25, 0.45), Color(0.93, 0.96, 1.0),
]

var _player_kart: KartController
var _lap_tracker: LapTracker
var _karts: Array[KartController] = []
var last_rank: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	EventBus.kart_finished.connect(_on_kart_finished)


func _exit_tree() -> void:
	if EventBus.kart_finished.is_connected(_on_kart_finished):
		EventBus.kart_finished.disconnect(_on_kart_finished)


func bind(player_kart: KartController, lap_tracker: LapTracker, karts: Array[KartController]) -> void:
	_player_kart = player_kart
	_lap_tracker = lap_tracker
	_karts = karts.duplicate()
	last_rank = 0
	clear()


## Finishing rank = karts already finished (finished karts rank by time).
static func finishing_rank(lap_tracker: LapTracker, karts: Array[KartController]) -> int:
	return maxi(1, RaceCompletion.count(lap_tracker, karts))


static func is_podium(rank: int) -> bool:
	return rank >= 1 and rank <= PODIUM_RANKS


func clear() -> void:
	for child: Node in get_children():
		child.queue_free()


func _on_kart_finished(kart: Node, _finish_time_seconds: float) -> void:
	if kart != _player_kart or _player_kart == null or _lap_tracker == null:
		return
	last_rank = finishing_rank(_lap_tracker, _karts)
	if is_podium(last_rank):
		celebrate(HudReadout.position_color(last_rank))


## Spawns the confetti rain and a short sequence of firework bursts.
func celebrate(rank_color: Color) -> void:
	clear()
	var confetti: CPUParticles2D = _make_particles(CONFETTI_AMOUNT, CONFETTI_SECONDS, 0.0)
	confetti.position = Vector2(size.x * 0.5, -12.0)
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(size.x * 0.5, 4.0)
	confetti.direction = Vector2.DOWN
	confetti.spread = 25.0
	confetti.gravity = Vector2(0.0, size.y * 0.35)
	confetti.initial_velocity_min = size.y * 0.15
	confetti.initial_velocity_max = size.y * 0.4
	confetti.angular_velocity_min = -360.0
	confetti.angular_velocity_max = 360.0
	confetti.scale_amount_min = maxf(4.0, size.y / 90.0)
	confetti.scale_amount_max = maxf(8.0, size.y / 48.0)
	confetti.color_initial_ramp = _palette(rank_color)
	confetti.emitting = true
	var stop: Tween = create_tween()
	stop.tween_interval(CONFETTI_SECONDS * 0.6)
	stop.tween_callback(func() -> void: confetti.emitting = false)
	for index: int in range(FIREWORK_COUNT):
		var burst: CPUParticles2D = _make_particles(FIREWORK_AMOUNT, 1.1, 1.0)
		burst.position = Vector2(size.x * (0.2 + 0.2 * float(index)), size.y * (0.22 + 0.08 * float(index % 2)))
		burst.spread = 180.0
		burst.gravity = Vector2(0.0, size.y * 0.25)
		burst.initial_velocity_min = size.y * 0.22
		burst.initial_velocity_max = size.y * 0.42
		burst.scale_amount_min = maxf(3.0, size.y / 160.0)
		burst.scale_amount_max = maxf(6.0, size.y / 80.0)
		burst.color = rank_color.lerp(CONFETTI_COLORS[index % CONFETTI_COLORS.size()], 0.35)
		burst.one_shot = true
		var tween: Tween = create_tween()
		tween.tween_interval(FIREWORK_INTERVAL * float(index))
		tween.tween_callback(func() -> void: burst.emitting = true)


func _make_particles(amount: int, lifetime: float, explosiveness: float) -> CPUParticles2D:
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = explosiveness
	particles.emitting = false
	particles.local_coords = false
	add_child(particles)
	return particles


func _palette(rank_color: Color) -> Gradient:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, rank_color)
	gradient.set_color(1, CONFETTI_COLORS[2])
	for index: int in range(CONFETTI_COLORS.size()):
		gradient.add_point(0.15 + 0.17 * float(index), CONFETTI_COLORS[index])
	return gradient
