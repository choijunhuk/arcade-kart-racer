class_name ItemManager
extends Node

## Race-local deterministic item selection, activation, ticking, and pooling.

const DEFAULT_TABLE: ItemTableData = preload("res://data/item_tables/default_8_karts.tres")
const ITEM_DATA_DIRECTORY: String = "res://data/items"
const DEFAULT_MAX_ACTIVE_PROJECTILES: int = 16

@export var item_table: ItemTableData = DEFAULT_TABLE
@export var max_active_projectiles: int = DEFAULT_MAX_ACTIVE_PROJECTILES
@export var items_enabled: bool = true

var active_projectiles: Array[ItemBase] = []

var _position_tracker: PositionTracker
var _racing_line: RacingLine
var _collision_resolver: KartCollisionResolver
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _context: ItemContext = ItemContext.new()
var _karts: Array[KartController] = []
var _slots: Dictionary[int, ItemSlot] = {}
var _previous_item_ids: Dictionary[int, StringName] = {}
var _cooldowns: Dictionary[int, float] = {}
var _cooldown_durations: Dictionary[int, float] = {}
var _items_by_id: Dictionary[StringName, ItemData] = {}
var _pools: Dictionary[String, ObjectPool] = {}
var _live_items: Array[ItemBase] = []
var _pending_finished: Array[ItemBase] = []


func _ready() -> void:
	_load_item_catalog()
	if not EventBus.item_defense_triggered.is_connected(notify_leader_immunity):
		EventBus.item_defense_triggered.connect(notify_leader_immunity)


func _exit_tree() -> void:
	if EventBus.item_defense_triggered.is_connected(notify_leader_immunity):
		EventBus.item_defense_triggered.disconnect(notify_leader_immunity)
	for item: ItemBase in _live_items:
		if item.finished.is_connected(_on_item_finished):
			item.finished.disconnect(_on_item_finished)
	for pool_value: ObjectPool in _pools.values():
		pool_value.clear()
	_live_items.clear()
	active_projectiles.clear()
	_pending_finished.clear()
	_pools.clear()
	_items_by_id.clear()
	_context.configure([], null, null, null, null)


func _physics_process(delta: float) -> void:
	if not items_enabled:
		return
	_tick_cooldowns(delta)
	for kart: KartController in _karts:
		if not is_instance_valid(kart):
			continue
		var slot: ItemSlot = _slots.get(kart.get_instance_id()) as ItemSlot
		if slot == null:
			continue
		slot.tick_roulette(delta)
		if slot.consume_use_request():
			use_item(kart, kart.get_input_frame_snapshot())
	for item: ItemBase in _live_items.duplicate():
		if is_instance_valid(item) and not item.is_expired():
			item.tick(delta)
	_flush_finished()


## Wires race read services and resets the seeded random stream.
func setup(
	position_tracker: PositionTracker, racing_line: RacingLine,
	collision_resolver: KartCollisionResolver, seed: int,
) -> void:
	_position_tracker = position_tracker
	_racing_line = racing_line
	_collision_resolver = collision_resolver
	_rng.seed = seed
	_load_item_catalog()
	_rebuild_context()


## Registers a kart and its concrete ItemSlot. Re-registering is idempotent.
func register_kart(kart: KartController) -> void:
	if kart == null or _karts.has(kart):
		return
	var slot: ItemSlot = kart.get_node_or_null("ItemSlot") as ItemSlot
	if slot == null:
		push_error("ItemManager.register_kart requires Kart/ItemSlot")
		return
	_karts.append(kart)
	_slots[kart.get_instance_id()] = slot
	_cooldowns[kart.get_instance_id()] = 0.0
	_cooldown_durations[kart.get_instance_id()] = 0.0
	_rebuild_context()


## Removes a kart's slot/cooldown records without touching other participants.
func unregister_kart(kart: KartController) -> void:
	if kart == null:
		return
	for item: ItemBase in _live_items.duplicate():
		if item.owner_kart == kart:
			item.expire()
	_flush_finished()
	_karts.erase(kart)
	_slots.erase(kart.get_instance_id())
	_cooldowns.erase(kart.get_instance_id())
	_cooldown_durations.erase(kart.get_instance_id())
	_previous_item_ids.erase(kart.get_instance_id())
	_rebuild_context()


## Connects a generic track pickup to selection and leader-strike immunity.
func register_item_box(item_box: ItemBox) -> void:
	if item_box != null and not item_box.collected.is_connected(collect_item_box):
		item_box.collected.connect(collect_item_box)


## Selects immediately from current rank and starts the 1.2-second reveal.
func collect_item_box(body: Node3D) -> void:
	var kart: KartController = body as KartController
	if not items_enabled or kart == null:
		return
	notify_leader_immunity(kart)
	var slot: ItemSlot = _slots.get(kart.get_instance_id()) as ItemSlot
	if slot == null or slot.has_item() or slot.roulette_active:
		return
	var rank: int = _position_tracker.get_position(kart) if _position_tracker != null else _karts.find(kart) + 1
	var normalized: float = ItemTable.normalize_rank(maxi(rank, 1), maxi(_karts.size(), 1))
	var previous_id: StringName = _previous_item_ids.get(kart.get_instance_id(), &"")
	var result_id: StringName = ItemTable.pick(item_table, normalized, previous_id, _rng)
	var result: ItemData = _items_by_id.get(result_id) as ItemData
	if result == null:
		push_error("ItemManager could not resolve selected item: %s" % String(result_id))
		return
	_previous_item_ids[kart.get_instance_id()] = result_id
	slot.begin_roulette(result)


## Gives a concrete item immediately for tests and sandbox cycling.
func give_item(kart: KartController, item: ItemData) -> bool:
	var slot: ItemSlot = _slots.get(kart.get_instance_id()) as ItemSlot
	if not items_enabled or slot == null or item == null or slot.has_item() or slot.roulette_active:
		return false
	slot.set_item(item)
	return true


## Creates the held data scene through its common contract and starts cooldown.
func use_item(kart: KartController, frame: InputFrame) -> bool:
	var slot: ItemSlot = _slots.get(kart.get_instance_id()) as ItemSlot
	if not items_enabled or slot == null or not slot.has_item():
		return false
	if float(_cooldowns.get(kart.get_instance_id(), 0.0)) > 0.0:
		return false
	var item_data: ItemData = slot.get_item_data()
	if item_data.scene == null:
		push_error("ItemData.scene is required for %s" % String(item_data.id))
		return false
	if _is_projectile_category(item_data.category) and active_projectiles.size() >= max_active_projectiles:
		return false
	var pool: ObjectPool = _pool_for(item_data)
	var item: ItemBase = pool.acquire() as ItemBase
	if item == null:
		return false
	if not item.finished.is_connected(_on_item_finished):
		item.finished.connect(_on_item_finished)
	item.setup(item_data, kart, _context)
	if not item.can_spawn(_live_items) or not item.can_activate():
		pool.release(item)
		return false
	slot.clear_item()
	_live_items.append(item)
	if item.is_projectile():
		active_projectiles.append(item)
	_cooldowns[kart.get_instance_id()] = item_data.cooldown
	_cooldown_durations[kart.get_instance_id()] = item_data.cooldown
	EventBus.item_used.emit(kart, item_data.id)
	item.activate(frame if frame != null else InputFrame.zero())
	return true


## Returns a defensive copy used by AI projectile sensing.
func get_active_projectiles() -> Array[ItemBase]:
	return active_projectiles.duplicate()


## Returns the current projectile registry size for HUD/debug watches.
func get_active_projectile_count() -> int:
	return active_projectiles.size()


## Returns normalized remaining cooldown for a registered kart's HUD.
func get_cooldown_ratio(kart: KartController) -> float:
	if kart == null:
		return 0.0
	var kart_id: int = kart.get_instance_id()
	var duration: float = float(_cooldown_durations.get(kart_id, 0.0))
	if duration <= 0.0:
		return 0.0
	return clampf(float(_cooldowns.get(kart_id, 0.0)) / duration, 0.0, 1.0)


## Returns dormant instances for a scene-keyed pool.
func get_available_count_for(item_data: ItemData) -> int:
	var key: String = _pool_key(item_data)
	var pool: ObjectPool = _pools.get(key) as ObjectPool
	return pool.get_available_count() if pool != null else 0


## Gives active leader strikes immunity when their target passes a counter.
func notify_leader_immunity(kart: KartController) -> void:
	for item: ItemBase in _live_items:
		if item.has_method("grant_immunity"):
			item.call("grant_immunity", kart)


## Resolves one catalog id for sandbox selection and HUD warning copy.
func get_item_data(item_id: StringName) -> ItemData:
	return _items_by_id.get(item_id) as ItemData


## Announces an accepted item explosion for camera and pooled visual feedback.
func spawn_impact(world_position: Vector3) -> void:
	EventBus.item_exploded.emit(world_position)


## Clears live registries and participant state for in-place race restart.
func reset() -> void:
	for item: ItemBase in _live_items.duplicate():
		_release_item(item)
	_pending_finished.clear()
	active_projectiles.clear()
	_karts.clear()
	_slots.clear()
	_previous_item_ids.clear()
	_cooldowns.clear()
	_cooldown_durations.clear()
	_position_tracker = null
	_racing_line = null
	_collision_resolver = null
	_rebuild_context()


func _load_item_catalog() -> void:
	if not _items_by_id.is_empty():
		return
	for file_name: String in DirAccess.get_files_at(ITEM_DATA_DIRECTORY):
		if file_name.get_extension() != "tres":
			continue
		var item: ItemData = load(ITEM_DATA_DIRECTORY.path_join(file_name)) as ItemData
		if item != null and not item.id.is_empty():
			_items_by_id[item.id] = item


func _rebuild_context() -> void:
	_context.configure(_karts, _position_tracker, _racing_line, _rng, self)


func _tick_cooldowns(delta: float) -> void:
	for kart_id: int in _cooldowns.keys():
		_cooldowns[kart_id] = maxf(0.0, float(_cooldowns[kart_id]) - delta)


func _on_item_finished(item: ItemBase) -> void:
	if not _pending_finished.has(item):
		_pending_finished.append(item)


func _flush_finished() -> void:
	for item: ItemBase in _pending_finished:
		_release_item(item)
	_pending_finished.clear()


func _release_item(item: ItemBase) -> void:
	_live_items.erase(item)
	active_projectiles.erase(item)
	var pool: ObjectPool = _pools.get(_pool_key(item.data)) as ObjectPool
	if pool != null:
		pool.release(item)


func _pool_for(item_data: ItemData) -> ObjectPool:
	var key: String = _pool_key(item_data)
	var pool: ObjectPool = _pools.get(key) as ObjectPool
	if pool == null:
		pool = ObjectPool.new()
		pool.configure(item_data.scene, self, max_active_projectiles)
		_pools[key] = pool
	return pool


func _pool_key(item_data: ItemData) -> String:
	return item_data.scene.resource_path if item_data != null and item_data.scene != null else ""


func _is_projectile_category(category: ItemData.ItemCategory) -> bool:
	return category == ItemData.ItemCategory.PROJECTILE or category == ItemData.ItemCategory.HOMING

## Restores a normalized cooldown read without enabling client item decisions.
func apply_network_cooldown(kart: KartController, ratio: float) -> void:
	_cooldowns[kart.get_instance_id()] = clampf(ratio, 0.0, 1.0)
	_cooldown_durations[kart.get_instance_id()] = 1.0

## Returns all active item visuals, including independent triple-projectile children.
func get_network_items() -> Array[ItemBase]:
	var result: Array[ItemBase] = _live_items.duplicate()
	for projectile: ItemBase in active_projectiles:
		if not result.has(projectile):
			result.append(projectile)
	return result
