extends GutTest

## 19-D item 3: opponent name tags (distance fade, rival relation, settings
## toggle) drawn per viewport from read-only race state.

var _saved_setting: Variant


func before_each() -> void:
	_saved_setting = SettingsManager.get_setting(&"gameplay", &"name_tags", true)


func after_each() -> void:
	SettingsManager.set_setting(&"gameplay", &"name_tags", _saved_setting)


func test_tags_fade_out_with_distance() -> void:
	assert_eq(RaceNameTags.fade_for_distance(5.0), 1.0)
	assert_eq(RaceNameTags.fade_for_distance(RaceNameTags.NEAR_DISTANCE), 1.0)
	var middle: float = RaceNameTags.fade_for_distance((RaceNameTags.NEAR_DISTANCE + RaceNameTags.FAR_DISTANCE) * 0.5)
	assert_between(middle, 0.1, 0.9)
	assert_eq(RaceNameTags.fade_for_distance(RaceNameTags.FAR_DISTANCE + 1.0), 0.0)


func test_rival_is_the_racer_directly_ahead_or_behind() -> void:
	assert_eq(RaceNameTags.rival_for(4, 3), RaceNameTags.Rival.AHEAD)
	assert_eq(RaceNameTags.rival_for(4, 5), RaceNameTags.Rival.BEHIND)
	assert_eq(RaceNameTags.rival_for(4, 2), RaceNameTags.Rival.NONE)
	assert_eq(RaceNameTags.rival_for(1, 2), RaceNameTags.Rival.BEHIND)
	assert_eq(RaceNameTags.rival_for(0, 1), RaceNameTags.Rival.NONE, "unranked player has no rival")


func test_setting_toggles_the_tags() -> void:
	var tags: RaceNameTags = RaceNameTags.new()
	add_child_autofree(tags)
	SettingsManager.set_setting(&"gameplay", &"name_tags", false)
	assert_false(tags.is_enabled())
	SettingsManager.set_setting(&"gameplay", &"name_tags", true)
	assert_true(tags.is_enabled())
	assert_true(bool(SettingsManager.default_settings()["gameplay"]["name_tags"]), "on by default")


func test_hud_binds_name_tags_to_the_viewport_player() -> void:
	var hud: RaceHud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as RaceHud
	add_child_autofree(hud)
	var tags: RaceNameTags = hud.get_node("NameTags") as RaceNameTags
	assert_not_null(tags)
	assert_eq(tags.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_overlapping_tags_are_decluttered() -> void:
	var placed: Array[Rect2] = [Rect2(100.0, 100.0, 80.0, 20.0)]
	assert_false(RaceNameTags.declutter_accepts(Rect2(150.0, 110.0, 80.0, 20.0), placed))
	assert_true(RaceNameTags.declutter_accepts(Rect2(100.0, 140.0, 80.0, 20.0), placed))


func test_tag_scratch_is_allocated_once_per_bind() -> void:
	var tags: RaceNameTags = RaceNameTags.new()
	add_child_autofree(tags)
	var karts: Array[KartController] = []
	for _index: int in range(3):
		var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
		add_child_autofree(kart)
		karts.append(kart)
	tags.bind(karts[0], null, karts)
	assert_eq(tags._pool.size(), 2, "one reusable tag per opponent")
	var first: RaceNameTags.TagInfo = tags._pool[0]
	tags._draw()
	tags._draw()
	assert_same(tags._pool[0], first, "draws reuse the pooled tags")
