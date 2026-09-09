class_name TransitionOverlay
extends CanvasLayer

const FADE_SECONDS: float = 0.18

@onready var _fade: ColorRect = $Fade

var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade.modulate.a = 0.0
	visible = false


## Fades out the current scene, changes it, then reveals the next scene.
func transition_to(scene_path: String) -> void:
	if _busy:
		return
	_busy = true
	visible = true
	var fade_out: Tween = create_tween()
	fade_out.tween_property(_fade, "modulate:a", 1.0, FADE_SECONDS)
	await fade_out.finished
	var loading: Control = preload("res://ui/components/loading_screen.tscn").instantiate() as Control
	add_child(loading)
	var model: LoadingProgress = LoadingProgress.new()
	model.begin()
	var request_error: Error = ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if request_error != OK:
		await _show_failure(loading, "Scene loading request failed: %s" % scene_path)
		return
	while model.state == LoadingProgress.State.LOADING:
		var progress: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(scene_path, progress)
		model.update(status, float(progress[0]) if not progress.is_empty() else 0.0)
		(loading.get_node("Progress") as ProgressBar).value = model.progress * 100.0
		await get_tree().process_frame
	if model.state == LoadingProgress.State.FAILED:
		await _show_failure(loading, "Scene threaded load failed: %s" % scene_path)
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
	var change_error: Error = ERR_INVALID_DATA if packed == null else get_tree().change_scene_to_packed(packed)
	if change_error != OK:
		await _show_failure(loading, "Scene transition failed: %s" % scene_path)
		return
	await get_tree().process_frame
	get_tree().current_scene.add_child(PostLoadProbe.new())
	loading.queue_free()
	var fade_in: Tween = create_tween()
	fade_in.tween_property(_fade, "modulate:a", 0.0, FADE_SECONDS)
	await fade_in.finished
	queue_free()


## Reveals the previous scene while keeping recovery available above it.
func _show_failure(loading: Control, message: String) -> void:
	push_error(message)
	loading.queue_free()
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "LoadError"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -180.0
	panel.offset_right = 180.0
	panel.offset_top = -55.0
	panel.offset_bottom = 55.0
	add_child(panel)
	var content: VBoxContainer = VBoxContainer.new()
	panel.add_child(content)
	var label: Label = Label.new()
	label.text = "Unable to load this scene."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)
	var back: Button = Button.new()
	back.text = "Back to menu"
	back.pressed.connect(_back_to_menu)
	content.add_child(back)
	var fade_in: Tween = create_tween()
	fade_in.tween_property(_fade, "modulate:a", 0.0, FADE_SECONDS)
	await fade_in.finished
	back.grab_focus()


func _back_to_menu() -> void:
	# GameState rejects requests while SceneTransition remains under the root.
	get_parent().remove_child(self)
	GameState.change_scene("res://ui/menus/main_menu.tscn")
	queue_free()
