class_name NetUpnp
extends Node

## Best-effort UPnP IGD port mapping, run off the main thread so lobby UI
## never blocks on router discovery (spec item 1: 3s timeout, never block
## the UI thread). Mapping status/external IP are reported asynchronously;
## failure to map is a normal, handled outcome (manual port-forward advice).

signal mapping_finished(result: Dictionary)

const DESCRIPTION: String = "TurboCircuit"
const TIMEOUT_MS: int = 3000

var _thread: Thread
var _mapped_port: int = -1
## Set when release_and_free() arrives while a worker thread is still running:
## the thread's deferred callback frees the node instead of touching state.
var _release_pending: bool = false


## Starts discovery + port mapping for `port` on a worker thread.
func map_port(port: int) -> void:
	if _thread != null and _thread.is_alive():
		return
	_thread = Thread.new()
	_thread.start(_run.bind(port))


## Releases the mapping created by `map_port` and frees this node once the
## router has answered. Discovery costs up to TIMEOUT_MS, so it runs on the
## same worker-thread pattern `map_port` uses rather than on the UI thread
## (spec item 1: never block the UI on router discovery); the caller is
## typically a lobby that is about to change scene, so the node reparents
## itself onto the persistent GameState owner first and the removal is
## fire-and-forget, reporting only a log line.
func release_and_free() -> void:
	if _thread != null and _thread.is_alive():
		# A discovery thread is mid-flight and will call back into this node;
		# let it finish and free us there rather than freeing under it.
		_release_pending = true
		return
	if _mapped_port < 0:
		_free_thread_and_self()
		return
	var port: int = _mapped_port
	_mapped_port = -1
	if get_parent() != null:
		get_parent().remove_child(self)
	GameState.add_child(self)
	_thread = Thread.new()
	_thread.start(_run_removal.bind(port))


func _run_removal(port: int) -> void:
	var upnp: UPNP = UPNP.new()
	var removed: bool = false
	if upnp.discover(TIMEOUT_MS) == UPNP.UPNP_RESULT_SUCCESS:
		removed = upnp.delete_port_mapping(port, "UDP") == UPNP.UPNP_RESULT_SUCCESS
	call_deferred("_finish_removal", port, removed)


func _finish_removal(port: int, removed: bool) -> void:
	print("UPNP_UNMAP port=%d removed=%s" % [port, removed])
	_free_thread_and_self()


## Joins the worker thread (if any) and frees this node exactly once.
func _free_thread_and_self() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	queue_free()


func _run(port: int) -> void:
	var result: Dictionary = _attempt_mapping(port)
	call_deferred("_finish", result)


func _attempt_mapping(port: int) -> Dictionary:
	var upnp: UPNP = UPNP.new()
	var discover_result: int = upnp.discover(TIMEOUT_MS)
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		return {"status": "no_igd", "code": discover_result}
	var gateway: UPNPDevice = upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"status": "no_igd"}
	var add_result: int = upnp.add_port_mapping(port, port, DESCRIPTION, "UDP")
	if add_result != UPNP.UPNP_RESULT_SUCCESS:
		return {"status": "failed", "code": add_result}
	var external_ip: String = upnp.query_external_address()
	if external_ip.is_empty():
		return {"status": "mapped_no_ip", "port": port}
	if not is_internet_reachable_address(external_ip):
		# CGNAT or a double-NAT router: the IGD mapped the port on its own
		# WAN-facing address, but that address is itself private, so nothing
		# on the internet can actually reach it (spec/audit finding 2).
		return {"status": "mapped_unreachable", "external_ip": external_ip, "port": port}
	return {"status": "mapped", "external_ip": external_ip, "port": port}


## Human-readable status line for anything other than a successful reachable
## mapping (`OnlineLobby._on_upnp_finished`'s "mapped" branch handles that one
## itself, since it also needs the join code). Distinguishes "mapped but not
## internet-reachable" (CGNAT/double-NAT, finding 2) from a genuine mapping
## failure so a guest is never handed a code that could never work.
static func status_message(result: Dictionary, port: int) -> String:
	if String(result.get("status", "")) == "mapped_unreachable":
		return (
			"UPnP mapped, but %s is not internet-reachable (likely CGNAT/double-NAT) — use the relay above or forward UDP port %d on your router manually."
			% [String(result.get("external_ip", "")), port]
		)
	return "UPnP unavailable — forward UDP port %d manually." % port


## Parses `ip` as four 0-255 octets, or an empty array if it is not a
## well-formed dotted-quad — malformed/untrusted input fails closed for
## every caller (`is_internet_reachable_address` and `status_message`).
static func _parse_ipv4_octets(ip: String) -> Array[int]:
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return []
	var octets: Array[int] = []
	for part: String in parts:
		if not part.is_valid_int():
			return []
		var value: int = int(part)
		if value < 0 or value > 255:
			return []
		octets.append(value)
	return octets


## True when `ip` is a routable, internet-reachable IPv4 address. False for
## every private/CGNAT/link-local/loopback/reserved range an IGD can
## legitimately (or a false-WAN-down router can spuriously) hand back as its
## own "external" address: 0.0.0.0/8 ("no address", a down/misconfigured WAN
## — the exact false success this feature exists to catch), 10.0.0.0/8,
## 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 (CGNAT, RFC 6598),
## 169.254.0.0/16 (link-local), 127.0.0.0/8 (loopback), and 224.0.0.0/4 +
## 240.0.0.0/4 (multicast/reserved, includes 255.255.255.255). Malformed
## input fails closed (not reachable).
static func is_internet_reachable_address(ip: String) -> bool:
	var octets: Array[int] = _parse_ipv4_octets(ip)
	if octets.is_empty():
		return false
	if octets[0] == 0:
		return false
	if octets[0] == 10:
		return false
	if octets[0] == 172 and octets[1] >= 16 and octets[1] <= 31:
		return false
	if octets[0] == 192 and octets[1] == 168:
		return false
	if octets[0] == 100 and octets[1] >= 64 and octets[1] <= 127:
		return false
	if octets[0] == 169 and octets[1] == 254:
		return false
	if octets[0] == 127:
		return false
	if octets[0] >= 224:
		return false
	return true


func _finish(result: Dictionary) -> void:
	if String(result.get("status", "")).begins_with("mapped"):
		_mapped_port = int(result.get("port", -1))
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if _release_pending:
		# Caller left the lobby while discovery was running: drop the mapping
		# we just created (if any) and free, instead of emitting into a dead UI.
		_release_pending = false
		release_and_free()
		return
	mapping_finished.emit(result)


func _exit_tree() -> void:
	if _thread != null and _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
