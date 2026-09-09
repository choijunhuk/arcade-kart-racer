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
		push_error("Scene loading request failed: %s" % scene_path)
		queue_free()
		return
	while model.state == LoadingProgress.State.LOADING:
		var progress: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(scene_path, progress)
		model.update(status, float(progress[0]) if not progress.is_empty() else 0.0)
		(loading.get_node("Progress") as ProgressBar).value = model.progress * 100.0
		await get_tree().process_frame
	if model.state == LoadingProgress.State.FAILED:
		push_error("Scene threaded load failed: %s" % scene_path)
		queue_free()
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
	var change_error: Error = get_tree().change_scene_to_packed(packed)
	if change_error != OK:
		push_error("Scene transition failed: %s" % scene_path)
		queue_free()
		return
	await get_tree().process_frame
	get_tree().current_scene.add_child(PostLoadProbe.new())
	loading.queue_free()
	var fade_in: Tween = create_tween()
	fade_in.tween_property(_fade, "modulate:a", 0.0, FADE_SECONDS)
	await fade_in.finished
	queue_free()
