class_name NetContentCatalog
extends RefCounted

## Resolves driver/kart/track content ids from disk for lobby rosters and
## race setup, keeping NetSession focused on transport/session state.

const TRACK_DIRECTORY: String = "res://data/tracks"
const AI_DIRECTORY: String = "res://data/ai"

## Per-directory memo of the shipped content catalog. A peer's `_selection`
## reaches `has()` twice, and each call used to re-open the directory and
## re-load every `.tres` — pure disk churn for an identical result, since the
## catalog is read-only at runtime. The memo lives here, not in
## `ResourceScanner`, because that scanner is also used for directories whose
## contents legitimately change (tests, tooling).
static var _catalog: Dictionary[String, Array] = {}


## Cached whole-directory catalog scan. A directory gets at most one scan
## attempt per process (bounded retry = 0): whatever loaded on that attempt
## is memoized as-is, complete or not. An earlier version left an incomplete
## scan wholly uncached so "a transient failure gets a fresh look on the next
## call" — but one unloadable file (corrupt install, missing `.import` in an
## export) never resolves itself between calls, so every `_selection` RPC
## re-scanned the whole directory and re-`push_warning`'d per failing file at
## the rate limiter's cadence: the disk-churn DoS this memo exists to
## prevent, plus attacker-paced log growth on a headless server. Memoizing
## the partial result means a broken file degrades the catalog once, not
## per RPC; `clear_cache()` is still the only way to force a fresh look.
static func _scan(directory: String) -> Array[Resource]:
	if not _catalog.has(directory):
		var result: Dictionary = ResourceScanner.scan_tres_complete(directory)
		_catalog[directory] = result["resources"]
	var scanned: Array[Resource] = []
	scanned.assign(_catalog[directory])
	return scanned


## Drops the memo; for tests that write content directories at runtime.
static func clear_cache() -> void:
	_catalog.clear()


## Returns the first catalog driver id, used to seed a freshly joined row.
static func default_driver_id() -> String:
	return String((_scan(LocalLobby.DRIVER_DIRECTORY)[0] as DriverData).id)


## Returns the first catalog kart id, used to seed a freshly joined row.
static func default_kart_id() -> String:
	return String((_scan(LocalLobby.KART_DIRECTORY)[0] as KartData).id)


## True when `id` exists in the scanned `.tres` catalog at `directory`.
static func has(directory: String, id: String) -> bool:
	for resource: Resource in _scan(directory):
		if String(resource.get("id")) == id:
			return true
	return false


## Resolves a track by content id (never a path/object over the network,
## spec: network payloads never select file paths or instantiate objects);
## falls back to the existing default when `id` is empty or unknown.
static func resolve_track(id: String) -> TrackData:
	if not id.is_empty():
		for resource: Resource in _scan(TRACK_DIRECTORY):
			if resource is TrackData and String((resource as TrackData).id) == id:
				return resource as TrackData
	return LocalLobby.DEFAULT_TRACK


## Resolves an AI difficulty profile by content id (mirrors `resolve_track`);
## falls back to the existing default when `id` is empty or unknown.
static func resolve_difficulty(id: String) -> AIDifficultyProfile:
	if not id.is_empty():
		for resource: Resource in _scan(AI_DIRECTORY):
			if resource is AIDifficultyProfile and String((resource as AIDifficultyProfile).id) == id:
				return resource as AIDifficultyProfile
	return LocalLobby.DEFAULT_DIFFICULTY
