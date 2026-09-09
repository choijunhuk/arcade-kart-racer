extends GutTest

func test_online_lobby_has_shared_panels_and_enabled_connection_controls() -> void:
	var lobby: OnlineLobby = (load("res://ui/menus/online_lobby.tscn") as PackedScene).instantiate() as OnlineLobby
	add_child_autofree(lobby)
	await wait_process_frames(2)
	assert_eq(lobby.get_node("Panel/VBox/Players").get_child_count(), NetTuning.MAX_PLAYERS)
	assert_false((lobby.get("_host") as Button).disabled)
	assert_false((lobby.get("_join") as Button).disabled)
	assert_true((lobby.get("_ready_button") as Button).disabled)
	assert_eq(int((lobby.get("_port") as SpinBox).value), NetTuning.PORT)

func test_main_menu_exposes_online_and_disconnection_message() -> void:
	GameState.network_message = "Host disconnected."
	var menu: MainMenu = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child_autofree(menu)
	assert_false((menu.get_node("Panel/VBox/OnlineButton") as Button).disabled)
	assert_eq((menu.get_node("Panel/VBox/NetworkMessage") as Label).text, "Host disconnected.")
	assert_eq(GameState.network_message, "")
