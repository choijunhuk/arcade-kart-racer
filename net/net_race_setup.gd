class_name NetRaceSetup
extends RefCounted

## Builds the local RaceConfig every peer derives from the one server-owned
## roster broadcast (spec: identical race composition on host and clients,
## from the same roster/seed). Kept out of NetSession so the session file
## stays transport-focused.

## `roster` rows are the session's player dictionaries (peer/driver/kart/ready).
static func build(
	roster: Array, ai_count: int, laps: int, race_seed: int, track_id: String,
	difficulty_id: String = "",
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
		NetContentCatalog.resolve_difficulty(difficulty_id), slots.size() + ai_count)
	config.laps = laps
	config.seed = race_seed
	# Mirrors track_select.gd's offline assignment (audit finding 3):
	# otherwise GameState.selected_track_id stays "" for every online race
	# and RaceTelemetryService.write_and_rotate() files it under "unknown".
	# Runs on every peer (this RPC handler executes on host and clients alike).
	GameState.selected_track_id = config.track.id
	return config
