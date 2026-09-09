extends ContentTrack

## Lumen Underpass: four tight right-angle corners and two boost-only alley cuts.

const TUNNEL_START: Vector3 = Vector3(-200.0, 0.4, 110.0)
const TUNNEL_END: Vector3 = Vector3(140.0, 0.4, 110.0)
const TUNNEL_HEIGHT: float = 7.0
const ALLEY_SPEED: float = 30.0
const OBSTACLE_SCENE: PackedScene = preload("res://track/elements/moving_obstacle.tscn")


func open_inner_wall(point: Vector3) -> bool:
	return (point.x < -255.0 and point.z > 65.0) or (point.x > 255.0 and point.z < -65.0)


func build_theme() -> void:
	TrackBuilder.add_box_segment(geometry, TUNNEL_START + Vector3.UP * TUNNEL_HEIGHT,
		TUNNEL_END + Vector3.UP * TUNNEL_HEIGHT, road_width + 2.0, 1.0, road_material)
	for lateral: float in [-1.0, 1.0]:
		var shift: Vector3 = Vector3(0.0, TUNNEL_HEIGHT * 0.5, lateral * (road_width + 1.0) * 0.5)
		TrackBuilder.add_box_segment(geometry, TUNNEL_START + shift, TUNNEL_END + shift, 1.0, TUNNEL_HEIGHT, wall_material)
	for index: int in range(2):
		var offset: float = line.offset_at(Vector3(-120.0 + float(index) * 160.0, ROAD_HEIGHT, half_depth))
		var gate: MovingObstacle = place(OBSTACLE_SCENE, "MovingObstacles", "SlidingGate%d" % index, offset) as MovingObstacle
		var side: float = -1.0 if index == 0 else 1.0
		gate.path = make_path("MovingObstacles", "GatePath%d" % index, [
			line.sample(offset) + line.right_at(offset) * 7.0 * side + Vector3.UP,
			line.sample(offset) + line.right_at(offset) * 11.0 * side + Vector3.UP,
		])
		gate.loop = false
		gate.speed = 2.0
	_add_alley("PrismAlley", Vector3(-300.0, ROAD_HEIGHT, 66.0), Vector3(-256.0, ROAD_HEIGHT, 110.0))
	_add_alley("RelayAlley", Vector3(300.0, ROAD_HEIGHT, -66.0), Vector3(256.0, ROAD_HEIGHT, -110.0))
	for index: int in range(3):
		place(BOOST_SCENE, "BoostPads", "NeonBoost%d" % index, 160.0 + float(index) * 12.0)


func _add_alley(node_name: String, start: Vector3, end: Vector3) -> void:
	shortcut(node_name, line.offset_at(start), line.offset_at(end), [start, end], ALLEY_SPEED)
