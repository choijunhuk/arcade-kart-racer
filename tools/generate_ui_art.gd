extends SceneTree

## Offline, deterministic original UI art; generated images are redistributable.
const SIZE: int = 128
const ROOT: String = "res://assets/art/"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	for category: String in ["drivers", "karts", "items"]:
		for resource: Resource in ResourceScanner.scan_tres("res://data/" + category):
			var id: String = String(resource.get("id"))
			var color: Color = Color(0.1, 0.8, 1.0)
			if resource is DriverData:
				color = (resource as DriverData).driver_color
			elif resource is KartData:
				color = (resource as KartData).body_color
			else:
				color = Color.from_hsv(float(absi(id.hash()) % 360) / 360.0, 0.7, 0.95)
			var image: Image = _draw(category, color, absi(id.hash()))
			image.save_png(ROOT + id + ".png")
	_draw("karts", Color(0.1, 0.85, 1), 13).save_png(ROOT + "app_icon.png")
	quit()

func _draw(category: String, color: Color, seed_value: int) -> Image:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.02, 0.04, 0.08, 0))
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var p: Vector2 = (Vector2(x, y) - Vector2.ONE * 64.0) / 48.0
			var ink: Color = Color.TRANSPARENT
			if category == "drivers":
				if p.length() < 1.0:
					ink = color.darkened(maxf(0.0, p.y) * 0.3)
				if absf(p.y + 0.05) < 0.22 and absf(p.x) < 0.82:
					ink = Color(0.025, 0.07, 0.13)
				if absf(p.x + 0.25) < 0.1 and p.y < -0.4 and p.y > -0.92:
					ink = Color.WHITE
			elif category == "karts":
				if absf(p.x) < 0.66 and absf(p.y) < 0.8:
					ink = color
				if absf(p.x) > 0.6 and absf(p.x) < 0.95 and absf(absf(p.y) - 0.5) < 0.2:
					ink = Color(0.1, 0.12, 0.16)
				if p.length() < 0.3:
					ink = Color.WHITE
			else:
				var sides: float = float(3 + seed_value % 6)
				var radius: float = 0.65 + 0.2 * cos(p.angle() * sides)
				if p.length() < radius:
					ink = color
				if p.length() < 0.22:
					ink = Color.WHITE
			image.set_pixel(x, y, ink)
	return image
