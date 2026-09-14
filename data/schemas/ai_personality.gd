class_name AIPersonality
extends Resource

## Per-driver AI judgment/style traits (spec §18d — phase 18d-1). Every value
## is 0..1 with 0.5 as neutral, matching `AIPersonalityTuning`'s no-op point
## exactly: a kart whose `DriverData.ai_personality` is null (see `resolve()`)
## drives byte-identical to before this phase existed. These traits change
## ONLY decision timing/probability/style, never
## max_speed/acceleration/speed_confidence/rubber-band (spec §13.6) — those
## stay exclusively `AIDifficultyProfile`'s job.

## Attack-item (projectile/homing/area/leader-strike) use frequency and how
## quickly a fresh eligible situation gets acted on.
@export_range(0.0, 1.0) var aggression: float = 0.5
## Defensive-item (shield/trap) holding tendency: how long it sits on one
## before using it, and how decisively it uses one once eligible.
@export_range(0.0, 1.0) var defense: float = 0.5
## Overtake-attempt boldness: how small a speed gap it will commit on, and
## how quickly it relaxes into forcing a boxed-in pass.
@export_range(0.0, 1.0) var overtake_boldness: float = 0.5
## Drift-tier ambition: how high a mini-turbo tier it holds out for, and how
## reluctant it is to bail out of a drift early.
@export_range(0.0, 1.0) var drift_ambition: float = 0.5
## Racing-line discipline: how tightly it hugs the racing line versus
## swinging wide during voluntary lane changes (overtakes).
@export_range(0.0, 1.0) var line_discipline: float = 0.5


## Returns `personality` if non-null, otherwise a fresh neutral (all-0.5) one.
## Every ai/* call site routes through this so a null `DriverData.ai_personality`
## (spec: "null이면 중립 0.5 기본값") never needs its own null check.
static func resolve(personality: AIPersonality) -> AIPersonality:
	return personality if personality != null else AIPersonality.new()
