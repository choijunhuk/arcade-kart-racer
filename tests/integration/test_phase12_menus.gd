extends GutTest


func after_each() -> void:
	GameState.reset_session()
	for child: Node in get_tree().root.get_children():
		if child is TransitionOverlay:
			child.free()


func test_six_kart_cards_wrap_across_both_rows_and_scroll_to_focus() -> void:
	var menu: KartSelectMenu = (load("res://ui/menus/kart_select.tscn") as PackedScene).instantiate() as KartSelectMenu
	add_child_autofree(menu)
	await wait_process_frames(2)
	var grid: GridContainer = menu.get_node("Panel/VBox/Scroll/Grid") as GridContainer
	var scroll: ScrollContainer = menu.get_node("Panel/VBox/Scroll") as ScrollContainer
	assert_eq(grid.get_child_count(), 6)
	var first: Control = grid.get_child(0) as Control
	var last_row: Control = grid.get_child(3) as Control
	assert_same(first.get_node(first.focus_neighbor_bottom), last_row)
	assert_same(last_row.get_node(last_row.focus_neighbor_bottom), first)
	assert_same(first.get_node(first.focus_neighbor_left), grid.get_child(2))
	last_row.grab_focus()
	await wait_process_frames(3)
	assert_true(scroll.follow_focus)
	assert_gt(scroll.scroll_vertical, 0)


func test_grand_prix_skips_individual_track_selection() -> void:
	GameState.selected_race_mode = RaceConfig.RaceMode.GRAND_PRIX
	var menu: KartSelectMenu = (load("res://ui/menus/kart_select.tscn") as PackedScene).instantiate() as KartSelectMenu
	add_child_autofree(menu)
	menu._select_kart(load("res://data/karts/medium.tres") as KartData)
	assert_eq(GameState.selected_track_id, &"track_01_ridgeline_circuit")
	assert_not_null(get_tree().root.get_node_or_null("SceneTransition"))


func test_time_trial_difficulty_screen_forces_the_item_toggle_off() -> void:
	GameState.selected_race_mode = RaceConfig.RaceMode.TIME_TRIAL
	var menu: DifficultySelectMenu = (load("res://ui/menus/difficulty_select.tscn") as PackedScene).instantiate() as DifficultySelectMenu
	add_child_autofree(menu)
	var toggle: CheckButton = menu.get_node("Panel/VBox/ItemsToggle") as CheckButton
	assert_false(toggle.button_pressed)
	assert_true(toggle.disabled)


func test_track_menu_four_cards_and_back_fit_in_the_viewport() -> void:
	var menu: TrackSelectMenu = (load("res://ui/menus/track_select.tscn") as PackedScene).instantiate() as TrackSelectMenu
	add_child_autofree(menu)
	await wait_process_frames(3)
	var list: VBoxContainer = menu.get_node("Panel/VBox/TrackList") as VBoxContainer
	assert_eq(list.get_child_count(), 4)
	var back: Control = menu.get_node("Panel/VBox/BackButton") as Control
	assert_lte(back.get_global_rect().end.y, get_viewport().get_visible_rect().end.y)
	assert_gte((list.get_child(0) as Control).get_global_rect().position.y, 0.0)
