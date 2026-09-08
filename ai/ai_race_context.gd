class_name AIRaceContext
extends RefCounted

## Read-only race wiring handed to every `AIController.setup()` call so AI
## code never reaches upward through `get_node("../..")` (spec §29 rule 5).
## Every field has a concrete consumer; do not add speculative fields.

## Baked racing line queried by AINavigator and AIDriver's rubber band.
var racing_line: RacingLine
## Track root; used only at setup time to enumerate shortcuts/item boxes.
var track: TrackRoot
## Progress/ranking source for rubber banding and the AIItemBrain rank rule.
var position_tracker: PositionTracker
## Null when there is no human participant (spec §13.7: gap is 0 without one).
var player_kart: KartController
## `(KartController) -> void`; forwards to RespawnSystem.request_respawn().
var request_respawn: Callable = Callable()
## `() -> float`; forwards to Countdown.get_phase_seconds() while frozen.
var get_countdown_phase_seconds: Callable = Callable()
