class_name UiAudio
extends Node

## One adapter per menu root; connects authored and dynamically added buttons.

const BACK_META: StringName = &"audio_back"


## Attaches button focus/activation sounds, including selection cards added later.
static func attach(menu_root: Node) -> UiAudio:
	var adapter: UiAudio = UiAudio.new()
	menu_root.add_child(adapter)
	adapter._connect_tree(menu_root)
	return adapter


## Plays the shared Back cue for keyboard/gamepad cancellation paths.
static func play_back() -> void:
	AudioManager.play_sfx(&"menu_back", null, AudioManagerService.PRIORITY_UI)


func _connect_tree(node: Node) -> void:
	if node is UiAudio:
		return # Do not observe the adapter's own bookkeeping nodes.
	if node.child_entered_tree.is_connected(_connect_tree):
		return # A subtree can arrive via both recursion and child_entered_tree.
	if node is BaseButton:
		var button: BaseButton = node as BaseButton
		button.focus_entered.connect(_on_focus.bind(button))
		button.pressed.connect(_on_pressed.bind(button))
	node.child_entered_tree.connect(_connect_tree)
	for child: Node in node.get_children():
		_connect_tree(child)


func _on_focus(button: BaseButton) -> void:
	if button.is_visible_in_tree() and not button.disabled:
		AudioManager.play_sfx(&"menu_move", null, AudioManagerService.PRIORITY_UI)


func _on_pressed(button: BaseButton) -> void:
	if button.disabled or not button.is_visible_in_tree():
		return # Hidden overlays never produce interaction sounds.
	var is_back: bool = bool(button.get_meta(BACK_META, button.name == &"BackButton"))
	AudioManager.play_sfx(&"menu_back" if is_back else &"menu_accept", null, AudioManagerService.PRIORITY_UI)
