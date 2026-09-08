class_name RaceConfig
extends Resource

## Per-race parameters consumed by RaceManager (spec §14.2).

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
