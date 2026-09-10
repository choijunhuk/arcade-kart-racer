class_name NetTrackEvents
extends Node

## Replicates authoritative pickup availability without client collection timers.
var _session: NetSession
var _boxes: Array[ItemBox] = []

## Enumerates authored boxes once, preserving identical track child order.
func configure(session: NetSession, track: Node, replica: bool) -> void:
	_session = session
	var container: Node = track.get_node_or_null("ItemBoxes")
	if container == null:
		return # A track without pickups has no availability events.
	for node: Node in container.get_children():
		if node is ItemBox:
			var box: ItemBox = node as ItemBox
			box.network_replica = replica
			if not replica:
				box.availability_changed.connect(_send.bind(_boxes.size()))
			_boxes.append(box)
	if replica:
		session.event_received.connect(_receive)

func _send(available: bool, index: int) -> void:
	_session.send(&"_event", 0, ["box", [index, available]], true)

func _receive(kind: String, args: Array) -> void:
	if kind == "box" and args.size() == 2:
		var index: int = int(args[0])
		if index >= 0 and index < _boxes.size():
			_boxes[index].apply_network_available(bool(args[1]))
