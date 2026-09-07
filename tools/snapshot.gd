extends SceneTree
## Runs a scene windowed for N frames, saves a PNG, quits.
## usage: godot --path . -s tools/snapshot.gd -- <scene_path> <out_png> [frames]

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://scenes/test/kart_sandbox.tscn"
	var out_path: String = args[1] if args.size() > 1 else "/tmp/snapshot.png"
	var frames: int = int(args[2]) if args.size() > 2 else 120
	var packed: PackedScene = load(scene_path)
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame
	for i in range(frames):
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("SNAPSHOT_SAVED ", out_path, " ", img.get_width(), "x", img.get_height())
	quit()
