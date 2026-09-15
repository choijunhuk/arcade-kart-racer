class_name NetUpnp
extends Node

## Best-effort UPnP IGD port mapping, run off the main thread so lobby UI
## never blocks on router discovery (spec item 1: 3s timeout, never block
## the UI thread). Mapping status/external IP are reported asynchronously;
## failure to map is a normal, handled outcome (manual port-forward advice).

signal mapping_finished(result: Dictionary)

const DESCRIPTION: String = "TurboCircuit"
const TIMEOUT_MS: int = 3000
## Requested router lease duration in seconds (backlog item 2). Most IGDs
## treat duration 0 (the UPNP default) as PERMANENT — the previous
## `add_port_mapping(port, port, DESCRIPTION, "UDP")` call (no duration
## argument) left a genuinely permanent static forward on the router that a
## crash, kill, or force-quit never cleared; only a router reboot did. A
## finite lease bounds that worst case to this many seconds even when the
## process never gets to run `release_and_free()` at all.
const LEASE_DURATION_SECONDS: int = 3600
## Renew this long before the lease's own expiry (backlog item 2) so a slow
## renewal discovery round trip never lets the real router mapping lapse
## mid-session.
const RENEW_MARGIN_SECONDS: float = 300.0

## Mutable box a worker thread's bound Callable writes its result into,
## instead of calling back into this node directly. Review finding 1: the
## previous `call_deferred("_finish"/"_finish_removal", ...)` targeted
## `self`, and `_exit_tree()` detaching a still-running thread lets the node
## be freed before that deferred call lands — on a freed instance. A
## `RefCounted` box has no lifecycle tied to this node: a freed node simply
## drops its `_box` reference, and the worker thread, which never touches
## `self`, harmlessly finishes writing into a box nobody reads any more. The
## node polls `box.done` from `_process` instead of being called into.
class ResultBox extends RefCounted:
	var done: bool = false
	var result: Dictionary = {}

var _thread: Thread
var _box: ResultBox
var _mapped_port: int = -1
## `NetUpnp._now()` timestamp the current mapping's lease expires at, or
## -1.0 while no mapping is held. Drives `is_renewal_due()`.
var _lease_expires_at: float = -1.0
## Renewal retry back-off (review finding 1), independent of
## `_lease_expires_at` — see `NetUpnpRenewalBackoff`'s own doc comment for
## why re-arming the lease's own expiry on failure (the previous approach)
## was a no-op.
var _renewal_backoff: NetUpnpRenewalBackoff = NetUpnpRenewalBackoff.new()
## Set when release_and_free() arrives while a worker thread is still running:
## the poller frees the node once that worker's result lands instead of
## touching state out from under it.
var _release_pending: bool = false
## Set once the OS sends a close request (window close button, Alt+F4,
## Cmd+Q, ...): the app itself is shutting down, not a normal in-session
## exit (BACK/LEAVE RACE/END SESSION). Explicit and asserted via this node's
## own `_notification()` (review finding 3) instead of inferred from
## `GameState.is_inside_tree()`, which depends on Godot's `tree_exiting`
## cascade order and was never asserted anywhere — it could read either way
## depending on where in that cascade this node's own `tree_exiting` fires.
## Tests set it directly rather than driving a real close request.
var _quitting: bool = false


func _ready() -> void:
	# Renewal polling and the discovery/removal result-box handoff (both in
	# `_process`) must keep working while the game tree is paused (pause
	# menu, settings) — mirrors NetSession's own PROCESS_MODE_ALWAYS, set for
	# the same reason (net_session.gd's _ready()).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quitting = true


## Starts discovery + port mapping for `port` on a worker thread.
func map_port(port: int) -> void:
	if _thread != null and _thread.is_alive():
		return
	_start_worker(_worker_callable("_run"), port)


## Releases the mapping created by `map_port` and frees this node once the
## router has answered. Discovery costs up to TIMEOUT_MS, so it runs on the
## same worker-thread pattern `map_port` uses rather than on the UI thread
## (spec item 1: never block the UI on router discovery); the caller is
## typically a lobby that is about to change scene, so the node reparents
## itself onto the persistent GameState owner first and the removal is
## fire-and-forget, reporting only a log line.
##
## `NetSession.tree_exiting` (this method's caller) also fires during full
## app teardown, not just BACK/LEAVE RACE/END SESSION — at that point
## `_quitting` is set (review finding 3), so starting the removal worker
## here would only get detached rather than joined by `_exit_tree()` (see
## below), the exact up-to-seconds main-thread freeze this node exists to
## avoid. App teardown skips the network round trip and just frees, leaving
## the lease (backlog item 2: now finite, LEASE_DURATION_SECONDS, never
## permanent) to expire on the router on its own; `_warn_abandoned_mapping()`
## still names the port so a headless server operator sees it in the log.
func release_and_free() -> void:
	if _thread != null and _thread.is_alive():
		_release_pending = true
		return
	if _quitting:
		_warn_abandoned_mapping()
		_free_thread_and_self()
		return
	if _mapped_port < 0 or not is_inside_tree():
		_free_thread_and_self()
		return
	var port: int = _mapped_port
	_mapped_port = -1
	_lease_expires_at = -1.0
	if get_parent() != GameState:
		if get_parent() != null:
			get_parent().remove_child(self)
		GameState.add_child(self)
	_start_worker(_worker_callable("_run_removal"), port)


## A script-bound Callable (never object-bound — see the `ResultBox` doc
## comment above) for the named static worker, resolved against this
## instance's actual script so a test double's override (e.g.
## `test_net_upnp_release.gd`'s `FakeRemovalUpnp`) still runs instead of the
## real network call, exactly like overriding an instance method would.
func _worker_callable(method: StringName) -> Callable:
	return Callable(get_script() as GDScript, method)


func _start_worker(worker: Callable, port: int) -> void:
	_box = ResultBox.new()
	_thread = Thread.new()
	_thread.start(worker.bind(port, _box))


## Static: never touches `self`, so this can safely keep running on its own
## thread after the node that started it has been freed.
static func _run_removal(port: int, box: ResultBox) -> void:
	var upnp: UPNP = UPNP.new()
	var removed: bool = false
	if upnp.discover(TIMEOUT_MS) == UPNP.UPNP_RESULT_SUCCESS:
		removed = upnp.delete_port_mapping(port, "UDP") == UPNP.UPNP_RESULT_SUCCESS
	box.result = {"kind": "removal", "port": port, "removed": removed}
	box.done = true


func _finish_removal(port: int, removed: bool) -> void:
	print("UPNP_UNMAP port=%d removed=%s" % [port, removed])
	_free_thread_and_self()


## Joins the worker thread (if any) and frees this node exactly once. Only
## ever called once `_process` has already observed `_box.done`, so the
## worker has already returned and this join is a formality, never a wait.
func _free_thread_and_self() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	queue_free()


## Logs that a live mapping is being left on the router instead of released
## (review finding 3): the lease is finite (backlog item 2) and expires
## there on its own within LEASE_DURATION_SECONDS regardless, but a headless
## server operator should still see which port was abandoned.
func _warn_abandoned_mapping() -> void:
	if _mapped_port >= 0:
		push_warning("UPnP mapping for port %d abandoned on quit" % _mapped_port)


## Static: never touches `self` (see `_run_removal`).
static func _run(port: int, box: ResultBox) -> void:
	var result: Dictionary = _attempt_mapping(port, LEASE_DURATION_SECONDS)
	result["kind"] = "mapping"
	box.result = result
	box.done = true


## Static: never touches `self` (see `_run_removal`). Re-adds the same
## mapping with a fresh lease (backlog item 2); a plain re-run of
## `_attempt_mapping` since most IGDs treat re-adding an identical
## port/proto mapping as extending it rather than erroring.
static func _run_renewal(port: int, box: ResultBox) -> void:
	var result: Dictionary = _attempt_mapping(port, LEASE_DURATION_SECONDS)
	result["kind"] = "renewal"
	box.result = result
	box.done = true


static func _attempt_mapping(port: int, lease_seconds: int) -> Dictionary:
	var upnp: UPNP = UPNP.new()
	var discover_result: int = upnp.discover(TIMEOUT_MS)
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		return {"status": "no_igd", "code": discover_result}
	var gateway: UPNPDevice = upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"status": "no_igd"}
	var add_result: int = upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", lease_seconds)
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
## Untrusted IGD text (finding 4): `external_ip` on the "mapped_unreachable"
## branch comes straight from `query_external_address()`, i.e. whatever
## answered SSDP on the LAN — never echoed into the UI unless it actually
## parses as a dotted-quad IPv4 address.
static func status_message(result: Dictionary, port: int) -> String:
	if String(result.get("status", "")) == "mapped_unreachable":
		var external_ip: String = String(result.get("external_ip", ""))
		var reported: String = external_ip if not _parse_ipv4_octets(external_ip).is_empty() else "the address your router reported"
		return (
			"UPnP mapped, but %s is not internet-reachable (likely CGNAT/double-NAT) — use the relay above or forward UDP port %d on your router manually."
			% [reported, port]
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


## True once `now` has reached the renewal window before `expires_at`
## (backlog item 2's pure helper): renewing this early absorbs a slow
## discovery round trip on the renewal itself so the real router lease never
## actually lapses mid-session. `expires_at < 0.0` means no lease is
## currently held, so there is nothing to renew.
static func is_renewal_due(expires_at: float, now: float) -> bool:
	if expires_at < 0.0:
		return false
	return now >= expires_at - RENEW_MARGIN_SECONDS


static func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _process(_delta: float) -> void:
	if _box != null:
		if not _box.done:
			return
		var box: ResultBox = _box
		_box = null
		_free_finished_thread()
		_handle_result(box.result)
		return
	_maybe_start_renewal(_now())


## Joins the worker thread once its result box is observed done (a
## formality, not a wait — see `_free_thread_and_self`), without freeing
## this node, unlike `_free_thread_and_self`.
func _free_finished_thread() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


## Split out so tests can drive renewal timing directly with a fake clock,
## instead of waiting on real frames/wall-clock time.
func _maybe_start_renewal(now: float) -> void:
	if _mapped_port < 0 or _thread != null:
		return
	if not is_renewal_due(_lease_expires_at, now):
		return
	if not _renewal_backoff.is_due(now):
		return
	_start_worker(_worker_callable("_run_renewal"), _mapped_port)


func _handle_result(result: Dictionary) -> void:
	match String(result.get("kind", "")):
		"removal":
			_finish_removal(int(result.get("port", -1)), bool(result.get("removed", false)))
		"renewal":
			_finish_renewal(result)
		_:
			_finish(result)


func _finish(result: Dictionary) -> void:
	if String(result.get("status", "")).begins_with("mapped"):
		_mapped_port = int(result.get("port", -1))
		_lease_expires_at = _now() + float(LEASE_DURATION_SECONDS)
	if _release_pending:
		# Caller left the lobby while discovery was running: drop the mapping
		# we just created (if any) and free, instead of emitting into a dead UI.
		_release_pending = false
		release_and_free()
		return
	mapping_finished.emit(result)


func _finish_renewal(result: Dictionary) -> void:
	if String(result.get("status", "")).begins_with("mapped"):
		_lease_expires_at = _now() + float(LEASE_DURATION_SECONDS)
		_renewal_backoff.on_success()
	else:
		# Back off instead of re-attempting every _process tick (review
		# finding 1): a router that just rejected one renewal is likely to
		# reject an immediate retry too.
		push_warning("UPnP lease renewal failed for port %d (status=%s); backing off" % [_mapped_port, String(result.get("status", ""))])
		_renewal_backoff.on_failure(_now())
	if _release_pending:
		_release_pending = false
		release_and_free()


## Detaches rather than joins a still-running worker thread (review finding
## 3): a full app close reaches every node's `_exit_tree()` on the main
## thread, and `Thread.wait_to_finish()` here would block it for up to
## TIMEOUT_MS — the exact freeze this node exists to avoid. Dropping the
## reference without joining lets the thread (discovery, removal, or a
## renewal) run to completion in the background, writing into a `_box` this
## freed node no longer reads; Godot's own `Thread` destructor safely
## detaches an unfinished thread instead of crashing.
func _exit_tree() -> void:
	if _thread != null and _thread.is_alive():
		_warn_abandoned_mapping()
		_thread = null
