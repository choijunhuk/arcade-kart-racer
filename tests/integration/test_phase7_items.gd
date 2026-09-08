extends GutTest

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const SANDBOX_SCENE: PackedScene = preload("res://scenes/test/kart_sandbox.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud/hud.tscn")
const TEST_TRACK: PackedScene = preload("res://track/tracks/test_loop/test_loop.tscn")
const EPSILON: float = 0.01


func test_phase7_nodes_are_composed_in_kart_race_sandbox_and_hud() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	var race: Node = RACE_SCENE.instantiate()
	var sandbox: Node = SANDBOX_SCENE.instantiate()
	var hud: Node = HUD_SCENE.instantiate()
	autofree(kart)
	autofree(race)
	autofree(sandbox)
	autofree(hud)
	assert_not_null(kart.get_node_or_null("ItemSlot") as ItemSlot)
	assert_not_null(race.get_node_or_null("ItemManager") as ItemManager)
	assert_not_null(sandbox.get_node_or_null("ItemManager") as ItemManager)
	assert_not_null(hud.get_node_or_null("ItemPanel/Icon") as TextureRect)
	assert_not_null(hud.get_node_or_null("ThreatWarning") as Label)
	assert_not_null(hud.get_node_or_null("ShieldTimer") as TextureProgressBar)
	assert_true(ResourceLoader.exists("res://effects/impact_effect.tscn"))


func test_aegis_absorbs_one_dart_then_the_next_dart_hits() -> void:
	var owner: KartController = _make_kart("Owner")
	var target: KartController = _make_kart("Target")
	var context: ItemContext = _make_context([owner, target])
	var shield: ShieldItem = (preload("res://data/items/aegis_bubble.tres").scene.instantiate() as ShieldItem)
	var dart: ProjectileItem = (preload("res://data/items/rocket_dart.tres").scene.instantiate() as ProjectileItem)
	add_child_autofree(shield)
	add_child_autofree(dart)
	shield.setup(preload("res://data/items/aegis_bubble.tres"), target, context)
	shield.activate(InputFrame.zero())
	dart.setup(preload("res://data/items/rocket_dart.tres"), owner, context)
	dart.on_hit(target)
	assert_false(bool(target.call("has_shield")))
	assert_eq(target.get_hit_state(), -1)
	dart.on_hit(target)
	assert_eq(target.get_hit_state(), HitReactor.HitType.SPIN_OUT)


func test_pulse_telegraphs_then_bumps_and_cancels_target_drift() -> void:
	var owner: KartController = _make_kart("Owner")
	var target: KartController = _make_kart("Target")
	owner.global_position = Vector3.ZERO
	target.global_position = Vector3(1.0, 0.0, 0.0)
	var press: InputFrame = InputFrame.new()
	press.steer = 1.0
	press.drift = true
	press.drift_pressed = true
	target.drift_controller.step(press, 18.0, true, 0.0, 0.0, false, 0.1)
	press.drift_pressed = false
	target.drift_controller.step(press, 18.0, true, 0.0, 1.0, false, target.tuning.drift_hop_duration)
	assert_eq(target.get_drift_state(), DriftController.DriftState.HOLD)
	var pulse: AreaItem = preload("res://data/items/pulse_blast.tres").scene.instantiate() as AreaItem
	add_child_autofree(pulse)
	pulse.setup(preload("res://data/items/pulse_blast.tres"), owner, _make_context([owner, target]))
	pulse.activate(InputFrame.zero())
	pulse.tick(0.299)
	assert_eq(target.get_hit_state(), -1)
	pulse.tick(0.001)
	assert_eq(target.get_drift_state(), DriftController.DriftState.NONE)
	assert_eq(target.get_hit_state(), HitReactor.HitType.BUMP)


func test_aegis_absorbs_pulse_blast_bump_hit() -> void:
	var owner: KartController = _make_kart("Owner")
	var target: KartController = _make_kart("Target")
	owner.global_position = Vector3.ZERO
	target.global_position = Vector3(1.0, 0.0, 0.0)
	var context: ItemContext = _make_context([owner, target])
	var shield: ShieldItem = (preload("res://data/items/aegis_bubble.tres").scene.instantiate() as ShieldItem)
	add_child_autofree(shield)
	shield.setup(preload("res://data/items/aegis_bubble.tres"), target, context)
	shield.activate(InputFrame.zero())
	var pulse_data: ItemData = preload("res://data/items/pulse_blast.tres")
	var pulse: AreaItem = pulse_data.scene.instantiate() as AreaItem
	add_child_autofree(pulse)
	pulse.setup(pulse_data, owner, context)
	pulse.activate(InputFrame.zero())
	pulse.tick(0.3)
	assert_false(bool(target.call("has_shield")))
	assert_eq(target.get_hit_state(), -1)
	assert_almost_eq(target.get_speed(), 0.0, EPSILON)
	assert_almost_eq(target.get_lateral_speed(), 0.0, EPSILON)


func test_unshielded_pulse_blast_scales_speed_and_applies_knockback() -> void:
	var owner: KartController = _make_kart("Owner")
	var target: KartController = _make_kart("Target")
	owner.global_position = Vector3.ZERO
	target.global_position = Vector3(1.0, 0.0, 0.0)
	target.apply_impulse_arcade(Vector3(0.0, 0.0, -20.0), 0.0)
	var pulse_data: ItemData = preload("res://data/items/pulse_blast.tres")
	var pulse: AreaItem = pulse_data.scene.instantiate() as AreaItem
	add_child_autofree(pulse)
	pulse.setup(pulse_data, owner, _make_context([owner, target]))
	pulse.activate(InputFrame.zero())
	pulse.tick(0.3)
	assert_eq(target.get_hit_state(), HitReactor.HitType.BUMP)
	assert_almost_eq(target.get_speed(), 20.0 * pulse_data.power, EPSILON)
	assert_almost_eq(target.get_lateral_speed(), pulse_data.knockback_speed, EPSILON)


func test_kart_vs_kart_bump_still_bypasses_shield() -> void:
	var target: KartController = _make_kart("Target")
	var context: ItemContext = _make_context([target])
	var shield: ShieldItem = (preload("res://data/items/aegis_bubble.tres").scene.instantiate() as ShieldItem)
	add_child_autofree(shield)
	shield.setup(preload("res://data/items/aegis_bubble.tres"), target, context)
	shield.activate(InputFrame.zero())
	assert_true(target.apply_hit(HitReactor.HitType.BUMP, null))
	assert_true(bool(target.call("has_shield")))
	assert_eq(target.get_hit_state(), HitReactor.HitType.BUMP)


func test_storm_warning_can_be_countered_before_strike() -> void:
	var leader: KartController = _make_kart("Leader")
	var owner: KartController = _make_kart("Owner")
	var storm: LeaderStrikeItem = preload("res://data/items/storm_beacon.tres").scene.instantiate() as LeaderStrikeItem
	add_child_autofree(storm)
	watch_signals(EventBus)
	storm.setup(preload("res://data/items/storm_beacon.tres"), owner, _make_context([leader, owner]))
	storm.activate(InputFrame.zero())
	assert_signal_emitted_with_parameters(EventBus, "threat_warning", [leader, &"storm_beacon", 3.0])
	storm.grant_immunity(leader)
	storm.tick(3.0)
	assert_eq(leader.get_hit_state(), -1)


func test_race_item_manager_registers_four_karts_and_emits_use_and_hit() -> void:
	var track_data: TrackData = TrackData.new()
	track_data.id = &"test_loop"
	track_data.scene = TEST_TRACK
	var config: RaceConfig = RaceConfig.new()
	config.track = track_data
	config.laps = 1
	config.kart_count = 4
	config.player_slot = -1
	config.player_kart = preload("res://data/karts/medium.tres")
	config.ai_difficulty = preload("res://data/ai/normal.tres")
	config.items_enabled = true
	config.seed = 7
	var race: RaceManager = RACE_SCENE.instantiate() as RaceManager
	race.configure(config)
	add_child_autofree(race)
	var manager: ItemManager = race.get_node("ItemManager") as ItemManager
	var karts: Array[KartController] = race.get_karts()
	watch_signals(EventBus)
	assert_eq(karts.size(), 4)
	assert_true(manager.give_item(karts[3], preload("res://data/items/pulse_blast.tres")))
	assert_true(manager.use_item(karts[3], InputFrame.zero()))
	manager._physics_process(0.3)
	assert_signal_emit_count(EventBus, "item_used", 1)
	assert_gt(get_signal_emit_count(EventBus, "item_hit"), 0)


func _make_kart(kart_name: String) -> KartController:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	kart.name = kart_name
	add_child_autofree(kart)
	return kart


func _make_context(karts: Array[KartController]) -> ItemContext:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var context: ItemContext = ItemContext.new()
	context.configure(karts, null, null, rng, null)
	return context
