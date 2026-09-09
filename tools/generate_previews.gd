extends SceneTree

## Renders each playable track once; headless uses explicitly labelled map art.
const SIZE: Vector2i = Vector2i(512, 256)
const DIRECTORY: String = "res://assets/previews/"
var _viewport: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	for resource: Resource in ResourceScanner.scan_tres("res://data/tracks"):
		var data: TrackData = resource as TrackData
		_viewport = SubViewport.new()
		_viewport.size = SIZE
		_viewport.own_world_3d = true
		root.add_child(_viewport)
		var track: TrackRoot = data.scene.instantiate() as TrackRoot
		_viewport.add_child(track)
		await process_frame
		var line: RacingLine = track.get_racing_line()
		var points: PackedVector3Array = line.curve.get_baked_points()
		var image: Image
		if DisplayServer.get_name() == "headless":
			image = _map(points, data.preview_color)
			print("PREVIEW schematic fallback ", data.id)
		else:
			var bounds: AABB = AABB(points[0], Vector3.ZERO)
			for point: Vector3 in points:
				bounds = bounds.expand(point)
			var camera: Camera3D = Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = maxf(bounds.size.x, bounds.size.z * 2.0) * 1.15
			camera.far = 2000.0
			_viewport.add_child(camera)
			camera.position = bounds.get_center() + Vector3.UP * 800.0
			camera.rotation.x = -PI * 0.5
			camera.current = true
			_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			await process_frame
			await RenderingServer.frame_post_draw
			image = _viewport.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Preview render produced no image")
			quit(1)
			return
		var error: Error = image.save_png(DIRECTORY + String(data.id) + ".png")
		if error != OK:
			quit(error)
			return
		_viewport.queue_free()
		await process_frame
	quit()

func _map(points: PackedVector3Array, color: Color) -> Image:
	var image: Image = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(color.darkened(0.7))
	var normalized: PackedVector2Array = MinimapProjection.normalize_points(points)
	for point: Vector2 in normalized:
		var at: Vector2i = Vector2i(point * Vector2(SIZE))
		image.fill_rect(Rect2i(at - Vector2i(3, 3), Vector2i(6, 6)), color.lightened(0.6))
	return image
