class_name RaceConfigBuilder
extends RefCounted

const DEFAULT_KART_COUNT: int = 8
const MIN_LAPS: int = 1
const MAX_KART_COUNT: int = 12
const MAX_LOCAL_PLAYERS: int = 4
const MAX_DRIVER_MODIFIER: float = 0.05
const MODIFIABLE_STATS: Array[StringName] = [
	&"max_speed",
	&"acceleration",
	&"handling",
	&"drift_factor",
	&"weight",
]


## Builds the complete immutable-style payload consumed by `RaceManager`.
static func build(
	driver: DriverData,
	kart: KartData,
	track: TrackData,
	difficulty: AIDifficultyProfile,
	laps: int = -1,
	kart_count: int = DEFAULT_KART_COUNT,
) -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.player_driver = driver
	config.player_kart = kart
	config.track = track
	config.ai_difficulty = difficulty
	config.laps = maxi(MIN_LAPS, track.laps_default if laps < MIN_LAPS else laps)
	config.kart_count = maxi(1, kart_count)
	config.player_slot = 0
	config.items_enabled = true
	var player: PlayerSlot = PlayerSlot.new()
	player.device_id = PlayerInputProvider.DEVICE_ANY
	player.driver_id = driver.id
	player.kart_id = kart.id
	player.grid_slot = 0
	config.players = [player]
	return config


## Builds a local multiplayer race from validated lobby slots.
static func build_local(
	player_slots: Array[PlayerSlot], track: TrackData,
	difficulty: AIDifficultyProfile, kart_count: int = DEFAULT_KART_COUNT,
) -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.race_mode = RaceConfig.RaceMode.LOCAL_MULTIPLAYER
	config.track = track
	config.laps = maxi(MIN_LAPS, track.laps_default)
	config.kart_count = maxi(kart_count, player_slots.size())
	config.ai_difficulty = difficulty
	config.items_enabled = true
	for slot: PlayerSlot in player_slots:
		config.players.append(slot.copy())
	config.player_slot = config.players[0].grid_slot if not config.players.is_empty() else -1
	normalize(config)
	return config


## Returns a deep duplicate with allowlisted driver percentage modifiers applied.
static func apply_driver_mods(kart: KartData, driver: DriverData) -> KartData:
	var modified: KartData = kart.duplicate(true) as KartData
	if driver == null:
		return modified
	for stat_name: StringName in driver.stat_mods:
		if not MODIFIABLE_STATS.has(stat_name):
			push_warning("Driver modifier ignores unsupported kart stat: %s" % String(stat_name))
			continue
		var base_value: float = float(modified.get(stat_name))
		var modifier: float = clampf(
			driver.stat_mods[stat_name], -MAX_DRIVER_MODIFIER, MAX_DRIVER_MODIFIER,
		)
		modified.set(stat_name, base_value * (1.0 + modifier))
	return modified


## Normalizes scene-entry configs; time trial always has one human and no items.
static func normalize(config: RaceConfig) -> void:
	if config.track == null or config.track.scene == null:
		push_warning("RaceConfig track is invalid; using track_01")
		config.track = load("res://data/tracks/track_01.tres") as TrackData
	config.laps = maxi(MIN_LAPS, config.laps)
	config.kart_count = clampi(config.kart_count, 1, MAX_KART_COUNT)
	if config.player_slot >= 0:
		config.player_slot = clampi(config.player_slot, 0, config.kart_count - 1)
	if config.player_kart == null:
		config.player_kart = load("res://data/karts/medium.tres") as KartData
	if config.ai_difficulty == null:
		config.ai_difficulty = load("res://data/ai/normal.tres") as AIDifficultyProfile
	if config.race_mode == RaceConfig.RaceMode.TIME_TRIAL:
		config.kart_count = 1
		config.player_slot = 0
		config.items_enabled = false
	_normalize_players(config)


static func _normalize_players(config: RaceConfig) -> void:
	if config.race_mode == RaceConfig.RaceMode.TIME_TRIAL:
		config.players.resize(mini(config.players.size(), 1))
	if config.players.is_empty() and config.player_slot >= 0:
		var legacy: PlayerSlot = PlayerSlot.new()
		legacy.device_id = PlayerInputProvider.DEVICE_ANY
		legacy.driver_id = config.player_driver.id if config.player_driver != null else &"aurora_vale"
		legacy.kart_id = config.player_kart.id
		legacy.grid_slot = config.player_slot
		config.players.append(legacy)
	var normalized: Array[PlayerSlot] = []
	var devices: Dictionary[int, bool] = {}
	var grids: Dictionary[int, bool] = {}
	for source: PlayerSlot in config.players:
		if normalized.size() >= MAX_LOCAL_PLAYERS or devices.has(source.device_id):
			continue
		var slot: PlayerSlot = source.copy()
		if slot.grid_slot < 0 or slot.grid_slot >= config.kart_count or grids.has(slot.grid_slot):
			slot.grid_slot = _first_free_grid(grids, config.kart_count)
		if slot.grid_slot < 0:
			continue
		if slot.driver_id.is_empty():
			slot.driver_id = config.player_driver.id if config.player_driver != null else &"aurora_vale"
		if slot.kart_id.is_empty():
			slot.kart_id = config.player_kart.id
		devices[slot.device_id] = true
		grids[slot.grid_slot] = true
		normalized.append(slot)
	normalized.sort_custom(func(first: PlayerSlot, second: PlayerSlot) -> bool: return first.grid_slot < second.grid_slot)
	config.players = normalized
	config.player_slot = normalized[0].grid_slot if not normalized.is_empty() else -1


static func _first_free_grid(used: Dictionary[int, bool], kart_count: int) -> int:
	for grid_slot: int in range(kart_count):
		if not used.has(grid_slot):
			return grid_slot
	return -1
