extends GutTest

## Backlog item 5: NetRateLimiter.allow() now takes an optional per-call
## `cost` (default 1.0, so every existing caller — _selection_limiter,
## _ping_limiter — is unaffected), and NetSession._receive_input() charges
## one token per batched input frame instead of one per RPC call, so a full
## INPUT_BATCH_TICKS-sized batch cannot cost the same single token a lone
## frame would. New file (test_net_internet.gd is already at the 400-line
## budget) rather than added there.

func test_rate_limiter_allow_charges_a_custom_cost_and_rejects_when_insufficient() -> void:
	var limiter: NetRateLimiter = NetRateLimiter.new(5.0, 0.0)
	assert_true(limiter.allow(1, 0.0, 3.0), "3 of 5 tokens must be available")
	assert_true(limiter.allow(1, 0.0, 2.0), "the remaining 2 tokens must still cover an exact-cost call")
	assert_false(limiter.allow(1, 0.0, 1.0), "no tokens left for a further call at the same instant")

## Server-side NetSession with a scriptable RPC sender id, mirroring
## test_net_internet.gd's own GateSession but kept local to this file.
class CostSession extends NetSession:
	var sender_id: int = 0

	func _sender() -> int:
		return sender_id

	func input_from(id: int, data: Dictionary) -> void:
		sender_id = id
		_receive_input(data)

func test_receive_input_charges_one_token_per_batched_frame_not_one_per_rpc_call() -> void:
	var session: CostSession = CostSession.new()
	add_child_autofree(session)
	session._gate.track(21, 0.0)
	session._gate.verify(21) # Verified without a roster row: only the rate-limit cost matters here.
	session.running = true
	session.race = NetRace.new()
	autofree(session.race)
	session.race.session = session # Bare, unconfigured NetRace: only session.players (kept empty) is read.
	session._input_limiter = NetRateLimiter.new(5.0, 0.0)
	var frame: Dictionary = InputFrame.new().to_dict()
	session.input_from(21, {"frames": [frame, frame, frame]}) # Costs 3 of 5 tokens.
	assert_almost_eq(float(session._input_limiter._tokens.get(21, -1.0)), 2.0, 0.001, "a 3-frame batch must cost 3 tokens, not 1")
	session.input_from(21, {"frames": [frame, frame, frame]}) # Only 2 tokens left.
	assert_almost_eq(float(session._input_limiter._tokens.get(21, -1.0)), 2.0, 0.001, "a rejected batch must not consume any tokens")
