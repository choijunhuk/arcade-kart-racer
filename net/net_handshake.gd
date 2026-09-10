class_name NetHandshake
extends RefCounted

## Pure join-handshake validation (spec item 6: version check, hashed
## password compare). No networking; NetSession supplies the expected
## values and performs the actual rejection/disconnect side effects, so
## this stays independently unit-testable.

## Returns a human-readable rejection reason, or "" when the peer may join.
## `expected_version`/`expected_password_hash` empty means "don't enforce".
static func reject_reason(
	client_version: String, expected_version: String,
	password_attempt: String, expected_password_hash: String,
) -> String:
	if not expected_version.is_empty() and client_version != expected_version:
		return "Version mismatch: host runs %s" % expected_version
	if not expected_password_hash.is_empty() and password_attempt != expected_password_hash:
		return "Incorrect session password"
	return ""
