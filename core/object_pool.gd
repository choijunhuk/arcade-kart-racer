class_name ObjectPool
extends RefCounted

## Bounded PackedScene instance pool with explicit acquire/release ownership.

var _scene: PackedScene
var _parent: Node
var _capacity: int = 0
var _created_count: int = 0
var _available: Array[Node] = []
var _active: Array[Node] = []


## Configures the scene factory, runtime parent, and hard instance capacity.
func configure(scene: PackedScene, parent: Node, capacity: int) -> void:
	_scene = scene
	_parent = parent
	_capacity = maxi(0, capacity)


## Returns a recycled or newly-created instance, or null at capacity.
func acquire() -> Node:
	var instance: Node
	if not _available.is_empty():
		instance = _available.pop_back()
	elif _created_count < _capacity and _scene != null and _parent != null:
		instance = _scene.instantiate()
		_parent.add_child(instance)
		_created_count += 1
	else:
		return null
	_active.append(instance)
	instance.process_mode = Node.PROCESS_MODE_INHERIT
	if instance is Node3D:
		(instance as Node3D).visible = true
	return instance


## Makes an active instance dormant and available for deterministic reuse.
func release(instance: Node) -> void:
	if instance == null or not _active.has(instance):
		return
	_active.erase(instance)
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	if instance is Node3D:
		(instance as Node3D).visible = false
	_available.append(instance)


## Returns the number of checked-out instances.
func get_active_count() -> int:
	return _active.size()


## Returns the number of dormant reusable instances.
func get_available_count() -> int:
	return _available.size()
