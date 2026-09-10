class_name NetRaceState
extends RefCounted

## Explicit server-state adapter for existing read-only HUD and results APIs.
var manager: RaceManager
var items: ItemManager
var laps: LapTracker
var positions: PositionTracker
var catalog: Array[ItemData] = []
var _projectile_ids: Dictionary[int, int] = {}
var _next_projectile_id: int = 1

func _init(owner_race: RaceManager) -> void:
	manager = owner_race
	items = manager.get_node("ItemManager") as ItemManager
	laps = manager.get_node("LapTracker") as LapTracker
	positions = manager.get_node("PositionTracker") as PositionTracker
	for resource: Resource in ResourceScanner.scan_tres(ItemManager.ITEM_DATA_DIRECTORY):
		if resource is ItemData:
			catalog.append(resource as ItemData)

## Captures authoritative slots/ranks/laps/projectile transforms after kart stepping.
func capture(tick: int, acknowledgements: Array[int]) -> RaceSnapshot:
	var result: RaceSnapshot = RaceSnapshot.new()
	result.tick = tick
	result.server_seconds = NetSession.now()
	result.race_state = manager.get_state()
	result.race_seconds = laps.network_race_seconds()
	result.countdown_seconds = (manager.get_node("Countdown") as Countdown).get_phase_seconds()
	var karts: Array[KartController] = manager.get_karts()
	for index: int in range(karts.size()):
		var kart: KartController = karts[index]
		var slot: ItemSlot = kart.item_slot
		result.karts.append({"slot": index, "state": kart.capture_state(), "ack": acknowledgements[index],
			"lap": laps.get_lap(kart), "rank": positions.get_position(kart),
			"checkpoint": laps.get_next_checkpoint_index(kart),
			"item": item_index(slot.get_roulette_result() if slot.roulette_active else slot.get_item_data()),
			"roulette": slot.get_roulette_progress() if slot.roulette_active else -1.0,
			"cooldown": items.get_cooldown_ratio(kart),
			"finish": laps.get_finish_time(kart) if laps.is_finished(kart) else -1.0,
			"progress": positions.get_progress(kart)})
	var live_ids: Array[int] = []
	for projectile: ItemBase in items.get_network_items():
		var instance: int = projectile.get_instance_id()
		live_ids.append(instance)
		if not _projectile_ids.has(instance):
			_projectile_ids[instance] = _next_projectile_id
			_next_projectile_id += 1
		result.projectiles.append({"id": _projectile_ids[instance], "item": item_index(projectile.data),
			"pose": projectile.global_transform, "owner": maxi(0, karts.find(projectile.owner_kart))})
	for instance: int in _projectile_ids.keys():
		if not live_ids.has(instance):
			_projectile_ids.erase(instance)
	return result

## Applies server-owned gameplay reads without running client-side judgements.
func apply(snapshot: RaceSnapshot) -> void:
	var karts: Array[KartController] = manager.get_karts()
	for index: int in range(karts.size()):
		var row: Dictionary = snapshot.karts[index]
		var kart: KartController = karts[index]
		laps.apply_network_row(kart, row, snapshot.race_seconds)
		positions.apply_network_row(kart, int(row["rank"]), float(row["progress"]))
		kart.item_slot.apply_network_item(item_at(int(row["item"])), float(row["roulette"]))
		items.apply_network_cooldown(kart, float(row["cooldown"]))
	manager.apply_network_state(snapshot.race_state)

## One-based catalog indices reserve zero for an empty slot.
func item_index(item: ItemData) -> int:
	return catalog.find(item) + 1 if item != null else 0

## Resolves bounded catalog indices, without loading a network-provided path.
func item_at(index: int) -> ItemData:
	return catalog[index - 1] if index > 0 and index <= catalog.size() else null
