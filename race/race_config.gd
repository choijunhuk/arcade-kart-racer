class_name RaceConfig
extends Resource

## Per-race parameters consumed by RaceManager (spec §14.2).
enum RaceMode { SINGLE_RACE, GRAND_PRIX, TIME_TRIAL, LOCAL_MULTIPLAYER }

@export var race_mode: RaceMode = RaceMode.SINGLE_RACE
@export var gp_round: int = 0

@export var track: TrackData
@export var laps: int = 3
@export var kart_count: int = 8
## -1 means no human participant (all AI), used by headless sims (spec §14.2).
@export_range(-1, 11) var player_slot: int = 0
@export var ai_difficulty: AIDifficultyProfile
@export var player_kart: KartData
@export var player_driver: DriverData
@export var items_enabled: bool = true
@export var seed: int = 0

## Canonical local-human roster; legacy player_slot fields are normalized into it.
@export var players: Array[PlayerSlot] = []

## Optional per-grid-slot roster for mixed-class simulations; empty uses player_kart.
@export var kart_roster: Array[KartData] = []
@export var driver_roster: Array[DriverData] = []


## Returns the number of human slots, including an unnormalized legacy config.
func human_count() -> int:
	return players.size() if not players.is_empty() else (1 if player_slot >= 0 else 0)


## Returns the AI field size after human slots occupy grid positions.
func ai_count() -> int:
	return maxi(0, kart_count - human_count())


## Returns whether a grid slot belongs to a local human.
func is_human_grid_slot(grid_slot: int) -> bool:
	if players.is_empty():
		return player_slot == grid_slot
	return player_for_grid_slot(grid_slot) != null


## Returns the human assigned to a grid slot, or null.
func player_for_grid_slot(grid_slot: int) -> PlayerSlot:
	for player: PlayerSlot in players:
		if player.grid_slot == grid_slot:
			return player
	return null


## Returns joined keyboard/joypad ids in P1-P4 order.
func player_device_ids() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for player: PlayerSlot in players:
		result.append(player.device_id)
	if result.is_empty() and player_slot >= 0:
		result.append(PlayerSlot.KEYBOARD_DEVICE_ID)
	return result
