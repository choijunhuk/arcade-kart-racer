extends GutTest

## Regression for finding 1 (protocol version gate): every `@rpc` method's
## full wire contract — argument list, rpc mode, transfer mode and channel —
## is part of the join handshake's implicit protocol, gated by an EXACT
## `config/version` string match (net_handshake.gd, read via
## `ProjectSettings.get_setting("application/config/version", "")`).
## Changing any one of those without bumping `config/version` (project.godot)
## admits a stale-build peer whose calls to the changed RPC fail silently or
## loudly (CALL_ERROR_TOO_MANY_ARGUMENTS, a mode mismatch, a reliable packet
## sent unreliable) — and since `_mark_loaded` waits for
## `loaded.size() == players.size()`, the whole session hangs at LOADING.
##
## NEXT DEV: if this test fails because you changed an `@rpc` method's
## signature, rpc mode, transfer mode, or channel, bump `config/version` in
## project.godot IN THE SAME COMMIT, then update EXPECTED_RPC_CONFIG (and
## EXPECTED_CONFIG_VERSION, so this snapshot tracks the new version) below.
const NET_SESSION_SCRIPT: String = "res://net/net_session.gd"

## Pinned to project.godot's current value so a protocol change without a
## version bump fails this test, not only a silent CALL_ERROR at runtime.
const EXPECTED_CONFIG_VERSION: String = "0.7.0"

## method_name -> {arity, rpc_mode, transfer_mode, channel (only when != 0)}.
## rpc_mode/transfer_mode/channel mirror `Script.get_rpc_config()`'s own
## per-method dictionary shape (rpc_mode: RPC_MODE_ANY_PEER/AUTHORITY;
## transfer_mode: TRANSFER_MODE_RELIABLE/UNRELIABLE_ORDERED).
const EXPECTED_RPC_CONFIG: Dictionary = {
	"_admitted": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_selection": {"arity": 3, "rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_lobby": {"arity": 5, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_return_to_lobby": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_prepare_race": {"arity": 6, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_handshake": {"arity": 2, "rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_challenge": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_race_loaded": {"arity": 0, "rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_begin_race": {"arity": 0, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_receive_input": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, "channel": 1},
	"_snapshot": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, "channel": 2},
	"_event": {"arity": 2, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_ping": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_pong": {"arity": 2, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_player_left": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_session_ended": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
	"_test_report": {"arity": 1, "rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE},
}


func test_net_session_rpc_methods_match_the_full_config_snapshot() -> void:
	var script: GDScript = load(NET_SESSION_SCRIPT) as GDScript
	var rpc_methods: Dictionary = script.get_rpc_config()
	assert_eq(rpc_methods.size(), EXPECTED_RPC_CONFIG.size(),
		"An @rpc method was added or removed in net_session.gd; update EXPECTED_RPC_CONFIG here (and bump project.godot config/version if it changes the wire protocol).")
	for method_name: String in EXPECTED_RPC_CONFIG:
		var expected: Dictionary = EXPECTED_RPC_CONFIG[method_name]
		assert_true(rpc_methods.has(method_name), "%s is no longer an @rpc method" % method_name)
		var actual: Dictionary = rpc_methods.get(method_name, {}) as Dictionary
		assert_eq(_argument_count(script, method_name), int(expected["arity"]),
			"%s's argument count changed — bump config/version and update EXPECTED_RPC_CONFIG." % method_name)
		assert_eq(int(actual.get("rpc_mode", -1)), int(expected["rpc_mode"]),
			"%s's rpc mode (any_peer/authority) changed — bump config/version and update EXPECTED_RPC_CONFIG." % method_name)
		assert_eq(int(actual.get("transfer_mode", -1)), int(expected["transfer_mode"]),
			"%s's transfer mode (reliable/unreliable_ordered) changed — bump config/version and update EXPECTED_RPC_CONFIG." % method_name)
		assert_eq(int(actual.get("channel", 0)), int(expected.get("channel", 0)),
			"%s's RPC channel changed — bump config/version and update EXPECTED_RPC_CONFIG." % method_name)


## Ties the whole snapshot above to the exact string the handshake gates on,
## so a protocol change lands here even if every per-method assertion above
## somehow still matched (e.g. a version bump alone, with no other change).
func test_config_version_matches_the_pinned_protocol_snapshot() -> void:
	var actual_version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	assert_eq(actual_version, EXPECTED_CONFIG_VERSION,
		"project.godot's config/version changed. If net_session.gd's RPC wire protocol changed too, that's correct — update EXPECTED_CONFIG_VERSION (and EXPECTED_RPC_CONFIG if needed) here to match. If nothing in the protocol changed, this version bump was unnecessary.")


func _argument_count(script: GDScript, method_name: StringName) -> int:
	for method: Dictionary in script.get_script_method_list():
		if StringName(str(method.get("name", ""))) == method_name:
			return (method.get("args", []) as Array).size()
	return -1
