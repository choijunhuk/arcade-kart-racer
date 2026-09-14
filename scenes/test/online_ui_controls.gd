class_name OnlineUiControls
extends RefCounted

## Locates the online lobby's dynamically-built controls by node text/
## placeholder (the brief: node names must never be guessed, and these
## controls are created in code with no explicit `.name`, so text is the
## only reliable handle). `Footer`/`Players` are the only fixed paths, read
## straight from ui/menus/online_lobby.tscn.
static func collect(lobby: Node) -> Dictionary:
	var host_button: Button = button_with_text(lobby, "HOST")
	var join_button: Button = button_with_text(lobby, "JOIN")
	var ready_button: Button = button_with_text(lobby, "READY")
	var start_button: Button = button_with_text(lobby, "START")
	var back_button: Button = button_with_text(lobby, "BACK")
	var ip_field: LineEdit = line_edit_with_placeholder(lobby, "Host IP or join code")
	var password_field: LineEdit = line_edit_with_placeholder(lobby, "Password (optional)")
	var status_label: Label = lobby.get_node_or_null("Panel/VBox/Footer") as Label
	var spin_boxes: Array[Node] = find_all(lobby, "SpinBox")
	var option_buttons: Array[Node] = find_all(lobby, "OptionButton")

	var named: Array = [
		["HOST button", host_button], ["JOIN button", join_button],
		["READY button", ready_button], ["START button", start_button],
		["BACK button", back_button], ["ip/join-code LineEdit", ip_field],
		["password LineEdit", password_field], ["status Footer Label", status_label],
	]
	for entry: Array in named:
		if entry[1] == null:
			return {"missing": entry[0]}
	if spin_boxes.is_empty():
		return {"missing": "port SpinBox"}
	if option_buttons.size() < 2:
		return {"missing": "driver/kart OptionButton pair (found %d)" % option_buttons.size()}

	return {
		"missing": "", "host": host_button, "join": join_button, "ready": ready_button,
		"start": start_button, "back": back_button, "ip": ip_field, "password": password_field,
		"status": status_label, "port": spin_boxes[0], "driver": option_buttons[0], "kart": option_buttons[1],
	}


static func find_all(root: Node, klass: String) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in root.get_children():
		if child.get_class() == klass:
			out.append(child)
		out.append_array(find_all(child, klass))
	return out


static func button_with_text(root: Node, text: String) -> Button:
	for node: Node in find_all(root, "Button"):
		if (node as Button).text.strip_edges() == text:
			return node as Button
	return null


static func line_edit_with_placeholder(root: Node, placeholder: String) -> LineEdit:
	for node: Node in find_all(root, "LineEdit"):
		if (node as LineEdit).placeholder_text == placeholder:
			return node as LineEdit
	return null
