class_name OnlineLobbyWidgets

## Static UI-construction helpers used by OnlineLobby, extracted so
## online_lobby.gd stays under the project's 400-line-per-file cap.

static func button(parent: Control, text: String, action: Callable) -> Button:
	var control: Button = Button.new()
	control.text = text
	control.pressed.connect(action)
	parent.add_child(control)
	return control

static func options(parent: Control, resources: Array[Resource]) -> OptionButton:
	var control: OptionButton = OptionButton.new()
	for resource: Resource in resources:
		control.add_item(String(resource.get("display_name")))
	parent.add_child(control)
	return control

## Explicit gamepad focus over runtime-built rows: left/right wraps within each
## row, up/down (and focus_next/previous) walks every row in reading order and
## wraps via the screen's MenuScreen.wire_vertical_focus(), so no control is a
## dead end.
static func wire_rows_focus(screen: MenuScreen, rows: Array[Array]) -> void:
	var chain: Array[Control] = []
	for row: Array in rows:
		var controls: Array[Control] = []
		controls.assign(row)
		for index: int in range(controls.size()):
			var control: Control = controls[index]
			control.focus_neighbor_left = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
			control.focus_neighbor_right = control.get_path_to(controls[(index + 1) % controls.size()])
		chain.append_array(controls)
	screen.wire_vertical_focus(chain)

static func row_label(parent: Control, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	parent.add_child(label)

static func select_option(option: OptionButton, resources: Array[Resource], id: String, default_id: String) -> void:
	var target: String = id if not id.is_empty() else default_id
	for index: int in range(resources.size()):
		if String(resources[index].get("id")) == target:
			option.selected = index
			return

static func display_name(resources: Array[Resource], id: String) -> String:
	for resource: Resource in resources:
		if String(resource.get("id")) == id:
			return String(resource.get("display_name"))
	return id
