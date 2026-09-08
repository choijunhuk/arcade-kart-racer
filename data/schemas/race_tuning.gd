class_name RaceTuning
extends Resource

## Tick-driven race-flow cadence values shared by Countdown and RaceManager.

@export_group("Countdown")
@export var countdown_step_seconds: float = 1.0

@export_group("Finishing")
@export var finish_timeout_seconds: float = 15.0
@export var results_delay_seconds: float = 1.0

@export_group("Ranking")
@export var position_update_hz: float = 5.0

