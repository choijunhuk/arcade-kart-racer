extends GutTest

## Regression coverage for the Phase 8 review: `set_lod_enabled()` must only
## touch smoke emission through its `enabled == false` branch. A stray,
## unconditional loop previously force-stopped smoke on every call — even
## `set_lod_enabled(true)` — silently killing tire smoke whenever camera-LOD
## ran later than DriftEffects in the same frame.

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const DT: float = 0.1


func test_lod_enabled_true_while_drifting_keeps_smoke_emitting() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	_enter_hold(kart, 1.0)
	var drift_effects: Node = kart.get_node("DriftEffects")
	drift_effects.call("_process", DT)
	var smoke_left: GPUParticles3D = drift_effects.get_node("SmokeLeft") as GPUParticles3D
	var smoke_right: GPUParticles3D = drift_effects.get_node("SmokeRight") as GPUParticles3D
	assert_true(smoke_left.emitting)
	assert_true(smoke_right.emitting)

	drift_effects.call("set_lod_enabled", true)

	assert_true(smoke_left.emitting)
	assert_true(smoke_right.emitting)


func test_lod_disabled_stops_smoke_while_drifting() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	_enter_hold(kart, 1.0)
	var drift_effects: Node = kart.get_node("DriftEffects")
	drift_effects.call("_process", DT)
	var smoke_left: GPUParticles3D = drift_effects.get_node("SmokeLeft") as GPUParticles3D
	var smoke_right: GPUParticles3D = drift_effects.get_node("SmokeRight") as GPUParticles3D
	assert_true(smoke_left.emitting)

	drift_effects.call("set_lod_enabled", false)

	assert_false(smoke_left.emitting)
	assert_false(smoke_right.emitting)


## Drives the kart's own `DriftController` (already configured by
## `KartController._ready()`) directly into `HOLD`, mirroring
## `test_drift_controller.gd`'s `_enter_hold` helper.
func _enter_hold(kart: KartController, direction: float) -> void:
	var hop_duration: float = kart.tuning.drift_hop_duration
	kart.drift_controller.call("step", _frame(direction, true, true), 18.0, true, 0.0, 0.0, false, DT)
	kart.drift_controller.call("step", _frame(direction, true), 18.0, true, 0.0, direction, false, hop_duration)


func _frame(steer: float, held: bool, pressed: bool = false) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.steer = steer
	frame.drift = held
	frame.drift_pressed = pressed
	return frame
