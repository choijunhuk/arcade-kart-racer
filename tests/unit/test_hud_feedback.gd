extends GutTest

## 19-D item 4: rank-change popups, lap split math/colour, item-hit toast and
## the wrong-way cue on one player's HUD.


func _make_feedback() -> Dictionary:
	var feedback: HudFeedback = HudFeedback.new()
	feedback.size = Vector2(1280.0, 720.0)
	add_child_autofree(feedback)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(kart)
	feedback.bind(kart, null)
	return {"feedback": feedback, "kart": kart}


func test_rank_delta_text_is_signed() -> void:
	assert_eq(HudFeedback.rank_delta_text(1), "+1")
	assert_eq(HudFeedback.rank_delta_text(2), "+2")
	assert_eq(HudFeedback.rank_delta_text(-1), "-1")


func test_lap_split_against_best_earlier_lap() -> void:
	assert_true(is_nan(HudFeedback.lap_split(41.2, -1.0)), "first lap has no split")
	assert_almost_eq(HudFeedback.lap_split(40.8, 41.2), -0.4, 0.0001)
	assert_almost_eq(HudFeedback.lap_split(42.0, 41.2), 0.8, 0.0001)
	assert_eq(HudFeedback.split_color(-0.4), HudFeedback.GAIN_COLOR, "faster = green")
	assert_eq(HudFeedback.split_color(0.8), HudFeedback.LOSS_COLOR, "slower = red")
	assert_eq(HudFeedback.split_color(NAN), HudFeedback.NEUTRAL_COLOR)


func test_rank_changes_accumulate_while_the_popup_is_up() -> void:
	var context: Dictionary = _make_feedback()
	var feedback: HudFeedback = context["feedback"]
	EventBus.position_changed.emit(context["kart"], 5, 4)
	EventBus.position_changed.emit(context["kart"], 4, 3)
	var label: Label = feedback._rank_label
	assert_true(label.visible)
	assert_eq(label.text, "+2")
	EventBus.position_changed.emit(context["kart"], 3, 4)
	assert_eq(label.text, "+1")


func test_other_karts_do_not_trigger_feedback() -> void:
	var context: Dictionary = _make_feedback()
	var feedback: HudFeedback = context["feedback"]
	var other: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(other)
	EventBus.position_changed.emit(other, 5, 4)
	EventBus.item_hit.emit(context["kart"], other, &"rocket_dart")
	assert_false(feedback._rank_label.visible)
	assert_false(feedback._hit_label.visible)


func test_lap_card_shows_time_and_coloured_split() -> void:
	var context: Dictionary = _make_feedback()
	var feedback: HudFeedback = context["feedback"]
	EventBus.lap_completed.emit(context["kart"], 1, 41.0)
	assert_string_contains(feedback._lap_label.text, "0:41.000")
	EventBus.lap_completed.emit(context["kart"], 2, 81.5)
	assert_string_contains(feedback._lap_label.text, "-0.500")
	assert_eq(feedback._lap_label.get_theme_color("font_color"), HudFeedback.GAIN_COLOR)
	EventBus.lap_completed.emit(context["kart"], 3, 123.0)
	assert_string_contains(feedback._lap_label.text, "+1.000")
	assert_eq(feedback._lap_label.get_theme_color("font_color"), HudFeedback.LOSS_COLOR)


func test_item_hit_names_the_item_and_wrong_way_adds_turn_hint() -> void:
	var context: Dictionary = _make_feedback()
	var feedback: HudFeedback = context["feedback"]
	EventBus.item_hit.emit(null, context["kart"], &"rocket_dart")
	assert_true(feedback._hit_label.visible)
	assert_string_contains(feedback._hit_label.text, "ROCKET DART")
	EventBus.wrong_way.emit(context["kart"], true)
	assert_true(feedback._turn_label.visible)
	EventBus.wrong_way.emit(context["kart"], false)
	assert_false(feedback._turn_label.visible)
