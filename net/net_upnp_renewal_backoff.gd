class_name NetUpnpRenewalBackoff
extends RefCounted

## Renewal retry back-off after a failed renewal (review finding 1): a naive
## retry-on-the-next-`_process`-tick used to cancel out against
## `NetUpnp.is_renewal_due()`'s own `RENEW_MARGIN_SECONDS` margin, because
## `_finish_renewal()` re-armed the lease's own expiry at
## `_now() + RENEW_MARGIN_SECONDS` while `is_renewal_due()` fires at
## `expires_at - RENEW_MARGIN_SECONDS`. This back-off is independent of lease
## expiry instead, so a router that keeps rejecting renewal never gets
## back-to-back SSDP + AddPortMapping requests for the rest of the session.
##
## Split out of `net_upnp.gd` itself to keep it under the project's 400-line
## rule — pure timing state and math, no threading, no UPNP calls, trivially
## unit-testable on its own.

const INITIAL_SECONDS: float = 60.0
const MAX_SECONDS: float = 300.0

## `NetUpnp._now()` timestamp before which the next renewal attempt must not
## start. -1.0 means no back-off is in effect (never failed yet, or the last
## attempt succeeded).
var next_attempt_at: float = -1.0
var _retry_seconds: float = INITIAL_SECONDS


## True once `now` has reached `next_attempt_at`, or no back-off is armed.
func is_due(now: float) -> bool:
	return next_attempt_at < 0.0 or now >= next_attempt_at


## A renewal just succeeded: clear the back-off and reset the retry ladder.
func on_success() -> void:
	next_attempt_at = -1.0
	_retry_seconds = INITIAL_SECONDS


## A renewal just failed: arm the back-off, doubling the wait on each
## further consecutive failure (capped at MAX_SECONDS).
func on_failure(now: float) -> void:
	next_attempt_at = now + _retry_seconds
	_retry_seconds = minf(_retry_seconds * 2.0, MAX_SECONDS)


## Same as `on_failure()`, but also `push_warning(message)` — only the first
## time in a back-off run (review item 6): a router that keeps rejecting
## renewal should not spam a warning on every retry, only when the failing
## state is first entered.
func on_failure_warn_once(now: float, message: String) -> void:
	if next_attempt_at < 0.0:
		push_warning(message)
	on_failure(now)
