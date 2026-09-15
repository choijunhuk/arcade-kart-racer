class_name NetUpnp
extends Node

## Best-effort UPnP IGD port mapping, run off the main thread so lobby UI
## never blocks on router discovery (spec item 1: 3s timeout, never block
## the UI thread). Mapping status/external IP are reported asynchronously;
## failure to map is a normal, handled outcome (manual port-forward advice).

signal mapping_finished(result: Dictionary)

const DESCRIPTION: String = "TurboCircuit"
const TIMEOUT_MS: int = 3000
## Cushion on top of TIMEOUT_MS for the delayed-quit wait (finding 4), so a
## worker returning right at the timeout still gets a moment to write its box.
const QUIT_WAIT_MARGIN_MS: int = 250
## Requested router lease duration in seconds (backlog item 2): duration 0
## (the previous, argument-less `add_port_mapping` call) left a genuinely
## permanent forward that only a router reboot cleared, surviving a crash or
## force-quit. A finite lease bounds that worst case even if the process
## never runs `release_and_free()` at all.
const LEASE_DURATION_SECONDS: int = 3600
## Renew this long before the lease's own expiry (backlog item 2) so a slow
## renewal discovery round trip never lets the real router mapping lapse
## mid-session.
const RENEW_MARGIN_SECONDS: float = 300.0

## Mutable box a worker thread's bound Callable writes into, instead of
## calling back into this node directly (finding 1: a freed node dropped
## mid-`call_deferred` was a crash). A `RefCounted` box has no lifecycle
## tied to this node: a freed node just drops its `_box` reference.
##
## `done` alone does not make `result` safe to read cross-thread (review
## item 7) — a plain, unsynchronised bool. `_process()` trusts `result`
## only once `Thread.is_alive()` (engine-synchronised) confirms the worker
## returned; `done` remains a test seam for a finished result with no real
## `Thread` — see `_thread` below.
class ResultBox extends RefCounted:
	var done: bool = false
	var result: Dictionary = {}

## Null while idle, or a test double skipped starting one (`_process()`
## treats that as "finished" too) — see `ResultBox` above.
var _thread: Thread
var _box: ResultBox
var _mapped_port: int = -1
## `NetUpnp._now()` timestamp the current mapping's lease expires at; -1.0
## while no mapping is held, or (review finding 2) it is a permanent lease
## that never expires and so is never renewed — `is_renewal_due()` already
## treats any negative value as "nothing to renew".
var _lease_expires_at: float = -1.0
## Renewal retry back-off (finding 1) — see `NetUpnpRenewalBackoff`.
var _renewal_backoff: NetUpnpRenewalBackoff = NetUpnpRenewalBackoff.new()
## Set when release_and_free() arrives while a worker thread is still
## running: the poller frees the node once its result lands instead of
## touching state out from under it.
var _release_pending: bool = false
## Set once the OS sends a close request: the app is shutting down, not a
## normal in-session exit. Explicit via `_notification()` (finding 3)
## instead of inferred from tree-exiting order, which could read either
## way. Tests set it directly.
var _quitting: bool = false
## Bounds a delayed OS-close quit (see `_notification()`) on a live worker —
## see `NetUpnpQuitWaiter`'s own doc comment.
var _quit_waiter: NetUpnpQuitWaiter = NetUpnpQuitWaiter.new()


func _ready() -> void:
	# Renewal polling and the discovery/removal result-box handoff (both in
	# `_process`) must keep working while the game tree is paused (pause
	# menu, settings) — mirrors NetSession's own PROCESS_MODE_ALWAYS, set for
	# the same reason (net_session.gd's _ready()).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quitting = true
		if _box != null and not _box.done:
			# A worker is still discovering/mapping (finding 4): veto the
			# automatic quit; `_process()` fires it once the worker reports
			# back or the bounded margin elapses (see `_exit_tree()`).
			get_tree().auto_accept_quit = false
			if not _quit_waiter.is_armed(): # Only arm once (item 1).
				_quit_waiter.arm(_now(), float(TIMEOUT_MS) / 1000.0, float(QUIT_WAIT_MARGIN_MS) / 1000.0)


## Starts discovery + port mapping for `port` on a worker thread. Gated on
## `_box != null` (finding 3), not `_thread.is_alive()`, which reads false
## the instant a worker *returns* — before `_process()` consumes its result
## — and so would let a second worker start over an unconsumed one.
func map_port(port: int) -> void:
	if _box != null:
		return
	_start_worker(_worker_callable("_run"), port)


## Releases the mapping created by `map_port` and frees this node once the
## router has answered, on the same worker-thread pattern as `map_port`; the
## caller is typically a lobby about to change scene, so the node reparents
## onto the persistent GameState owner first, and the removal is fire-and-
## forget, reporting only a log line.
##
## `NetSession.tree_exiting` (this method's caller) also fires during full
## app teardown, where `_quitting` is set (finding 3) — starting a removal
## worker there would only get detached rather than joined by
## `_exit_tree()`, so teardown skips the round trip and just frees, leaving
## the mapping: a finite lease expires on its own, a permanent one does not
## (item 6). `_warn_abandoned_mapping()` still names the port for an operator.
func release_and_free() -> void:
	# `_box != null`, not `_thread.is_alive()` (review finding 3, see
	# `map_port()`'s own doc comment): a worker that already returned but
	# whose result isn't consumed yet must still defer here, or a mapping
	# the router just created could be abandoned before `_mapped_port`
	# reflects it.
	if _box != null:
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


## A script-bound Callable (never object-bound — see `ResultBox` above) for
## the named static worker, resolved against this instance's actual script
## so a test double's override (e.g. `FakeRemovalUpnp`) still runs instead
## of the real network call.
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


## Logs that a live mapping is left on the router (finding 3): a finite
## lease still expires there on its own, a permanent one does not (item 6) —
## either way, a headless operator should see which port was abandoned.
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
	var permanent: bool = false
	if add_result == UPNP.UPNP_RESULT_ONLY_PERMANENT_LEASE_SUPPORTED and lease_seconds != 0:
		# Some IGDs only support a permanent lease and reject any finite
		# duration outright (review finding 2). Retry once with duration 0
		# so it still works there; release_and_free()'s removal is what
		# clears it, since it never expires or renews (see `_finish()`).
		add_result = upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", 0)
		permanent = add_result == UPNP.UPNP_RESULT_SUCCESS
	if add_result != UPNP.UPNP_RESULT_SUCCESS:
		return {"status": "failed", "code": add_result}
	var external_ip: String = upnp.query_external_address()
	if external_ip.is_empty():
		return {"status": "mapped_no_ip", "port": port, "permanent": permanent}
	if not is_internet_reachable_address(external_ip):
		# CGNAT or a double-NAT router: the IGD mapped the port on its own
		# WAN-facing address, but that address is itself private, so nothing
		# on the internet can actually reach it (spec/audit finding 2).
		return {"status": "mapped_unreachable", "external_ip": external_ip, "port": port, "permanent": permanent}
	return {"status": "mapped", "external_ip": external_ip, "port": port, "permanent": permanent}


## Human-readable status line for anything other than a successful reachable
## mapping. Distinguishes "mapped but not internet-reachable" (CGNAT/double-
## NAT) from a genuine failure. `external_ip` on "mapped_unreachable" is raw
## SSDP LAN text — never echoed unless it parses as a dotted-quad IPv4.
static func status_message(result: Dictionary, port: int) -> String:
	if String(result.get("status", "")) == "mapped_unreachable":
		var external_ip: String = String(result.get("external_ip", ""))
		var reported: String = external_ip if not _parse_ipv4_octets(external_ip).is_empty() else "the address your router reported"
		return (
			"UPnP mapped, but %s is not internet-reachable (likely CGNAT/double-NAT) — use the relay above or forward UDP port %d on your router manually."
			% [reported, port]
		)
	return "UPnP unavailable — forward UDP port %d manually." % port


## Parses `ip` as four 0-255 octets, or empty if not a well-formed dotted-
## quad — malformed/untrusted input fails closed for every caller.
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
## every private/CGNAT/link-local/loopback/reserved range an IGD can hand
## back as its own "external" address: 0.0.0.0/8 (down/misconfigured WAN),
## 10/8, 172.16/12, 192.168/16, 100.64/10 (CGNAT), 169.254/16 (link-local),
## 127/8 (loopback), and 224/4 + 240/4 (multicast/reserved, includes
## 255.255.255.255). Malformed input fails closed (not reachable).
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


## True once `now` has reached the renewal window before `expires_at`: this
## early margin absorbs a slow renewal discovery round trip so the real
## lease never lapses mid-session. `expires_at < 0.0` means nothing to renew.
static func is_renewal_due(expires_at: float, now: float) -> bool:
	if expires_at < 0.0:
		return false
	return now >= expires_at - RENEW_MARGIN_SECONDS


static func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _process(_delta: float) -> void:
	# Bounded quit-wait (finding 4); `box_ready` is snapshotted once and
	# reused below for both the poll and consume decision (item 1 race fix).
	if _box != null:
		var thread_alive: bool = _thread != null and _thread.is_alive()
		var box_ready: bool = not thread_alive and _box.done
		_quit_waiter.poll(_now(), box_ready, get_tree())
		if not box_ready:
			return
		var box: ResultBox = _box
		_box = null
		_free_finished_thread()
		_handle_result(box.result)
		return
	_quit_waiter.poll(_now(), false, get_tree())
	_maybe_start_renewal(_now())


## Joins the worker thread once `_process()` confirmed `not
## _thread.is_alive()` (a formality, not a wait), without freeing this node.
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
		if bool(result.get("permanent", false)):
			# A permanent lease (review finding 2) never expires on its own,
			# so it is never due for renewal either — `is_renewal_due()`
			# already treats a negative `_lease_expires_at` as "nothing to
			# renew," the same sentinel used for "no mapping held."
			_lease_expires_at = -1.0
		else:
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
		if bool(result.get("permanent", false)):
			# Fell back to a permanent lease (item 3): never renews again.
			_lease_expires_at = -1.0
		else:
			_lease_expires_at = _now() + float(LEASE_DURATION_SECONDS)
		_renewal_backoff.on_success()
	else: # Back off instead of retrying every tick (finding 1); warns once (item 6).
		_renewal_backoff.on_failure_warn_once(_now(), "UPnP lease renewal failed for port %d (status=%s); backing off" % [_mapped_port, String(result.get("status", ""))])
	if _release_pending:
		_release_pending = false
		release_and_free()


## Detaches a still-running worker thread (finding 3); joins one that already
## returned but was never joined (item 4). Also fires the quit waiter (item
## 1) if still armed when a free path other than `_process()`'s own lands here.
func _exit_tree() -> void:
	if _thread != null:
		if _thread.is_alive():
			_warn_abandoned_mapping()
			_thread = null
		else:
			_thread.wait_to_finish()
			_thread = null
	_quit_waiter.fire_on_exit(get_tree())
