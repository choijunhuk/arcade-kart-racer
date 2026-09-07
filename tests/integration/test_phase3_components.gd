extends GutTest

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const BOOST_PAD_PATH: String = "res://track/elements/boost_pad.tscn"
const JUMP_PAD_PATH: String = "res://track/elements/jump_pad.tscn"
const HAIRPIN_PATH: String = "res://track/tracks/test_hairpin/test_hairpin.tscn"


func test_boost_pad_requests_configured_boost_from_kart() -> void:
	assert_true(ResourceLoader.exists(BOOST_PAD_PATH))
	if not ResourceLoader.exists(BOOST_PAD_PATH):
		return
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var pad: Area3D = (load(BOOST_PAD_PATH) as PackedScene).instantiate() as Area3D
	add_child_autofree(pad)
	await wait_physics_frames(1)
	pad.call("_on_body_entered", kart)

	assert_eq(pad.collision_layer, 16)
	assert_eq(pad.collision_mask, 2)
	assert_eq(kart.boost_controller.get_source(), &"boost_pad")
	assert_gt(kart.boost_controller.get_result().speed_mult, 1.0)


func test_jump_pad_launches_kart_through_physics_api() -> void:
	assert_true(ResourceLoader.exists(JUMP_PAD_PATH))
	if not ResourceLoader.exists(JUMP_PAD_PATH):
		return
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var pad: Area3D = (load(JUMP_PAD_PATH) as PackedScene).instantiate() as Area3D
	add_child_autofree(pad)
	await wait_physics_frames(1)
	pad.call("_on_body_entered", kart)

	assert_eq(pad.collision_layer, 16)
	assert_eq(pad.collision_mask, 2)
	assert_true(kart.has_method("launch"))
	assert_false(kart.is_grounded())


func test_required_pads_are_placed_on_flat_and_hills_tracks() -> void:
	var flat: Node = (load("res://track/tracks/test_loop/test_loop.tscn") as PackedScene).instantiate()
	var hills: Node = (load("res://track/tracks/test_loop_hills/test_loop_hills.tscn") as PackedScene).instantiate()
	add_child_autofree(flat)
	add_child_autofree(hills)

	assert_eq(flat.get_node("BoostPads").get_child_count(), 2)
	assert_eq(hills.get_node("JumpPads").get_child_count(), 1)
	assert_not_null(hills.get_node_or_null("Geometry/LandingZone"))


func test_hairpin_track_exists_and_has_required_curve_shape() -> void:
	assert_true(ResourceLoader.exists(HAIRPIN_PATH))
	if not ResourceLoader.exists(HAIRPIN_PATH):
		return
	var track: TrackRoot = (load(HAIRPIN_PATH) as PackedScene).instantiate() as TrackRoot
	add_child_autofree(track)
	await wait_physics_frames(1)
	var line: Path3D = track.get_node("RacingLine") as Path3D

	assert_gte(line.curve.point_count, 12)
	assert_gte(track.get_node("Checkpoints").get_child_count(), 4)
	assert_gte(track.get_node("StartGrid").get_child_count(), 8)


func test_kart_feedback_uses_no_more_than_six_particle_nodes() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var particle_count: int = 0
	for node: Node in kart.find_children("*", "GPUParticles3D", true, false):
		particle_count += 1

	assert_not_null(kart.get_node_or_null("DriftEffects"))
	assert_not_null(kart.get_node_or_null("BoostEffects"))
	assert_lte(particle_count, 6)
	assert_gte(particle_count, 1)


func test_sandbox_contains_phase3_drift_meter() -> void:
	var sandbox: Node = (load("res://scenes/test/kart_sandbox.tscn") as PackedScene).instantiate()
	add_child_autofree(sandbox)

	assert_not_null(sandbox.get_node_or_null("HUD/DriftMeter"))
