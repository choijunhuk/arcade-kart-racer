extends SceneTree
## Runs a scene windowed for N frames, saves a PNG, quits.
## usage: godot --path . -s tools/snapshot.gd -- <scene_path> <out_png> [frames]

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://scenes/test/kart_sandbox.tscn"
	var out_path: String = args[1] if args.size() > 1 else "/tmp/snapshot.png"
	var frames: int = int(args[2]) if args.size() > 2 else 120
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("SNAPSHOT_FAILED cannot load scene %s" % scene_path)
		quit(1)
		return
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame
	for i in range(frames):
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("SNAPSHOT_FAILED viewport produced no image for %s" % scene_path)
		quit(1)
		return
	var error: Error = img.save_png(out_path)
	if error != OK:
		push_error("SNAPSHOT_FAILED save_png(%s) returned %s" % [out_path, error_string(error)])
		quit(1)
		return
	print("SNAPSHOT_SAVED ", out_path, " ", img.get_width(), "x", img.get_height())
	quit()
