class_name NetJoinCode
extends RefCounted

## Short, human-typeable Crockford base32 code encoding an IPv4 external
## address and UDP port (spec: 8-10 chars, checksum, decode -> ip/port).
## 4 IP bytes + 2 port bytes pack into 48 payload bits plus a 2-bit checksum,
## fitting exactly 10 symbols with zero padding waste.
const ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const CODE_LENGTH: int = 10
const PAYLOAD_BYTES: int = 6
const CHECKSUM_BITS: int = 2
const CHECKSUM_MASK: int = (1 << CHECKSUM_BITS) - 1

## Encodes `ip` ("a.b.c.d") and `port` (0-65535) into a 10-character code,
## or "" when either input is out of range.
static func encode(ip: String, port: int) -> String:
	var bytes: PackedByteArray = _ip_port_bytes(ip, port)
	if bytes.is_empty():
		return ""
	var payload: int = 0
	for value: int in bytes:
		payload = (payload << 8) | value
	var bits: int = (payload << CHECKSUM_BITS) | _checksum(bytes)
	var code: String = ""
	for index: int in range(CODE_LENGTH):
		var shift: int = (CODE_LENGTH - 1 - index) * 5
		code += ALPHABET[(bits >> shift) & 0x1F]
	return code

## Decodes a code produced by `encode`, returning {"ip": String, "port": int}
## or an empty Dictionary when the code is malformed or its checksum fails.
static func decode(code: String) -> Dictionary:
	var normalized: String = code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if normalized.length() != CODE_LENGTH:
		return {}
	var bits: int = 0
	for symbol: String in normalized:
		var index: int = ALPHABET.find(symbol)
		if index < 0:
			return {}
		bits = (bits << 5) | index
	var checksum: int = bits & CHECKSUM_MASK
	var payload: int = bits >> CHECKSUM_BITS
	var bytes: PackedByteArray = PackedByteArray()
	for index: int in range(PAYLOAD_BYTES):
		var shift: int = (PAYLOAD_BYTES - 1 - index) * 8
		bytes.append((payload >> shift) & 0xFF)
	if _checksum(bytes) != checksum:
		return {}
	return {"ip": "%d.%d.%d.%d" % [bytes[0], bytes[1], bytes[2], bytes[3]],
		"port": (bytes[4] << 8) | bytes[5]}

## Returns true when `text` looks like a join code rather than a raw ip[:port].
static func looks_like_code(text: String) -> bool:
	var normalized: String = text.strip_edges().to_upper().replace("-", "")
	if normalized.length() != CODE_LENGTH:
		return false
	for symbol: String in normalized:
		if ALPHABET.find(symbol) < 0:
			return false
	return true

static func _ip_port_bytes(ip: String, port: int) -> PackedByteArray:
	var octets: PackedStringArray = ip.split(".")
	if octets.size() != 4 or port < 0 or port > 65535:
		return PackedByteArray()
	var bytes: PackedByteArray = PackedByteArray()
	for octet: String in octets:
		if not octet.is_valid_int():
			return PackedByteArray()
		var value: int = int(octet)
		if value < 0 or value > 255:
			return PackedByteArray()
		bytes.append(value)
	bytes.append((port >> 8) & 0xFF)
	bytes.append(port & 0xFF)
	return bytes

static func _checksum(bytes: PackedByteArray) -> int:
	var sum: int = 0
	for value: int in bytes:
		sum += value
	return sum & CHECKSUM_MASK
