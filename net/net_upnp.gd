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


## Starts discovery + port mapping for `port` on a worker thread.
func map_port(port: int) -> void:
	if _thread != null and _thread.is_alive():
		return
	_thread = Thread.new()
	_thread.start(_run.bind(port))


## Best-effort removal of a mapping created by `map_port` (spec: remove on
## session end). Synchronous but bounded by the same discovery timeout.
func remove_mapping() -> void:
	if _mapped_port < 0:
		return
	var port: int = _mapped_port
	_mapped_port = -1
	var upnp: UPNP = UPNP.new()
	if upnp.discover(TIMEOUT_MS) == UPNP.UPNP_RESULT_SUCCESS:
		upnp.delete_port_mapping(port, "UDP")


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
	return {"status": "mapped", "external_ip": external_ip, "port": port}


func _finish(result: Dictionary) -> void:
	if String(result.get("status", "")).begins_with("mapped"):
		_mapped_port = int(result.get("port", -1))
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	mapping_finished.emit(result)


func _exit_tree() -> void:
	if _thread != null and _thread.is_alive():
		_thread.wait_to_finish()
