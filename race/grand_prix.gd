class_name GrandPrix
extends RefCounted

## Autoload-free championship: stable grid identities survive every race scene.

const POINTS: Array[int] = [15, 12, 10, 8, 6, 4, 2, 1]
const CUP_ID: StringName = &"horizon_cup"

class Standing extends RefCounted:
	var slot: int = 0
	var driver_name: String = ""
	var kart_name: String = ""
	var points: int = 0
	var best_finish: int = 0
	var finishes: Array[int] = []

var round_index: int = 0
var tracks: Array[TrackData] = []
var _base: RaceConfig
var _standings: Array[Standing] = []
var _recorded: bool = false


## Creates the cup and resolves its seeded roster exactly once.
func setup(config: RaceConfig, sequence: Array[TrackData]) -> void:
	_base = config.duplicate() as RaceConfig
	_base.race_mode = RaceConfig.RaceMode.GRAND_PRIX
	tracks = sequence.duplicate()
	round_index = 0
	_recorded = false
	_standings.clear()
	_build_roster()
	for slot: int in range(_base.kart_count):
		var standing: Standing = Standing.new()
		standing.slot = slot
		standing.driver_name = _base.driver_roster[slot].display_name
		standing.kart_name = _base.kart_roster[slot].display_name
		_standings.append(standing)


## Returns the fixed points schedule; invalid positions and DNFs earn zero.
static func points_for_position(position: int) -> int:
	return POINTS[position - 1] if position > 0 and position <= POINTS.size() else 0


## Builds the current round while preserving difficulty, participants and seed.
func current_config() -> RaceConfig:
	if tracks.is_empty() or _base == null:
		return null
	var result: RaceConfig = _base.duplicate() as RaceConfig
	result.track = tracks[round_index]
	result.laps = result.track.laps_default
	result.gp_round = round_index
	return result


## Accepts a complete round once; stale/duplicate submissions cannot award points.
func record_results(index: int, entries: Array[RaceResults.Entry]) -> bool:
	if index != round_index or _recorded or entries.size() != _standings.size():
		return false
	var seen: Dictionary[int, bool] = {}
	var ranks: Dictionary[int, bool] = {}
	for entry: RaceResults.Entry in entries:
		if entry.grid_slot < 0 or entry.grid_slot >= _standings.size() or seen.has(entry.grid_slot):
			return false
		if entry.rank < 1 or entry.rank > _standings.size() or ranks.has(entry.rank):
			return false
		seen[entry.grid_slot] = true
		ranks[entry.rank] = true
	for entry: RaceResults.Entry in entries:
		var standing: Standing = _standings[entry.grid_slot]
		var finish: int = entry.rank if entry.total_time_seconds > 0.0 else POINTS.size() + 1
		standing.points += points_for_position(finish)
		standing.finishes.append(finish)
		standing.best_finish = finish if standing.best_finish == 0 else mini(standing.best_finish, finish)
	_recorded = true
	return true


## Advances only after the current results were accepted and another race exists.
func advance() -> bool:
	if not _recorded or is_complete():
		return false
	round_index += 1
	_recorded = false
	return true


## True only after final-round results have been counted.
func is_complete() -> bool:
	return not tracks.is_empty() and _recorded and round_index == tracks.size() - 1


## Returns copied standings by points, best finish, countback, then grid slot.
func standings() -> Array[Standing]:
	var result: Array[Standing] = []
	for source: Standing in _standings:
		var copy: Standing = Standing.new()
		copy.slot = source.slot
		copy.driver_name = source.driver_name
		copy.kart_name = source.kart_name
		copy.points = source.points
		copy.best_finish = source.best_finish
		copy.finishes = source.finishes.duplicate()
		result.append(copy)
	result.sort_custom(_ahead)
	return result


## Returns the player's stable slot for saving the final championship result.
func player_slot() -> int:
	return _base.player_slot if _base != null else -1


## Separates saved championship bests by the difficulty used for every round.
func record_key() -> StringName:
	return StringName("%s/%s" % [CUP_ID, _base.ai_difficulty.id])


static func _ahead(a: Standing, b: Standing) -> bool:
	if a.points != b.points:
		return a.points > b.points
	if a.best_finish != b.best_finish:
		return a.best_finish < b.best_finish
	for position: int in range(1, POINTS.size() + 1):
		if a.finishes.count(position) != b.finishes.count(position):
			return a.finishes.count(position) > b.finishes.count(position)
	return a.slot < b.slot


func _build_roster() -> void:
	var karts: Array[Resource] = ResourceScanner.scan_tres("res://data/karts")
	var drivers: Array[Resource] = ResourceScanner.scan_tres("res://data/drivers")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _base.seed
	_base.kart_roster = []
	_base.driver_roster = []
	var selected_driver: DriverData = _base.player_driver if _base.player_driver != null else drivers[0] as DriverData
	if _base.player_slot >= 0:
		drivers.erase(selected_driver)
	for slot: int in range(_base.kart_count):
		if slot == _base.player_slot:
			_base.kart_roster.append(_base.player_kart)
			_base.driver_roster.append(selected_driver)
		else:
			_base.kart_roster.append(karts[rng.randi_range(0, karts.size() - 1)] as KartData)
			var index: int = rng.randi_range(0, drivers.size() - 1)
			_base.driver_roster.append(drivers[index] as DriverData)
			if drivers.size() > 1:
				drivers.remove_at(index)
