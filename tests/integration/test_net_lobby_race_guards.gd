extends GutTest

## Phase 18i item 4. New file rather than added to test_net_lobby.gd (already
## at the 400-line budget) or test_net_lobby_broadcast.gd (a different topic
## — broadcast coalescing, not settings validation).

## `apply_race_settings` is the single clamp point for laps/bots (review
## finding 3) and must normalize track/difficulty the same way — an id
## absent from the catalog (a stale build, or a hostile `_lobby`/
## `_prepare_race` payload) must fall back to the real default id, identically
## on host and client since both run this one function.
func test_apply_race_settings_normalizes_an_unknown_track_id_to_the_default() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session._roster.apply_race_settings(3, 2, "not_a_real_track", "hard")
	assert_eq(session.track_id, "track_01_ridgeline_circuit", "an unknown track id must normalize to the default track's real id")
	assert_eq(session.difficulty_id, "hard", "a known difficulty id must pass through unchanged")

func test_apply_race_settings_normalizes_an_unknown_difficulty_id_to_the_default() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session._roster.apply_race_settings(3, 2, "track_02_lumen_underpass", "not_a_real_difficulty")
	assert_eq(session.track_id, "track_02_lumen_underpass", "a known track id must pass through unchanged")
	assert_eq(session.difficulty_id, "normal", "an unknown difficulty id must normalize to the default difficulty's real id")
