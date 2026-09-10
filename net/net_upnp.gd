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


## Releases the mapping created by `map_port` and frees this node once the
## router has answered. Discovery costs up to TIMEOUT_MS, so it runs on the
## same worker-thread pattern `map_port` uses rather than on the UI thread
## (spec item 1: never block the UI on router discovery); the caller is
## typically a lobby that is about to change scene, so the node reparents
## itself onto the persistent GameState owner first and the removal is
## fire-and-forget, reporting only a log line.
func release_and_free() -> void:
	if _mapped_port < 0 or (_thread != null and _thread.is_alive()):
		queue_free()
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
