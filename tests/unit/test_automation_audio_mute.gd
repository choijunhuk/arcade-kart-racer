extends GutTest

## Windowed harness tools (snapshot/perf/collision probes, the online UI driver)
## run with a real audio driver, so automation_mode must silence the master bus.

func after_each() -> void:
	GameState.automation_mode = false


func test_automation_mode_mutes_and_unmutes_the_master_bus() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	assert_gt(master, -1, "project must define a Master bus")
	GameState.automation_mode = true
	assert_true(AudioServer.is_bus_mute(master), "automation must mute the master bus")
	GameState.automation_mode = false
	assert_false(AudioServer.is_bus_mute(master), "leaving automation must unmute")
