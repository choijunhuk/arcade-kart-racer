class_name NetContentCatalog
extends RefCounted

## Resolves driver/kart/track content ids from disk for lobby rosters and
## race setup, keeping NetSession focused on transport/session state.

const TRACK_DIRECTORY: String = "res://data/tracks"


## Returns the first catalog driver id, used to seed a freshly joined row.
static func default_driver_id() -> String:
	return String((ResourceScanner.scan_tres(LocalLobby.DRIVER_DIRECTORY)[0] as DriverData).id)


## Returns the first catalog kart id, used to seed a freshly joined row.
static func default_kart_id() -> String:
	return String((ResourceScanner.scan_tres(LocalLobby.KART_DIRECTORY)[0] as KartData).id)


## True when `id` exists in the scanned `.tres` catalog at `directory`.
static func has(directory: String, id: String) -> bool:
	for resource: Resource in ResourceScanner.scan_tres(directory):
		if String(resource.get("id")) == id:
			return true
	return false


## Resolves a track by content id (never a path/object over the network,
## spec: network payloads never select file paths or instantiate objects);
## falls back to the existing default when `id` is empty or unknown.
static func resolve_track(id: String) -> TrackData:
	if not id.is_empty():
		for resource: Resource in ResourceScanner.scan_tres(TRACK_DIRECTORY):
			if resource is TrackData and String((resource as TrackData).id) == id:
				return resource as TrackData
	return LocalLobby.DEFAULT_TRACK
