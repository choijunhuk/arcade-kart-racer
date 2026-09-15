class_name FirstRaceHintsService
extends Node

## First real race, 3 one-shot contextual hints (spec §1): drift before the
## first corner, use-item on the first pickup, trick off the first ramp.
## Grounded in real EventBus signals, gated off during the tutorial itself,
## automation, and any headless/CLI run so no automated harness ever sees it.
## Persists one-shot state and the enable toggle through SettingsManager.

const DISPLAY_SECONDS: float = 3.5

const HINT_TEXT: Dictionary = {
	FirstRaceHintsState.Hint.DRIFT: "TIP: hold DRIFT through corners for a speed boost",
	FirstRaceHintsState.Hint.ITEM: "TIP: press USE ITEM to fire what you picked up",
	FirstRaceHintsState.Hint.RAMP: "TIP: hold DRIFT in the air off a ramp for a trick boost",
}

@onready var _label: Label = _build_label()

## Bumped on every _display() call so a stale SceneTreeTimer from an earlier
## hint can't hide a newer one that is still showing.
var _display_generation: int = 0

## Test-only escape hatch: non-null Array replaces the RaceManager-derived
## local-human roster used by `_is_local()`'s network locality check (mirrors
## `RaceTelemetryService.roster_override`).
var local_karts_override: Variant = null


func _ready() -> void:
	EventBus.race_started.connect(_on_race_started)
	EventBus.roulette_started.connect(_on_roulette_started)
	EventBus.kart_launched.connect(_on_kart_launched)


func _on_race_started() -> void:
	_maybe_show(FirstRaceHintsState.Hint.DRIFT, null)


func _on_roulette_started(kart: Node) -> void:
	_maybe_show(FirstRaceHintsState.Hint.ITEM, kart)


func _on_kart_launched(kart: Node) -> void:
	_maybe_show(FirstRaceHintsState.Hint.RAMP, kart)


func _maybe_show(hint: FirstRaceHintsState.Hint, kart: Node) -> void:
	if not _eligible(kart):
		return
	var state: FirstRaceHintsState = FirstRaceHintsState.new(
		bool(SettingsManager.get_setting(&"tutorial", &"hints_enabled", true)),
		SettingsManager.get_setting(&"tutorial", &"hints_seen", {}),
	)
	if not state.consume(hint):
		return
	SettingsManager.update_setting(&"tutorial", &"hints_seen", state.seen_snapshot())
	_display(String(HINT_TEXT.get(hint, "")))


## Excludes automation, the tutorial itself, and every headless/CLI run
## (GUT tests, snapshot/perf probes, the sim harness) from ever seeing a hint,
## and (audit finding 3) a remote networked player's actions from ever
## triggering a hint on this machine.
func _eligible(kart: Node) -> bool:
	if not is_eligible(
		kart,
		DisplayServer.get_name() == "headless",
		GameState.automation_mode,
		GameState.tutorial_active,
		GameState.current_mode,
	):
		return false
	return _is_local(kart)


## `kart`'s InputProvider type alone can't tell local from remote online — a
## remote human kart uses the same `PlayerInputProvider` this machine's own
## kart does (see `RaceManager.get_local_human_karts()`). Offline,
## `GameState.net_session` is null and every eligible kart is local, matching
## prior behavior.
func _is_local(kart: Node) -> bool:
	if GameState.net_session == null or kart == null:
		return true
	if local_karts_override != null:
		return (local_karts_override as Array).has(kart)
	var manager: RaceManager = get_tree().current_scene as RaceManager
	return manager != null and manager.get_local_human_karts().has(kart)


## Pure gate check (no autoload/DisplayServer reads) so it is testable without
## a scene tree. Mirrors `_eligible()`'s rules exactly.
static func is_eligible(
	kart: Node, is_headless: bool, automation_mode: bool, tutorial_active: bool, current_mode: int,
) -> bool:
	if is_headless or automation_mode or tutorial_active:
		return false
	if current_mode != GameState.Mode.RACE:
		return false
	if kart != null and not (kart is KartController and (kart as KartController).input_provider is PlayerInputProvider):
		return false
	return true


func _display(text: String) -> void:
	if text.is_empty():
		return
	_label.text = text
	_label.visible = true
	_display_generation += 1
	get_tree().create_timer(DISPLAY_SECONDS).timeout.connect(_on_hide_timeout.bind(_display_generation))


func _on_hide_timeout(generation: int) -> void:
	if generation != _display_generation:
		return # A newer hint is already showing; let its own timer hide it.
	if is_instance_valid(_label):
		_label.visible = false


func _build_label() -> Label:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	var label: Label = Label.new()
	label.visible = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -260.0
	label.offset_right = 260.0
	label.offset_top = 100.0
	label.offset_bottom = 140.0
	layer.add_child(label)
	return label
