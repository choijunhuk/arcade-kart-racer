extends GutTest

## Regression for finding 1 (protocol version gate): every `@rpc` method's
## argument count is part of the join handshake's implicit wire contract.
## `net_handshake.gd` admits/rejects a joiner by an EXACT `config/version`
## string match, so changing an RPC's parameter list without also bumping
## `config/version` (project.godot) admits a stale-build peer, and every
## call to the changed RPC then fails with CALL_ERROR_TOO_MANY_ARGUMENTS —
## the stale peer never gets a roster or loads the race, and since
## `_mark_loaded` waits for `loaded.size() == players.size()`, the whole
## session hangs at LOADING.
##
## NEXT DEV: if this test fails because you changed an `@rpc` method's
## parameter list, bump `config/version` in project.godot IN THE SAME COMMIT,
## then update EXPECTED_ARITY below to match the new signature.
const NET_SESSION_SCRIPT: String = "res://net/net_session.gd"

const EXPECTED_ARITY: Dictionary = {
	"_admitted": 1,
	"_selection": 3,
	"_lobby": 5,
	"_return_to_lobby": 1,
	"_prepare_race": 6,
	"_handshake": 2,
	"_race_loaded": 0,
	"_begin_race": 0,
	"_receive_input": 1,
	"_snapshot": 1,
	"_event": 2,
	"_ping": 1,
	"_pong": 2,
	"_player_left": 1,
	"_session_ended": 1,
	"_test_report": 1,
}


func test_net_session_rpc_methods_match_the_arity_snapshot() -> void:
	var script: GDScript = load(NET_SESSION_SCRIPT) as GDScript
	var rpc_methods: Dictionary = script.get_rpc_config()
	assert_eq(rpc_methods.size(), EXPECTED_ARITY.size(),
		"An @rpc method was added or removed in net_session.gd; update EXPECTED_ARITY here (and bump project.godot config/version if it changes the wire protocol).")
	for method_name: String in EXPECTED_ARITY:
		assert_true(rpc_methods.has(method_name), "%s is no longer an @rpc method" % method_name)
		assert_eq(_argument_count(script, method_name), int(EXPECTED_ARITY[method_name]),
			"%s's argument count changed — bump project.godot config/version in the same commit and update EXPECTED_ARITY here." % method_name)


func _argument_count(script: GDScript, method_name: StringName) -> int:
	for method: Dictionary in script.get_script_method_list():
		if StringName(str(method.get("name", ""))) == method_name:
			return (method.get("args", []) as Array).size()
	return -1
