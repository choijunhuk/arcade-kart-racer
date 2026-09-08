class_name MenuScreen
extends Control

@export_file("*.tscn") var back_scene_path: String = ""


func _ready() -> void:
	UiAudio.attach(self)
	_start_menu_music.call_deferred()
	if get_parent() == get_tree().root:
		GameState.current_mode = GameState.Mode.MENU


func _unhandled_input(event: InputEvent) -> void:
	if not back_scene_path.is_empty() and event.is_action_pressed(&"ui_cancel"):
		UiAudio.play_back()
		go_back()
		get_viewport().set_input_as_handled()


## Requests a themed transition through the global scene boundary.
func go_to(scene_path: String) -> void:
	GameState.change_scene(scene_path)


## Returns to the configured parent screen when this screen has one.
func go_back() -> void:
	if not back_scene_path.is_empty():
		go_to(back_scene_path)


## Defers initial focus until Godot has completed Control layout.
func focus_initial(control: Control) -> void:
	control.call_deferred("grab_focus")


## Wires a wraparound vertical focus chain for enabled controls.
func wire_vertical_focus(controls: Array[Control]) -> void:
	if controls.is_empty():
		return
	for index: int in range(controls.size()):
		var control: Control = controls[index]
		var previous: Control = controls[(index - 1 + controls.size()) % controls.size()]
		var next: Control = controls[(index + 1) % controls.size()]
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)


## Wires wraparound four-way focus for a fixed-column selection grid.
func wire_grid_focus(controls: Array[Control], columns: int) -> void:
	if controls.is_empty() or columns <= 0:
		return
	var count: int = controls.size()
	for index: int in range(count):
		var row: int = index / columns
		var column: int = index % columns
		var row_count: int = ceili(float(count) / float(columns))
		var left_index: int = row * columns + ((column - 1 + columns) % columns)
		var right_index: int = row * columns + ((column + 1) % columns)
		if left_index >= count:
			left_index = index
		if right_index >= count:
			right_index = row * columns
		var up_index: int = ((row - 1 + row_count) % row_count) * columns + column
		var down_index: int = ((row + 1) % row_count) * columns + column
		if up_index >= count:
			up_index = mini(count - 1, column)
		if down_index >= count:
			down_index = column % count
		controls[index].focus_neighbor_left = controls[index].get_path_to(controls[left_index])
		controls[index].focus_neighbor_right = controls[index].get_path_to(controls[right_index])
		controls[index].focus_neighbor_top = controls[index].get_path_to(controls[up_index])
		controls[index].focus_neighbor_bottom = controls[index].get_path_to(controls[down_index])


func _start_menu_music() -> void:
	if get_parent() == get_tree().root:
		AudioManager.set_music_ducked(false)
		AudioManager.set_final_lap(false)
		AudioManager.play_bgm(&"menu")
