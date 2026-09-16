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


## Derives this connection's one-time challenge response (spec item 6): binds
## the password hash to the server's freshly issued nonce so a path observer
## who captures one response cannot replay it against a later handshake.
## Empty `password_hash` (no password set) always answers "", preserving
## today's "no password required" meaning regardless of nonce.
static func response(nonce: String, password_hash: String) -> String:
	if password_hash.is_empty():
		return ""
	return (nonce + password_hash).sha256_text()
