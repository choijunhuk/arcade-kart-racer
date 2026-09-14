extends SceneTree

## Offline, deterministic original UI art; generated images are redistributable.
const SIZE: int = 128
const ROOT: String = "res://assets/art/"

## Item icon colors are grouped by function so silhouette + color both read at a glance.
const ATTACK_COLOR: Color = Color(0.92, 0.16, 0.16)
const DEFENSE_COLOR: Color = Color(0.16, 0.45, 0.95)
const BOOST_COLOR: Color = Color(0.98, 0.78, 0.12)
const DEPLOY_COLOR: Color = Color(0.62, 0.22, 0.85)


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
			elif resource is ItemData:
				color = _item_category_color((resource as ItemData).category)
			else:
				color = Color.from_hsv(float(absi(id.hash()) % 360) / 360.0, 0.7, 0.95)
			var image: Image = _draw(category, color, absi(id.hash()), StringName(id))
			image.save_png(ROOT + id + ".png")
	_draw("karts", Color(0.1, 0.85, 1), 13).save_png(ROOT + "app_icon.png")
	quit()


func _item_category_color(category: int) -> Color:
	match category:
		ItemData.ItemCategory.SHIELD:
			return DEFENSE_COLOR
		ItemData.ItemCategory.BOOST:
			return BOOST_COLOR
		ItemData.ItemCategory.TRAP:
			return DEPLOY_COLOR
		_:
			return ATTACK_COLOR


func _draw(category: String, color: Color, seed_value: int, id: StringName = &"") -> Image:
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
				ink = _item_ink(id, color, p, seed_value)
			image.set_pixel(x, y, ink)
	return image


## Dispatches to a functional silhouette per known item id, falling back to the
## old radial-polygon shape (still deterministic from the id hash) for any
## item added later without an authored silhouette.
func _item_ink(id: StringName, color: Color, p: Vector2, seed_value: int) -> Color:
	match String(id):
		"rocket_dart":
			return _dart_ink(p, color)
		"triple_dart":
			return _triple_dart_ink(p, color)
		"hunter_drone":
			return _drone_ink(p, color)
		"spike_mine":
			return _spike_mine_ink(p, color)
		"nitro_can":
			return _nitro_can_ink(p, color)
		"aegis_bubble":
			return _shield_ink(p, color)
		"pulse_blast":
			return _pulse_blast_ink(p, color)
		"storm_beacon":
			return _storm_beacon_ink(p, color)
		"phantom_decoy":
			return _phantom_decoy_ink(p, color)
		_:
			var sides: float = float(3 + seed_value % 6)
			var radius: float = 0.65 + 0.2 * cos(p.angle() * sides)
			var ink: Color = Color.TRANSPARENT
			if p.length() < radius:
				ink = color
			if p.length() < 0.22:
				ink = Color.WHITE
			return ink


## Rocket Dart: a single dart/rocket pointing up with tail fins.
func _dart_ink(p: Vector2, color: Color) -> Color:
	var ink: Color = Color.TRANSPARENT
	if p.y >= -0.95 and p.y < -0.1:
		var head_width: float = 0.34 * clampf((p.y + 0.95) / 0.85, 0.0, 1.0)
		if absf(p.x) < head_width:
			ink = color
	if p.y >= -0.1 and p.y < 0.55 and absf(p.x) < 0.1:
		ink = color
	if p.y >= 0.4 and p.y <= 0.8:
		var fin_width: float = 0.1 + 0.5 * ((p.y - 0.4) / 0.4)
		if absf(p.x) > 0.1 and absf(p.x) < fin_width:
			ink = color
	return ink


## Triple Dart: three smaller darts fanned side by side.
func _triple_dart_ink(p: Vector2, color: Color) -> Color:
	for offset_x: float in [-0.62, 0.0, 0.62]:
		var local: Vector2 = (p - Vector2(offset_x, -0.05)) / 0.55
		var ink: Color = _dart_ink(local, color)
		if ink.a > 0.0:
			return ink
	return Color.TRANSPARENT


## Hunter Drone: a quad-arm body with propeller rings and a sensor eye.
func _drone_ink(p: Vector2, color: Color) -> Color:
	var ink: Color = Color.TRANSPARENT
	if absf(p.y) < 0.09 and absf(p.x) < 0.95:
		ink = color
	if absf(p.x) < 0.09 and absf(p.y) < 0.95:
		ink = color
	for end: Vector2 in [Vector2(0.95, 0.0), Vector2(-0.95, 0.0), Vector2(0.0, 0.95), Vector2(0.0, -0.95)]:
		var distance: float = (p - end).length()
		if distance < 0.32 and distance > 0.16:
			ink = color
	if p.length() < 0.3:
		ink = color
	if p.length() < 0.12:
		ink = Color.WHITE
	return ink


## Spike Mine: a spiky ball with a darker core ring and a bright trigger dot.
func _spike_mine_ink(p: Vector2, color: Color) -> Color:
	var ink: Color = Color.TRANSPARENT
	var spike_radius: float = 0.42 + 0.4 * pow(maxf(0.0, cos(p.angle() * 8.0)), 3.0)
	if p.length() < spike_radius:
		ink = color
	if p.length() < 0.4:
		ink = color.darkened(0.15)
	if p.length() < 0.12:
		ink = Color.WHITE
	return ink


## Nitro Can: a can body with a lightning bolt marking.
func _nitro_can_ink(p: Vector2, color: Color) -> Color:
	var ink: Color = Color.TRANSPARENT
	var in_body: bool = absf(p.x) < 0.42 and p.y > -0.85 and p.y < 0.85
	if in_body:
		ink = color
	if absf(p.x) < 0.5 and p.y > -0.98 and p.y < -0.75:
		ink = color.lightened(0.2)
	if in_body and _bolt_ink(p, Color.WHITE, 0.11).a > 0.0:
		ink = Color.WHITE
	return ink


## Aegis Bubble: a rounded-top, tapered shield with a bright center emblem.
func _shield_ink(p: Vector2, color: Color) -> Color:
	var ink: Color = Color.TRANSPARENT
	if p.y < 0.0 and (p - Vector2(0.0, -0.2)).length() < 0.62:
		ink = color
	if p.y >= 0.0 and p.y < 0.85 and absf(p.x) < 0.62 * clampf((0.85 - p.y) / 0.85, 0.0, 1.0):
		ink = color
	if (p - Vector2(0.0, -0.15)).length() < 0.22:
		ink = Color.WHITE
	return ink


## Pulse Blast: a solid origin dot with two expanding shockwave rings.
func _pulse_blast_ink(p: Vector2, color: Color) -> Color:
	var ink: Color = Color.TRANSPARENT
	var radius: float = p.length()
	if radius < 0.16:
		ink = color
	if radius > 0.34 and radius < 0.5:
		ink = color
	if radius > 0.68 and radius < 0.86:
		ink = color
	return ink


## Storm Beacon: a flared tower topped with a lightning bolt and a beacon light.
func _storm_beacon_ink(p: Vector2, color: Color) -> Color:
	var ink: Color = Color.TRANSPARENT
	if absf(p.x) < 0.14 and p.y > -0.25 and p.y < 0.85:
		ink = color
	var base_width: float = 0.14 + 0.4 * clampf((p.y - 0.55) / 0.3, 0.0, 1.0)
	if p.y > 0.55 and p.y < 0.85 and absf(p.x) < base_width:
		ink = color
	var bolt_local: Vector2 = Vector2(p.x / 0.55, (p.y + 0.75) / 0.45)
	if p.y < -0.2 and _bolt_ink(bolt_local, Color.WHITE, 0.16).a > 0.0:
		ink = Color.WHITE
	if (p - Vector2(0.0, -0.85)).length() < 0.16:
		ink = color.lightened(0.4)
	return ink


## Phantom Decoy: a hollow, translucent crate with crossed straps.
func _phantom_decoy_ink(p: Vector2, color: Color) -> Color:
	var ink: Color = Color.TRANSPARENT
	var in_outer: bool = absf(p.x) < 0.62 and absf(p.y) < 0.62
	var in_inner: bool = absf(p.x) < 0.42 and absf(p.y) < 0.42
	if in_outer and in_inner:
		var translucent: Color = color
		translucent.a = 0.35
		ink = translucent
	if in_outer and not in_inner:
		ink = color
	if in_inner and (absf(p.x - p.y) < 0.08 or absf(p.x + p.y) < 0.08):
		ink = color.lightened(0.3)
	return ink


## Straight-line-segment distance, used to draw the lightning bolt marking.
func _bolt_ink(p: Vector2, color: Color, thickness: float) -> Color:
	var top: Vector2 = Vector2(0.15, -0.7)
	var mid_left: Vector2 = Vector2(-0.12, 0.05)
	var mid_right: Vector2 = Vector2(0.12, 0.05)
	var bottom: Vector2 = Vector2(-0.15, 0.75)
	var distance: float = minf(
		_seg_dist(p, top, mid_left),
		minf(_seg_dist(p, mid_left, mid_right), _seg_dist(p, mid_right, bottom)),
	)
	if distance < thickness:
		return color
	return Color.TRANSPARENT


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var segment: Vector2 = b - a
	var t: float = clampf((p - a).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + segment * t)
