class_name NetContentCatalog
extends RefCounted

## Resolves driver/kart/track content ids from disk for lobby rosters and
## race setup, keeping NetSession focused on transport/session state.

const TRACK_DIRECTORY: String = "res://data/tracks"
const AI_DIRECTORY: String = "res://data/ai"

## Fallbacks for `default_driver_id()`/`default_kart_id()` (backlog item 5):
## the scan they read is memoized even when it comes back empty (the shipped
## content directory missing, or every file in it broken) — without these,
## `[0]` on that empty scan is an out-of-bounds script error for the rest of
## the process's lifetime, on every host()/admit. Preloaded, not scanned, so
## they resolve even when DRIVER_DIRECTORY/KART_DIRECTORY themselves cannot
## be — but only those directories: a missing or broken `aurora_vale.tres`/
## `basalt_crown.tres` here fails the whole script at parse/load time
## instead, not something this fallback can catch (review item 8).
const DEFAULT_DRIVER: DriverData = preload("res://data/drivers/aurora_vale.tres")
const DEFAULT_KART: KartData = preload("res://data/karts/basalt_crown.tres")

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
		if (_catalog[directory] as Array).is_empty():
			# Loud once per directory, not per lookup (review item 8): this
			# memo already bounds a directory to one scan attempt per process,
			# so this fires exactly once for it. An empty catalog silently
			# degrades to the same preloaded default (or resolve_track()'s/
			# resolve_difficulty()'s existing-default) forever — a lobby that
			# can never actually offer a choice, or shipped without its
			# content directory at all — and a headless server operator needs
			# to see that, not just find it later as a suspiciously narrow
			# roster.
			push_error("NetContentCatalog: %s scanned empty — content missing or entirely broken" % directory)
	var scanned: Array[Resource] = []
	scanned.assign(_catalog[directory])
	return scanned


## Drops the memo; for tests that write content directories at runtime.
static func clear_cache() -> void:
	_catalog.clear()


## Returns the first catalog driver id, used to seed a freshly joined row;
## falls back to the preloaded default (backlog item 5) once the memoized
## scan of `DRIVER_DIRECTORY` is empty instead of indexing `[0]` of nothing.
static func default_driver_id() -> String:
	return _first_id_or_default(LocalLobby.DRIVER_DIRECTORY, DEFAULT_DRIVER)


## Returns the first catalog kart id, used to seed a freshly joined row;
## falls back to the preloaded default (backlog item 5) once the memoized
## scan of `KART_DIRECTORY` is empty instead of indexing `[0]` of nothing.
static func default_kart_id() -> String:
	return _first_id_or_default(LocalLobby.KART_DIRECTORY, DEFAULT_KART)


static func _first_id_or_default(directory: String, fallback: Resource) -> String:
	var scanned: Array[Resource] = _scan(directory)
	if scanned.is_empty():
		return String(fallback.get("id"))
	return String(scanned[0].get("id"))


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
