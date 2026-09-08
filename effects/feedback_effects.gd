class_name FeedbackEffects
extends Node3D

## Race-local pooled impact renderer subscribed only to presentation events.

const IMPACT_SCENE: PackedScene = preload("res://effects/impact_effect.tscn")
## Minimum seconds between "pool exhausted" warnings, so a burst of drops
## (e.g. an 8-kart pileup) does not spam the log once per dropped effect.
const POOL_WARNING_INTERVAL: float = 5.0

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

var _pool: ObjectPool = ObjectPool.new()
var _active: Array[ImpactEffect] = []
var _pool_warning_cooldown: float = 0.0


func _ready() -> void:
	_pool.configure(IMPACT_SCENE, self, tuning.impact_pool_capacity)
	EventBus.item_exploded.connect(_on_item_exploded)
	EventBus.wall_head_on.connect(_on_wall_head_on)
	EventBus.kart_landed.connect(_on_kart_landed)


func _exit_tree() -> void:
	if EventBus.item_exploded.is_connected(_on_item_exploded):
		EventBus.item_exploded.disconnect(_on_item_exploded)
	if EventBus.wall_head_on.is_connected(_on_wall_head_on):
		EventBus.wall_head_on.disconnect(_on_wall_head_on)
	if EventBus.kart_landed.is_connected(_on_kart_landed):
		EventBus.kart_landed.disconnect(_on_kart_landed)
	_pool.clear()
	_active.clear()


func _process(delta: float) -> void:
	_pool_warning_cooldown = maxf(0.0, _pool_warning_cooldown - delta)
	for effect: ImpactEffect in _active.duplicate():
		if effect.tick(delta):
			_active.erase(effect)
			_pool.release(effect)


func _play(world_position: Vector3, kind: ImpactEffect.Kind) -> void:
	var effect: ImpactEffect = _pool.acquire() as ImpactEffect
	if effect == null:
		# Pool is at capacity: drop this impact rather than block gameplay or grow
		# the pool unbounded. Rate-limit the warning (§29.9) so a pileup that
		# exhausts the pool many times per second doesn't spam the log.
		if _pool_warning_cooldown <= 0.0:
			push_warning("FeedbackEffects: impact pool exhausted, dropping effect kind=%d" % kind)
			_pool_warning_cooldown = POOL_WARNING_INTERVAL
		return
	effect.play(world_position, kind)
	_active.append(effect)


func _on_item_exploded(world_position: Vector3) -> void:
	_play(world_position, ImpactEffect.Kind.ITEM)


func _on_wall_head_on(kart: Node) -> void:
	if kart is KartController:
		var controller: KartController = kart as KartController
		_play(controller.global_position - controller.get_forward(), ImpactEffect.Kind.WALL)


func _on_kart_landed(kart: Node, vertical_speed: float) -> void:
	if kart is KartController and vertical_speed >= tuning.landing_dust_min_speed:
		_play((kart as KartController).global_position, ImpactEffect.Kind.LANDING)
