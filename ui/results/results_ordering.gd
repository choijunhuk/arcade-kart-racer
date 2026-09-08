class_name ResultsOrdering
extends RefCounted


## Returns a rank-ascending copy without changing the race-owned entry array.
static func by_rank(entries: Array[RaceResults.Entry]) -> Array[RaceResults.Entry]:
	var ordered: Array[RaceResults.Entry] = entries.duplicate()
	ordered.sort_custom(_entry_precedes)
	return ordered


static func _entry_precedes(first: RaceResults.Entry, second: RaceResults.Entry) -> bool:
	return first.rank < second.rank
