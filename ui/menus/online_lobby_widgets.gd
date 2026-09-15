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
