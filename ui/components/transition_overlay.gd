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
	var change_error: Error = get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error("Scene transition failed: %s" % scene_path)
		queue_free()
		return
	await get_tree().process_frame
	var fade_in: Tween = create_tween()
	fade_in.tween_property(_fade, "modulate:a", 0.0, FADE_SECONDS)
	await fade_in.finished
	queue_free()
