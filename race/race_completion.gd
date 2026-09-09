class_name RaceCompletion
extends RefCounted

## Pure participant finish counters shared by RaceManager completion policy.


## Counts finished karts in the supplied roster.
static func count(lap_tracker: LapTracker, karts: Array[KartController]) -> int:
	var result: int = 0
	for kart: KartController in karts:
		if lap_tracker.is_finished(kart):
			result += 1
	return result
