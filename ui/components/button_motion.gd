class_name ButtonMotion
extends Node

## One adapter per menu root; gives every button (including cards added later,
## e.g. kart/track select) a small scale-punch on hover/focus and press.
## Mirrors UiAudio's attach-and-recurse pattern (Phase 17b item 5).

const HOVER_SCALE: float = 1.04
const HOVER_SECONDS: float = 0.12
const PRESS_SCALE: float = 0.93
const PRESS_SECONDS: float = 0.07
const RELEASE_SECONDS: float = 0.12

var _tweens: Dictionary[BaseButton, Tween] = {}


## Attaches hover/press scale tweens, including selection cards added later.
static func attach(menu_root: Node) -> ButtonMotion:
	var adapter: ButtonMotion = ButtonMotion.new()
	menu_root.add_child(adapter)
	adapter._connect_tree(menu_root)
	return adapter


func _connect_tree(node: Node) -> void:
	if node is ButtonMotion:
		return # Do not observe the adapter's own bookkeeping nodes.
	if node.child_entered_tree.is_connected(_connect_tree):
		return # A subtree can arrive via both recursion and child_entered_tree.
	if node is BaseButton:
		var button: BaseButton = node as BaseButton
		button.pivot_offset = button.size * 0.5
		button.resized.connect(_on_resized.bind(button))
		button.mouse_entered.connect(_animate.bind(button, HOVER_SCALE, HOVER_SECONDS))
		button.focus_entered.connect(_animate.bind(button, HOVER_SCALE, HOVER_SECONDS))
		button.mouse_exited.connect(_on_release.bind(button))
		button.focus_exited.connect(_on_release.bind(button))
		button.button_down.connect(_animate.bind(button, PRESS_SCALE, PRESS_SECONDS))
		button.button_up.connect(_on_release.bind(button))
		button.tree_exiting.connect(_forget.bind(button))
	node.child_entered_tree.connect(_connect_tree)
	for child: Node in node.get_children():
		_connect_tree(child)


func _on_resized(button: BaseButton) -> void:
	button.pivot_offset = button.size * 0.5


## A button released while still hovered/focused settles back to the hover
## scale rather than 1.0, so the pointer doesn't see a visible snap.
func _on_release(button: BaseButton) -> void:
	var hovered: bool = button.is_visible_in_tree() and (button.get_global_rect().has_point(button.get_global_mouse_position()) or button.has_focus())
	_animate(button, HOVER_SCALE if hovered else 1.0, RELEASE_SECONDS)


func _animate(button: BaseButton, target_scale: float, seconds: float) -> void:
	if button.disabled or not button.is_visible_in_tree():
		return
	var existing: Tween = _tweens.get(button)
	if existing != null:
		existing.kill()
	var tween: Tween = create_tween()
	_tweens[button] = tween
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _forget(button: BaseButton) -> void:
	_tweens.erase(button)
