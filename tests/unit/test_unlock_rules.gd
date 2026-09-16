extends GutTest

## Phase 18e-3: the unlock rule table is pure over SaveManager data, the
## bypass switches open everything, and evaluate_new never repeats a key.

const TRACK_02: String = "track_02_lumen_underpass"
const TRACK_03: String = "track_03_glacier_crown"
const ALL_TRACKS: Array[String] = [
	"track_01_ridgeline_circuit", TRACK_02, TRACK_03, "track_04_ochre_rift",
]
const TEST_SETTINGS_PATH: String = "user://phase18e_unlock_rules_settings.cfg"

var _settings_path: String


func before_each() -> void:
	_settings_path = SettingsManager.settings_path
	SettingsManager.settings_path = TEST_SETTINGS_PATH
	SettingsManager.load_settings()
	GameState.automation_mode = false


func after_each() -> void:
	GameState.automation_mode = false
	SettingsManager.settings_path = _settings_path
	SettingsManager.load_settings()
	DirAccess.remove_absolute(TEST_SETTINGS_PATH)


func test_content_without_a_rule_is_open_and_ruled_content_starts_locked() -> void:
	var data: Dictionary = SaveManager.default_data()
	assert_true(UnlockRules.is_unlocked("track", "track_01_ridgeline_circuit", data))
	assert_true(UnlockRules.is_unlocked("kart", "medium", data))
	assert_true(UnlockRules.is_unlocked("driver", "aurora_vale", data))
	assert_true(UnlockRules.is_unlocked("speed_class", "cruise", data))
	assert_false(UnlockRules.is_unlocked("track", TRACK_03, data))
	assert_false(UnlockRules.is_unlocked("kart", "basalt_crown", data))
	assert_false(UnlockRules.is_unlocked("driver", "nyx_calder", data))
	assert_false(UnlockRules.is_unlocked("speed_class", "turbo", data))
	assert_false(UnlockRules.is_unlocked("mode", "mirror", data))
	assert_eq(UnlockRules.locked_hint("track", TRACK_03), "Finish top 3 on Lumen Underpass")
	assert_eq(UnlockRules.locked_hint("kart", "medium"), "")


func test_track_position_rule_reads_top_level_or_profile_one_records() -> void:
	var data: Dictionary = SaveManager.default_data()
	data["best_positions"][TRACK_02] = 4
	assert_false(UnlockRules.condition_met("track", TRACK_03, data), "4th is outside the top 3")
	data["best_positions"][TRACK_02] = 3
	assert_true(UnlockRules.condition_met("track", TRACK_03, data))

	var profile_only: Dictionary = SaveManager.default_data()
	profile_only["player_profiles"]["P1"]["best_positions"][TRACK_02] = 2
	assert_true(UnlockRules.condition_met("track", TRACK_03, profile_only), "P1 profile records count too")


func test_gp_position_rule_honours_the_optional_speed_class_suffix() -> void:
	var data: Dictionary = SaveManager.default_data()
	data["grand_prix_bests"]["horizon_cup_turbo/normal"] = {"position": 1, "points": 60}
	assert_true(UnlockRules.condition_met("kart", "basalt_crown", data), "any class counts for top 3")
	assert_true(UnlockRules.condition_met("kart", "zephyr_needle", data), "any class counts for a win")
	assert_true(UnlockRules.condition_met("mode", "mirror", data))
	assert_false(UnlockRules.condition_met("speed_class", "turbo", data), "TURBO needs a STANDARD cup result")

	data["grand_prix_bests"]["horizon_cup/hard"] = {"position": 4, "points": 30}
	assert_false(UnlockRules.condition_met("speed_class", "turbo", data), "4th in STANDARD is not top 3")
	data["grand_prix_bests"]["horizon_cup/easy"] = {"position": 3, "points": 40}
	assert_true(UnlockRules.condition_met("speed_class", "turbo", data))


func test_gp_position_rule_counts_mirror_runs_of_the_same_speed_class() -> void:
	var data: Dictionary = SaveManager.default_data()
	data["grand_prix_bests"]["horizon_cup_mirror/normal"] = {"position": 2, "points": 50}
	assert_true(UnlockRules.condition_met("speed_class", "turbo", data), "a STANDARD mirror cup is still a STANDARD cup")
	data["grand_prix_bests"].clear()
	data["grand_prix_bests"]["horizon_cup_turbo_mirror/normal"] = {"position": 1, "points": 60}
	assert_false(UnlockRules.condition_met("speed_class", "turbo", data), "TURBO mirror is not STANDARD")
	assert_true(UnlockRules.condition_met("mode", "mirror", data))


func test_wins_rule_counts_stats_and_best_laps_all_needs_every_track() -> void:
	var data: Dictionary = SaveManager.default_data()
	data["stats"]["wins"] = 4
	assert_false(UnlockRules.condition_met("driver", "nyx_calder", data))
	data["stats"]["wins"] = 5
	assert_true(UnlockRules.condition_met("driver", "nyx_calder", data))

	for track: String in ALL_TRACKS.slice(0, 3):
		data["best_laps"][track] = 70_000
	assert_false(UnlockRules.condition_met("driver", "echo_meridian", data), "three of four tracks is not enough")
	data["best_laps"][ALL_TRACKS[3]] = 80_000
	assert_true(UnlockRules.condition_met("driver", "echo_meridian", data))

	var no_stats: Dictionary = SaveManager.default_data()
	no_stats.erase("stats")
	assert_false(UnlockRules.condition_met("driver", "nyx_calder", no_stats), "a save without stats is simply zero wins")


func test_evaluate_new_returns_only_unannounced_keys_without_duplicates() -> void:
	var data: Dictionary = SaveManager.default_data()
	data["grand_prix_bests"]["horizon_cup/normal"] = {"position": 1, "points": 60}
	data["best_positions"][TRACK_02] = 1

	var fresh: Array[String] = UnlockRules.evaluate_new(data, [])
	assert_eq(fresh, ["track:%s" % TRACK_03, "kart:basalt_crown", "kart:zephyr_needle", "speed_class:turbo", "mode:mirror"])
	for key: String in fresh:
		assert_eq(fresh.count(key), 1, "no duplicate keys")

	var remaining: Array[String] = UnlockRules.evaluate_new(data, ["kart:basalt_crown", "mode:mirror"])
	assert_false(remaining.has("kart:basalt_crown"))
	assert_false(remaining.has("mode:mirror"))
	assert_true(remaining.has("kart:zephyr_needle"))
	assert_eq(UnlockRules.evaluate_new(data, fresh), [], "everything already announced")


func test_bypass_switches_open_everything_but_never_leak_into_evaluate_new() -> void:
	var data: Dictionary = SaveManager.default_data()
	assert_false(UnlockRules.is_unlocked("kart", "zephyr_needle", data))

	GameState.automation_mode = true
	assert_true(UnlockRules.is_unlocked("kart", "zephyr_needle", data))
	assert_true(UnlockRules.is_unlocked("mode", "mirror", data))
	assert_eq(UnlockRules.evaluate_new(data, []), [], "automation must not announce unearned unlocks")
	GameState.automation_mode = false
	assert_false(UnlockRules.is_unlocked("kart", "zephyr_needle", data))

	SettingsManager.set_setting(&"gameplay", &"unlock_all", true)
	assert_true(UnlockRules.is_unlocked("kart", "zephyr_needle", data))
	assert_true(UnlockRules.is_unlocked("track", TRACK_03, data))
	assert_eq(UnlockRules.evaluate_new(data, []), [], "unlock_all must not announce unearned unlocks")
	SettingsManager.set_setting(&"gameplay", &"unlock_all", false)
	assert_false(UnlockRules.is_unlocked("track", TRACK_03, data))


func test_default_settings_carry_unlock_all_off() -> void:
	assert_false(bool(SettingsManager.default_settings()["gameplay"]["unlock_all"]))
	assert_false(bool(SettingsManager.get_setting(&"gameplay", &"unlock_all", true)))


func test_locked_last_selection_falls_back_to_defaults() -> void:
	var data: Dictionary = SaveManager.default_data()
	var selection: Dictionary = {"driver": "nyx_calder", "kart": "zephyr_needle", "track": TRACK_03}
	var sanitized: Dictionary = UnlockRules.sanitized_selection(selection, data)
	var defaults: Dictionary = SaveManager.default_data()["last_selection"]
	assert_eq(sanitized["driver"], defaults["driver"])
	assert_eq(sanitized["kart"], defaults["kart"])
	assert_eq(sanitized["track"], defaults["track"])

	var open: Dictionary = {"driver": "aurora_vale", "kart": "heavy", "track": "track_01_ridgeline_circuit"}
	assert_eq(UnlockRules.sanitized_selection(open, data), open, "open picks are kept verbatim")
	data["grand_prix_bests"]["horizon_cup/normal"] = {"position": 1, "points": 60}
	assert_eq(UnlockRules.sanitized_selection(selection, data)["kart"], "zephyr_needle", "earned picks are kept")


func test_announcement_lists_display_names() -> void:
	assert_eq(UnlockRules.announcement([]), "")
	assert_eq(UnlockRules.announcement(["kart:zephyr_needle"]), "UNLOCKED: Zephyr Needle")
	assert_eq(
		UnlockRules.announcement(["track:%s" % TRACK_03, "speed_class:turbo"]),
		"UNLOCKED: Glacier Crown, Turbo class",
	)
