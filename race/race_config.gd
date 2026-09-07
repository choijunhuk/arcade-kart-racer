class_name RaceConfig
extends Resource

## Per-race parameters (spec §14.2). Schema only in this phase; RaceManager
## (Phase 5) is the first consumer.

@export var track: TrackData
@export var laps: int = 3
@export var kart_count: int = 8
@export var ai_difficulty: AIDifficultyProfile
@export var player_kart: KartData
@export var player_driver: DriverData
@export var items_enabled: bool = true
@export var seed: int = 0
