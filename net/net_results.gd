class_name NetResults
extends RefCounted

## Reliable results payload with an explicit allowlist, never object deserialization.
const FIELDS: Array[String] = ["kart_name", "kart_display_name", "driver_name", "grid_slot",
	"rank", "total_time_seconds", "best_lap_seconds", "is_new_record", "hit_count", "item_use_count"]

## Extracts finalized server rows for the result mirror.
static func pack(entries: Array[RaceResults.Entry]) -> Array:
	var rows: Array = []
	for entry: RaceResults.Entry in entries:
		var row: Dictionary = {}
		for key: String in FIELDS:
			row[key] = entry.get(key)
		rows.append(row)
	return rows

## Rebuilds typed rows while highlighting only this client's player.
static func unpack(rows: Array, local_slot: int) -> Array[RaceResults.Entry]:
	var entries: Array[RaceResults.Entry] = []
	for row: Dictionary in rows:
		var entry: RaceResults.Entry = RaceResults.Entry.new()
		for key: String in FIELDS:
			entry.set(key, row[key])
		entry.is_human = entry.grid_slot == local_slot
		entry.player_number = 1 if entry.is_human else 0
		entries.append(entry)
	return entries
