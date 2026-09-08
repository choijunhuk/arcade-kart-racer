class_name RaceSimMetrics
extends RefCounted

const ITEM_IDS: Array[String] = [
	"rocket_dart", "hunter_drone", "spike_mine", "nitro_can",
	"aegis_bubble", "pulse_blast", "storm_beacon",
]
const MIN_CATCH_UP_DELTA: float = 0.4
const METRIC_EPSILON: float = 0.000001
const MAX_LEADER_HITS: float = 3.0
const MIN_FINISH_SPREAD: float = 5.0
const MAX_FINISH_SPREAD: float = 25.0

## Mean per-lap finish time across every finisher in every race (spec §13.8:
## this is what separates Easy/Normal/Hard when `tools/run_sim.sh` is run
## once per difficulty and the three summaries are compared).
static func summarize(race_outputs: Array[Dictionary], laps: int) -> Dictionary:
	var lap_time_samples: Array[float] = []
	var used_totals: Dictionary[String, int] = {}
	var hit_totals: Dictionary[String, int] = {}
	for item_id: String in ITEM_IDS:
		used_totals[item_id] = 0
		hit_totals[item_id] = 0
	var spreads: Array[float] = []
	var class_wins: Dictionary[String, int] = {"light": 0, "medium": 0, "heavy": 0}
	var rank_one_hit_total: int = 0
	var rank_eight_gain_total: float = 0.0
	var lap1_rank8_gain_total: float = 0.0
	for race_output: Dictionary in race_outputs:
		var spread: float = finish_spread(race_output)
		if spread >= 0.0:
			spreads.append(spread)
		var winner: String = str(race_output.get("winning_class", ""))
		if class_wins.has(winner):
			class_wins[winner] += 1
		for value: Variant in (race_output["times"] as Dictionary).values():
			if float(value) >= 0.0:
				lap_time_samples.append(float(value) / float(laps))
		for item_id: String in ITEM_IDS:
			used_totals[item_id] += int((race_output.get("items_used", {}) as Dictionary).get(item_id, 0))
			hit_totals[item_id] += int((race_output.get("item_hits", {}) as Dictionary).get(item_id, 0))
		rank_one_hit_total += int(race_output.get("rank_one_hits", 0))
		rank_eight_gain_total += float(race_output.get("rank_eight_gain", 0.0))
		lap1_rank8_gain_total += float(race_output.get("lap1_rank8_gain", 0.0))
	var mean_lap_time: float = 0.0
	if not lap_time_samples.is_empty():
		var total: float = 0.0
		for sample: float in lap_time_samples:
			total += sample
		mean_lap_time = total / float(lap_time_samples.size())
	var hit_rates: Dictionary[String, float] = {}
	for item_id: String in ITEM_IDS:
		var used: int = used_totals[item_id]
		hit_rates[item_id] = float(hit_totals[item_id]) / float(used) if used > 0 else 0.0
	var race_count: float = float(race_outputs.size())
	return {
		"mean_lap_time_seconds": mean_lap_time,
		"finish_spread_seconds": spreads,
		"mean_finish_spread_seconds": mean(spreads),
		"class_wins": class_wins,
		"finisher_samples": lap_time_samples.size(),
		"items_used": used_totals,
		"item_hits": hit_totals,
		"hit_rate_by_item": hit_rates,
		"average_rank_one_hits_per_race": float(rank_one_hit_total) / race_count if race_count > 0.0 else 0.0,
		## Grid-slot-8 kart's rank gain. Mostly regression to the mean (a
		## back-of-grid kart tends to finish ahead of its start slot even
		## with items off) — kept for reference but no longer gates.
		"mean_rank_eight_gain": rank_eight_gain_total / race_count if race_count > 0.0 else 0.0,
		## Rank gain for whichever kart was actually in last place (by race
		## position, not grid slot) at the end of lap 1. The paired items-off
		## control is subtracted before applying the balance threshold.
		"mean_lap1_rank8_gain": lap1_rank8_gain_total / race_count if race_count > 0.0 else 0.0,
	}

## Returns the whole-race first-to-last gap specified by section 13.8, or -1 for DNF.
static func finish_spread(race_output: Dictionary) -> float:
	var times: Dictionary = race_output.get("times", {})
	if times.is_empty():
		return -1.0
	var first: float = INF
	var last: float = 0.0
	for value: Variant in times.values():
		if float(value) < 0.0:
			return -1.0
		first = minf(first, float(value))
		last = maxf(last, float(value))
	return last - first


## Averages complete samples without conflating a race gap with its per-lap mean.
static func mean(samples: Array[float]) -> float:
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	return total / float(samples.size()) if not samples.is_empty() else 0.0


## Adds the measured same-seed items-off control; no historical constants substitute for it.
static func with_control(summary: Dictionary, control: Dictionary) -> Dictionary:
	var paired: Dictionary = summary.duplicate(true)
	paired["control_mean_lap1_rank8_gain"] = control["mean_lap1_rank8_gain"]
	paired["lap1_rank8_gain_delta"] = float(summary["mean_lap1_rank8_gain"]) - float(control["mean_lap1_rank8_gain"])
	return paired


## Requires a finite measured improvement and preserves the leader-hit ceiling.
static func items_balance_pass(summary: Dictionary) -> bool:
	var gain: float = float(summary.get("lap1_rank8_gain_delta", -INF))
	var hits: float = float(summary.get("average_rank_one_hits_per_race", INF))
	return is_finite(gain) and is_finite(hits) and gain + METRIC_EPSILON >= MIN_CATCH_UP_DELTA and hits >= 0.0 and hits <= MAX_LEADER_HITS


## All three weight classes must win in the mixed roster sample.
static func classes_balance_pass(summary: Dictionary) -> bool:
	var wins: Dictionary = summary.get("class_wins", {})
	return int(wins.get("light", 0)) > 0 and int(wins.get("medium", 0)) > 0 and int(wins.get("heavy", 0)) > 0
