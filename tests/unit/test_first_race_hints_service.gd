extends GutTest

## Pure gating tests for FirstRaceHintsService.is_eligible() (spec §1): each
## gate (headless, automation, tutorial, non-player kart) independently
## suppresses a hint, and a real display/hide cycle can't be hidden early by
## a stale timer from a previous hint.

const RACE_MODE: int = GameState.Mode.RACE
const MENU_MODE: int = GameState.Mode.MENU


func test_headless_gate_suppresses_even_when_every_other_gate_passes() -> void:
	assert_false(FirstRaceHintsService.is_eligible(null, true, false, false, RACE_MODE))


func test_automation_mode_gate_suppresses() -> void:
	assert_false(FirstRaceHintsService.is_eligible(null, false, true, false, RACE_MODE))


func test_tutorial_active_gate_suppresses() -> void:
	assert_false(FirstRaceHintsService.is_eligible(null, false, false, true, RACE_MODE))


func test_non_race_mode_gate_suppresses() -> void:
	assert_false(FirstRaceHintsService.is_eligible(null, false, false, false, MENU_MODE))


func test_null_kart_is_eligible_when_every_gate_passes() -> void:
	assert_true(FirstRaceHintsService.is_eligible(null, false, false, false, RACE_MODE))


func test_kart_with_player_input_provider_is_eligible() -> void:
	var kart: KartController = KartController.new()
	kart.input_provider = PlayerInputProvider.new()
	autofree(kart)

	assert_true(FirstRaceHintsService.is_eligible(kart, false, false, false, RACE_MODE))


func test_kart_with_non_player_input_provider_is_not_eligible() -> void:
	var kart: KartController = KartController.new()
	kart.input_provider = InputProvider.new()
	autofree(kart)

	assert_false(FirstRaceHintsService.is_eligible(kart, false, false, false, RACE_MODE))


func test_non_kart_node_is_not_eligible() -> void:
	var not_a_kart: Node = Node.new()
	autofree(not_a_kart)

	assert_false(FirstRaceHintsService.is_eligible(not_a_kart, false, false, false, RACE_MODE))


## Audit finding 3: a remote player's kart action must never trigger a hint
## on this machine — it uses the same PlayerInputProvider this machine's own
## kart does, so only the local-roster check (`local_karts_override` here,
## `RaceManager.get_local_human_karts()` in production) can exclude it.
## Exercises `_is_local()` directly (not `_eligible()`) since the other
## gates in `_eligible()`/`is_eligible()` read the real `DisplayServer`,
## which reports "headless" for every GUT run regardless of this fix.
func test_is_local_excludes_a_remote_kart_when_networked() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	GameState.net_session = session
	var local_kart: KartController = KartController.new()
	local_kart.input_provider = PlayerInputProvider.new()
	autofree(local_kart)
	var remote_kart: KartController = KartController.new()
	remote_kart.input_provider = PlayerInputProvider.new()
	autofree(remote_kart)
	var service: FirstRaceHintsService = FirstRaceHintsService.new()
	add_child_autofree(service)
	await wait_process_frames(1)
	service.local_karts_override = [local_kart]
	assert_true(service.call("_is_local", local_kart))
	assert_false(service.call("_is_local", remote_kart), "a remote networked kart must never count as local")
	GameState.net_session = null


## Offline regression: with no net_session, any kart (including null) still
## counts as local, matching prior (pre-network-fix) behavior.
func test_is_local_still_true_for_any_kart_when_offline() -> void:
	GameState.net_session = null
	var kart: KartController = KartController.new()
	kart.input_provider = PlayerInputProvider.new()
	autofree(kart)
	var service: FirstRaceHintsService = FirstRaceHintsService.new()
	add_child_autofree(service)
	await wait_process_frames(1)
	assert_true(service.call("_is_local", kart))


func test_stale_hide_timer_does_not_hide_a_newer_hint() -> void:
	var service: FirstRaceHintsService = FirstRaceHintsService.new()
	add_child_autofree(service)
	await wait_process_frames(1)

	service.call("_display", "first hint")
	var label: Label = service.get("_label") as Label
	assert_not_null(label)
	if label == null:
		return
	assert_true(label.visible)

	# Simulate the first hint's stale timer firing after a second hint has
	# already started showing (generation 2); it must not hide hint 2.
	service.call("_display", "second hint")
	service.call("_on_hide_timeout", 1)
	assert_true(label.visible, "a stale generation-1 timeout must not hide the generation-2 hint")

	service.call("_on_hide_timeout", 2)
	assert_false(label.visible, "the current generation's timeout must still hide the hint")
