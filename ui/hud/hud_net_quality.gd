class_name RaceHudNetQuality
extends RefCounted

## Ping/loss readout and "reconnecting" overlay for a networked client (spec
## item 5). Split out of RaceHud to keep it under the 400-line rule; never
## bound for the host/dedicated server or offline play.

const RECONNECT_GAP_SECONDS: float = 2.0

var _session: NetSession
var _label: Label
var _overlay: Control
var _last_snapshot_time: float = -1.0


func bind(session: NetSession, label: Label, overlay: Control) -> void:
	_session = session
	_label = label
	_overlay = overlay
	_last_snapshot_time = NetSession.now()
	_label.visible = true
	session.snapshot_received.connect(_on_snapshot_received)


func is_bound() -> bool:
	return _session != null


func unbind() -> void:
	if _session != null and _session.snapshot_received.is_connected(_on_snapshot_received):
		_session.snapshot_received.disconnect(_on_snapshot_received)
	_session = null


func _on_snapshot_received(_snapshot: RaceSnapshot) -> void:
	_last_snapshot_time = NetSession.now()


func update() -> void:
	var rtt_ms: int = roundi(_session.clock.rtt_seconds * 1000.0)
	# Real measured loss (snapshot sequence gaps), not the synthetic harness
	# drop counter this process injected itself (spec item 5).
	_label.text = "PING %dms  LOSS %.1f%%" % [rtt_ms, _session.get_loss_estimate() * 100.0]
	_overlay.visible = NetSession.now() - _last_snapshot_time > RECONNECT_GAP_SECONDS
