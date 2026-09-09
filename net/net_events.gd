class_name NetEvents
extends Node

## Reliable server event mirrors, mapping node identity to stable grid slots.
const EVENTS: Array[StringName] = [&"lap_completed", &"position_changed", &"kart_finished",
	&"kart_respawned", &"kart_hit", &"item_used", &"item_hit", &"threat_warning",
	&"roulette_started", &"roulette_stopped", &"roulette_ticked", &"item_exploded", &"wrong_way"]
var session: NetSession
var karts: Array[KartController] = []
var _connections: Dictionary[StringName, Callable] = {}

## Binds exactly the event signatures whose authority resides on the server.
func configure(owner_session: NetSession, roster: Array[KartController]) -> void:
	session = owner_session
	karts = roster
	if not multiplayer.is_server():
		session.event_received.connect(_receive)
		return
	for event: StringName in EVENTS:
		var count: int = 0
		for info: Dictionary in EventBus.get_signal_list():
			if StringName(info["name"]) == event:
				count = (info["args"] as Array).size()
		var callback: Callable
		match count:
			1: callback = func(a: Variant) -> void: _send(event, [a])
			2: callback = func(a: Variant, b: Variant) -> void: _send(event, [a, b])
			3: callback = func(a: Variant, b: Variant, c: Variant) -> void: _send(event, [a, b, c])
		_connections[event] = callback
		EventBus.connect(event, callback)

func _exit_tree() -> void:
	for event: StringName in _connections:
		if EventBus.is_connected(event, _connections[event]):
			EventBus.disconnect(event, _connections[event])

func _send(event: StringName, args: Array) -> void:
	var encoded: Array = []
	for value: Variant in args:
		if value is Node:
			encoded.append({"kart": karts.find(value)})
		else:
			encoded.append(value)
	session.send(&"_event", 0, [String(event), encoded], true)

func _receive(event: String, args: Array) -> void:
	if not EVENTS.has(StringName(event)):
		return # Results and countdown have their own typed adapters.
	var decoded: Array = []
	for value: Variant in args:
		if value is Dictionary:
			var index: int = int(value.get("kart", -1))
			decoded.append(karts[index] if index >= 0 and index < karts.size() else null)
		else:
			decoded.append(value)
	EventBus.emit_signal.callv([event] + decoded)
