class_name TripleDart
extends ProjectileItem

## One pooled volley owns three ordinary darts; the manager remains data-driven.

const DART_SCENE: PackedScene = preload("res://items/instances/rocket_dart/rocket_dart.tscn")
const DART_COUNT: int = 3
@export var spread_degrees: float = 12.0

var _darts: Array[ProjectileItem] = []


## Returns a symmetric, normalized spread around the supplied forward vector.
static func spread_directions(forward: Vector3, angle_degrees: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for index: int in range(DART_COUNT):
		var angle: float = deg_to_rad(angle_degrees * float(index - 1))
		result.append(forward.normalized().rotated(Vector3.UP, angle))
	return result


## Resets reused children and launches a front or rear three-dart volley.
func activate(frame: InputFrame) -> void:
	super.activate(frame)
	if _darts.is_empty():
		for index: int in range(DART_COUNT):
			var dart: ProjectileItem = DART_SCENE.instantiate() as ProjectileItem
			dart.name = "Dart%d" % index
			add_child(dart)
			_darts.append(dart)
	var directions: Array[Vector3] = spread_directions(direction, spread_degrees)
	for index: int in range(DART_COUNT):
		var dart: ProjectileItem = _darts[index]
		dart.setup(data, owner_kart, context)
		dart.activate(frame)
		dart.direction = directions[index]
		dart.global_position = owner_kart.global_position + dart.direction * SPAWN_FORWARD_OFFSET
		var manager: ItemManager = context.get_item_manager() as ItemManager
		if manager != null:
			manager.active_projectiles.append(dart)


## Advances each dart independently and returns the volley when all have expired.
func tick(dt: float) -> void:
	if _advance_lifetime(dt):
		return
	var remaining: int = 0
	for dart: ProjectileItem in _darts:
		if not dart.is_expired():
			dart.tick(dt)
		dart.visible = not dart.is_expired()
		if dart.is_expired():
			_unregister_dart(dart)
		if not dart.is_expired():
			remaining += 1
	if remaining == 0:
		expire()


## A volley counts as one pool lease, but reserves three projectile budget slots.
func can_spawn(_active_items: Array[ItemBase]) -> bool:
	var manager: ItemManager = context.get_item_manager() as ItemManager
	return manager == null or manager.active_projectiles.size() + DART_COUNT <= manager.max_active_projectiles


## AI/shields observe the moving dart children, not the stationary volley owner.
func is_projectile() -> bool:
	return false


## Releases all child registry entries before the manager returns the volley pool.
func expire() -> void:
	for dart: ProjectileItem in _darts:
		dart.expire()
		_unregister_dart(dart)
	super.expire()


func _unregister_dart(dart: ProjectileItem) -> void:
	var manager: ItemManager = context.get_item_manager() as ItemManager
	if is_instance_valid(manager):
		manager.active_projectiles.erase(dart)
