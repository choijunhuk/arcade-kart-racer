class_name RaceAudio
extends Node

## Race-owned EventBus adapter; scene composition supplies player identity/laps.

var _player: KartController
var _total_laps: int = 1
var _active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.countdown_tick.connect(_on_countdown)
	EventBus.race_started.connect(_on_started)
	EventBus.race_state_changed.connect(_on_state)
	EventBus.lap_completed.connect(_on_lap)
	EventBus.kart_finished.connect(_on_finished)
	EventBus.position_changed.connect(_on_position)
	EventBus.item_used.connect(_on_item_used)
	EventBus.item_hit.connect(_on_item_hit)
	EventBus.threat_warning.connect(_on_threat)


func _exit_tree() -> void:
	AudioManager.set_music_ducked(false)
	AudioManager.set_engine_offroad(false)
	AudioManager.set_final_lap(false)
	AudioManager.pool.stop_sfx()


## Rebinds before countdown, also resetting restart-only presentation state.
func configure(player: KartController, total_laps: int) -> void:
	_player = player
	_total_laps = maxi(1, total_laps)
	_active = false
	AudioManager.pool.stop_sfx()
	AudioManager.set_music_ducked(false)
	AudioManager.set_final_lap(false)
	AudioManager.set_engine_offroad(false)


func _on_countdown(value: int) -> void:
	if value > 0:
		AudioManager.play_sfx(&"countdown", null, AudioManagerService.PRIORITY_RACE)


func _on_started() -> void:
	AudioManager.play_sfx(&"go", null, AudioManagerService.PRIORITY_RACE)
	AudioManager.set_final_lap(_total_laps == 1)


func _on_state(_previous: int, current: int) -> void:
	AudioManager.set_music_ducked(current == RaceState.PAUSED)
	_active = current == RaceState.RACING or current == RaceState.FINISHING
	match current:
		RaceState.COUNTDOWN:
			AudioManager.play_bgm(&"race")
		RaceState.RESULTS:
			AudioManager.set_final_lap(false)
			AudioManager.play_bgm(&"results")


func _on_lap(kart: Node, lap: int, _time: float) -> void:
	if kart != _player or lap >= _total_laps:
		return # AI laps and the finish line have their own feedback rules.
	var final_lap: bool = lap == _total_laps - 1
	AudioManager.play_sfx(&"final_lap" if final_lap else &"lap", null, AudioManagerService.PRIORITY_RACE)
	AudioManager.set_final_lap(final_lap)


func _on_finished(kart: Node, _time: float) -> void:
	if kart == _player:
		AudioManager.play_sfx(&"finish", null, AudioManagerService.PRIORITY_RACE)


func _on_position(kart: Node, old_position: int, new_position: int) -> void:
	if not _active or kart != _player or old_position <= 0 or new_position == old_position:
		return # Registration/AI rank changes do not announce a player overtake.
	AudioManager.play_sfx(&"position_up" if new_position < old_position else &"position_down", null, AudioManagerService.PRIORITY_UI)


func _on_item_used(kart: Node, id: StringName) -> void:
	_play_item(kart, StringName("%s_fire" % id))


func _on_item_hit(_source: Node, target: Node, id: StringName) -> void:
	_play_item(target, StringName("%s_hit" % id))


func _play_item(node: Node, sound: StringName) -> void:
	var kart: KartController = node as KartController
	if not is_instance_valid(kart):
		return # Item expiry can race scene teardown; there is no audible owner then.
	AudioManager.play_kart_sfx(sound, kart, kart == _player)


func _on_threat(kart: Node, _id: StringName, _seconds: float) -> void:
	if kart == _player:
		AudioManager.play_sfx(&"threat_warning", null, AudioManagerService.PRIORITY_RACE)
