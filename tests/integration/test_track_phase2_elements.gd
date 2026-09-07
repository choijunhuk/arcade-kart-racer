extends GutTest

const OFFROAD_ZONE_SCENE: String = "res://track/elements/offroad_zone.tscn"
const KILL_ZONE_SCENE: String = "res://track/elements/kill_zone.tscn"
const RESPAWN_SYSTEM_SCRIPT: String = "res://race/respawn_system.gd"


func test_phase2_track_element_resources_exist() -> void:
	assert_true(ResourceLoader.exists(OFFROAD_ZONE_SCENE))
	assert_true(ResourceLoader.exists(KILL_ZONE_SCENE))
	assert_true(ResourceLoader.exists(RESPAWN_SYSTEM_SCRIPT))


func test_flat_loop_has_two_grass_zones_and_a_kill_plane() -> void:
	var track: Node = (load("res://track/tracks/test_loop/test_loop.tscn") as PackedScene).instantiate()
	add_child_autofree(track)

	assert_gte(track.get_node("OffroadZones").get_child_count(), 2)
	assert_gte(track.get_node("KillZones").get_child_count(), 1)
	var first_zone: Area3D = track.get_node("OffroadZones").get_child(0) as Area3D
	assert_eq((first_zone.get("terrain") as TerrainData).id, &"grass")


func test_hills_loop_has_dirt_kill_plane_and_open_outer_wall() -> void:
	var track: Node = (load("res://track/tracks/test_loop_hills/test_loop_hills.tscn") as PackedScene).instantiate()
	add_child_autofree(track)

	assert_gte(track.get_node("OffroadZones").get_child_count(), 1)
	assert_gte(track.get_node("KillZones").get_child_count(), 1)
	var dirt_zone: Area3D = track.get_node("OffroadZones").get_child(0) as Area3D
	assert_eq((dirt_zone.get("terrain") as TerrainData).id, &"dirt")
	assert_null(track.get_node_or_null("Geometry/OuterEastCollision"))
	assert_not_null(track.get_node_or_null("Geometry/OuterEastNorthCollision"))
	assert_not_null(track.get_node_or_null("Geometry/OuterEastSouthCollision"))
