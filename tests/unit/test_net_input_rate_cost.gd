extends GutTest

## Backlog item 5, then review RED-2 (rule changed twice — see each test's own
## note): NetRateLimiter.allow() takes an optional per-call `cost` (default
## 1.0, so _selection_limiter/_ping_limiter are unaffected). The ORIGINAL
## rule charged one token per batched input frame; RED-2 found that still
## over-throttled honest traffic (INPUT_BATCH_TICKS frames/call at TICK_RATE
## could burn tokens faster than any sane bucket refills, even though most of
## a real client's batch is just a resend of ticks already accounted for
## after ordinary packet loss). The rule is now: only frames whose tick is
## NEWER than the sender's last-charged tick cost anything
## (NetSessionTransport.input_batch_cost()), and the bucket itself is sized
## from NetTuning (capacity 3*TICK_RATE, refill 1.5*TICK_RATE) instead of the
## generic NetRateLimiter default. New file (test_net_internet.gd is already
## at the 400-line budget) rather than added there.

func _frame(tick: int) -> Dictionary:
	return {"tick": tick}

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

## RED-2: a resend of ticks already charged (routine after any packet loss —
## a real client's batch is mostly resend) must be free; only genuinely new
## ticks cost tokens. Exercised through the real `_receive_input` RPC path
## end to end, not just the pure helper, to prove the wiring itself.
func test_receive_input_charges_only_new_ticks_not_resends() -> void:
	var session: CostSession = CostSession.new()
	add_child_autofree(session)
	session._gate.track(21, 0.0)
	session._gate.verify(21) # Verified without a roster row: only the rate-limit cost matters here.
	session.running = true
	session.race = NetRace.new()
	autofree(session.race)
	session.race.session = session # Bare, unconfigured NetRace: only session.players (kept empty) is read.
	session._input_limiter = NetRateLimiter.new(10.0, 0.0)
	session.input_from(21, {"frames": [_frame(1), _frame(2), _frame(3)]}) # 3 new ticks.
	assert_almost_eq(float(session._input_limiter._tokens.get(21, -1.0)), 7.0, 0.001, "3 genuinely new ticks must cost 3 tokens")
	session.input_from(21, {"frames": [_frame(2), _frame(3), _frame(4)]}) # 2 and 3 are resends; only 4 is new.
	assert_almost_eq(float(session._input_limiter._tokens.get(21, -1.0)), 6.0, 0.001, "resending already-charged ticks must be free; only the new tick 4 costs a token")

## RED-2: sized so a fully honest client — one new tick per physics tick at
## TICK_RATE, batched with its own last INPUT_BATCH_TICKS ticks each call
## (the real _client_step resend window) — is never rejected, including
## across a sustained 5s run, not just a brief burst.
func test_steady_state_60hz_batches_of_three_never_reject() -> void:
	var limiter: NetRateLimiter = NetRateLimiter.new(3.0 * NetTuning.TICK_RATE, 1.5 * NetTuning.TICK_RATE)
	var transport: NetSessionTransport = NetSessionTransport.new()
	var session: NetSession = NetSession.new()
	autofree(session)
	transport.attach(session)
	var rejections: int = 0
	for i: int in range(5 * NetTuning.TICK_RATE): # 5 seconds at 60 Hz.
		var tick: int = i + 1
		var frames: Array = []
		for t: int in range(maxi(1, tick - 2), tick + 1):
			frames.append(_frame(t))
		var now: float = float(i) * NetTuning.STEP
		if not limiter.allow(21, now, transport.input_batch_cost(21, frames)):
			rejections += 1
	assert_eq(rejections, 0, "steady-state honest traffic (up to 3 ticks/call at 60Hz) must never be rejected")

## RED-2: a flood of ticks that are each genuinely new (never a resend) at
## 10x the honest call rate must still be bounded — the fix must not have
## thrown away rate limiting altogether.
func test_flood_of_distinct_ticks_at_ten_times_rate_is_rejected() -> void:
	var limiter: NetRateLimiter = NetRateLimiter.new(3.0 * NetTuning.TICK_RATE, 1.5 * NetTuning.TICK_RATE)
	var transport: NetSessionTransport = NetSessionTransport.new()
	var session: NetSession = NetSession.new()
	autofree(session)
	transport.attach(session)
	var rejections: int = 0
	var flood_rate: float = 10.0 * NetTuning.TICK_RATE
	for i: int in range(int(flood_rate) * 2): # 2 seconds at 10x the normal call rate.
		var now: float = float(i) / flood_rate
		if not limiter.allow(21, now, transport.input_batch_cost(21, [_frame(i + 1)])):
			rejections += 1
	assert_gt(rejections, 0, "a flood of distinct new ticks at 10x the honest rate must eventually be rejected")
