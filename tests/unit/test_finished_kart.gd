extends GutTest

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")


func test_set_frozen_holds_state_until_released() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	assert_true(kart.has_method("set_frozen"))
	if not kart.has_method("set_frozen"):
		return
	kart.call("set_frozen", true)
	kart._physics_process(1.0 / 60.0)
	assert_eq(kart.get_state(), KartState.FROZEN)
	kart.call("set_frozen", false)
	kart._physics_process(1.0 / 60.0)
	assert_ne(kart.get_state(), KartState.FROZEN)


func test_set_finished_keeps_finished_state_while_provider_drives() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	assert_true(kart.has_method("set_finished"))
	if not kart.has_method("set_finished"):
		return
	var provider: InputProvider = InputProvider.new()
	kart.call("set_finished", provider)
	kart._physics_process(1.0 / 60.0)
	assert_eq(kart.get_state(), KartState.FINISHED)
	assert_eq(kart.input_provider, provider)

