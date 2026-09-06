extends GutTest


func test_game_state_selection_can_be_reset_for_a_new_session() -> void:
	var state: GameStateService = GameStateService.new()
	autofree(state)
	state.set_selection(&"pilot_one", &"medium", &"test_loop")

	state.reset_session()

	assert_eq(state.selected_driver_id, &"")
	assert_eq(state.selected_kart_id, &"")
	assert_eq(state.selected_track_id, &"")


func test_audio_manager_creates_required_buses_and_round_trips_volume() -> void:
	var manager: AudioManagerService = AudioManagerService.new()
	autofree(manager)
	manager.ensure_audio_buses()

	manager.set_bus_volume(&"SFX", 0.4)

	assert_gte(AudioServer.get_bus_index("Music"), 0)
	assert_gte(AudioServer.get_bus_index("SFX"), 0)
	assert_gte(AudioServer.get_bus_index("Engine"), 0)
	assert_almost_eq(manager.get_bus_volume(&"SFX"), 0.4, 0.001)
	manager.set_bus_volume(&"SFX", 1.0)
