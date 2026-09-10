class_name NetRaceSetup
extends RefCounted

## Builds the local RaceConfig every peer derives from the one server-owned
## roster broadcast (spec: identical race composition on host and clients,
## from the same roster/seed). Kept out of NetSession so the session file
## stays transport-focused.

## `roster` rows are the session's player dictionaries (peer/driver/kart/ready).
static func build(
	roster: Array, ai_count: int, laps: int, race_seed: int, track_id: String,
) -> RaceConfig:
	var slots: Array[PlayerSlot] = []
	for index: int in range(roster.size()):
		var slot: PlayerSlot = PlayerSlot.new()
		slot.grid_slot = index
		slot.device_id = index - 1
		slot.driver_id = StringName(roster[index]["driver"])
		slot.kart_id = StringName(roster[index]["kart"])
		slots.append(slot)
	var config: RaceConfig = RaceConfigBuilder.build_local(
		slots, NetContentCatalog.resolve_track(track_id),
		LocalLobby.DEFAULT_DIFFICULTY, slots.size() + ai_count)
	config.laps = laps
	config.seed = race_seed
	return config
