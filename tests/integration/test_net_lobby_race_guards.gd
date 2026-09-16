extends GutTest

## Phase 18i items 4 and 5. New file rather than added to test_net_lobby.gd
## (already at the 400-line budget) or test_net_lobby_broadcast.gd (a
## different topic — broadcast coalescing, not settings validation/guards).

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

## Item 5: a stray/late `_lobby` broadcast reaching a client that is already
## racing must be ignored — `apply_lobby()` -> `replace()` on `players` would
## otherwise desync that client's roster/kart indices mid-race. Lobby return
## is `_return_to_lobby`'s job, not `_lobby`'s. A real (never actually
## connecting) client `ENetMultiplayerPeer` makes `is_server()` read false
## without a socket handshake — the same technique test_net_race_ux.gd uses.
func test_lobby_broadcast_is_ignored_by_a_racing_client() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	client_peer.create_client("127.0.0.1", 34598)
	get_tree().get_multiplayer().multiplayer_peer = client_peer
	session.race = NetRace.new()
	add_child_autofree(session.race)
	session.players = [{"peer": 1, "ready": true}]
	assert_false(session.multiplayer.is_server(), "test setup must simulate a non-host, currently-racing peer")
	session._lobby([{"peer": 1, "ready": false}], 5, 2, "track_03_glacier_crown", "hard")
	assert_eq(session.players.size(), 1, "a stray lobby broadcast must not replace the roster mid-race")
	assert_true(bool(session.players[0]["ready"]), "the racing client's own roster row must be untouched")
	client_peer.close()
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
