class_name RaceRoster
extends RefCounted

## Resolves human ids and legacy/AI roster resources without UI dependencies.

const DRIVER_DIRECTORY: String = "res://data/drivers"
const KART_DIRECTORY: String = "res://data/karts"

var _drivers: Array[DriverData] = []
var _drivers_by_id: Dictionary[StringName, DriverData] = {}
var _karts_by_id: Dictionary[StringName, KartData] = {}


func _init() -> void:
	for resource: Resource in ResourceScanner.scan_tres(DRIVER_DIRECTORY):
		if resource is DriverData:
			var driver: DriverData = resource as DriverData
			_drivers.append(driver)
			_drivers_by_id[driver.id] = driver
	for resource: Resource in ResourceScanner.scan_tres(KART_DIRECTORY):
		if resource is KartData:
			var kart: KartData = resource as KartData
			_karts_by_id[kart.id] = kart


## Resolves a slot's driver from human selection, fixed roster, or AI rotation.
func driver_for_slot(config: RaceConfig, grid_slot: int, player: PlayerSlot) -> DriverData:
	if player != null:
		return _drivers_by_id.get(player.driver_id, config.player_driver) as DriverData
	if grid_slot < config.driver_roster.size():
		return config.driver_roster[grid_slot]
	if _drivers.is_empty():
		return config.player_driver
	return _drivers[grid_slot % _drivers.size()]


## Resolves a slot's kart from human selection, fixed roster, or legacy default.
func kart_for_slot(config: RaceConfig, grid_slot: int, player: PlayerSlot) -> KartData:
	if player != null:
		return _karts_by_id.get(player.kart_id, config.player_kart) as KartData
	if grid_slot < config.kart_roster.size():
		return config.kart_roster[grid_slot]
	return config.player_kart
