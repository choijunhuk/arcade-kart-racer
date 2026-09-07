extends GutTest

## Spec §15.3: ItemBox hides on pickup and respawns after `respawn_time`,
## driven by a physics-tick counter (not a coroutine timer, spec §29 rule 7).

const TICKS_PER_SECOND: int = 60


func _make_box() -> ItemBox:
	var box: ItemBox = (load("res://track/elements/item_box.tscn") as PackedScene).instantiate() as ItemBox
	add_child_autofree(box)
	return box


func test_pickup_hides_the_box_and_emits_collected() -> void:
	var box: ItemBox = _make_box()
	var watcher: Node3D = Node3D.new()
	add_child_autofree(watcher)
	watch_signals(box)
	box._on_body_entered(watcher)
	assert_signal_emitted_with_parameters(box, "collected", [watcher])
	assert_false(box.get_node("Mesh").visible)


func test_box_respawns_after_configured_ticks() -> void:
	var box: ItemBox = _make_box()
	box.respawn_time = 1.0
	var watcher: Node3D = Node3D.new()
	add_child_autofree(watcher)
	box._on_body_entered(watcher)

	for _tick: int in range(TICKS_PER_SECOND - 1):
		box._physics_process(1.0 / TICKS_PER_SECOND)
	assert_false(box.get_node("Mesh").visible)

	box._physics_process(1.0 / TICKS_PER_SECOND)
	assert_true(box.get_node("Mesh").visible)


func test_reentry_while_hidden_does_not_re_trigger_collection() -> void:
	var box: ItemBox = _make_box()
	var watcher: Node3D = Node3D.new()
	add_child_autofree(watcher)
	watch_signals(box)
	box._on_body_entered(watcher)
	box._on_body_entered(watcher)
	assert_signal_emit_count(box, "collected", 1)
