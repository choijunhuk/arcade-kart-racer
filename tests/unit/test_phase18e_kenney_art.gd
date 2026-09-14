extends GutTest

## Phase 18e: pure-function coverage for the Kenney CC0 art install (model
## pick, scale fit, ground offset, track prop placement distance filter).
## No scene/engine mesh loading here -- see the drive_snapshot/collision_probe
## verification pass in the phase brief for the visual/collision checks.

func test_pick_car_model_matches_closest_reference_color() -> void:
	assert_eq(KartKenneyArt.pick_car_model(Color(0.95, 0.15, 0.1)), &"raceCarRed")
	assert_eq(KartKenneyArt.pick_car_model(Color(0.1, 0.9, 0.3)), &"raceCarGreen")
	assert_eq(KartKenneyArt.pick_car_model(Color(0.97, 0.97, 0.98)), &"raceCarWhite")
	assert_eq(KartKenneyArt.pick_car_model(Color(1.0, 0.7, 0.2)), &"raceCarOrange")


func test_pick_car_model_is_deterministic() -> void:
	var color: Color = Color(0.55, 0.2, 0.85)
	assert_eq(KartKenneyArt.pick_car_model(color), KartKenneyArt.pick_car_model(color))


func test_fit_scale_matches_target_per_axis() -> void:
	var scale: Vector3 = KartKenneyArt.fit_scale(Vector3(0.5, 0.25, 1.0), Vector3(1.0, 0.5, 2.0))
	assert_almost_eq(scale.x, 2.0, 0.0001)
	assert_almost_eq(scale.y, 2.0, 0.0001)
	assert_almost_eq(scale.z, 2.0, 0.0001)


func test_fit_scale_guards_against_zero_source_axis() -> void:
	var scale: Vector3 = KartKenneyArt.fit_scale(Vector3(0.0, 0.25, 1.0), Vector3(1.0, 0.5, 2.0))
	assert_almost_eq(scale.x, 1.0, 0.0001, "a degenerate source axis must not divide by zero")


func test_ground_offset_places_scaled_minimum_on_ground() -> void:
	var offset: float = KartKenneyArt.ground_offset(-0.2, 2.0, -0.35)
	assert_almost_eq(offset, -0.35 - (-0.2 * 2.0), 0.0001)
	# The body's local minimum, once shifted by the offset and scaled, must
	# land exactly on the requested ground height.
	assert_almost_eq(-0.2 * 2.0 + offset, -0.35, 0.0001)
