class_name NetUpnpAddress
extends RefCounted

## Pure, static IGD-address helpers split out of `net_upnp.gd` for the
## project's 400-line rule: whether the "external" address an IGD reports is
## actually internet-reachable, and the status line shown for anything other
## than a reachable mapping. `NetUpnp` keeps thin static wrappers so every
## caller and test still uses `NetUpnp.is_internet_reachable_address()` /
## `NetUpnp.status_message()` unchanged.


## Human-readable status line for anything other than a successful reachable
## mapping. Distinguishes "mapped but not internet-reachable" (CGNAT/double-
## NAT) from a genuine failure. `external_ip` on "mapped_unreachable" is raw
## SSDP LAN text — never echoed unless it parses as a dotted-quad IPv4.
static func status_message(result: Dictionary, port: int) -> String:
	if String(result.get("status", "")) == "mapped_unreachable":
		var external_ip: String = String(result.get("external_ip", ""))
		var reported: String = external_ip if not parse_ipv4_octets(external_ip).is_empty() else "the address your router reported"
		return (
			"UPnP mapped, but %s is not internet-reachable (likely CGNAT/double-NAT) — use the relay above or forward UDP port %d on your router manually."
			% [reported, port]
		)
	return "UPnP unavailable — forward UDP port %d manually." % port


## Parses `ip` as four 0-255 octets, or empty if not a well-formed dotted-
## quad — malformed/untrusted input fails closed for every caller.
static func parse_ipv4_octets(ip: String) -> Array[int]:
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return []
	var octets: Array[int] = []
	for part: String in parts:
		if not part.is_valid_int():
			return []
		var value: int = int(part)
		if value < 0 or value > 255:
			return []
		octets.append(value)
	return octets


## True when `ip` is a routable, internet-reachable IPv4 address. False for
## every private/CGNAT/link-local/loopback/reserved range an IGD can hand
## back as its own "external" address: 0.0.0.0/8 (down/misconfigured WAN),
## 10/8, 172.16/12, 192.168/16, 100.64/10 (CGNAT), 169.254/16 (link-local),
## 127/8 (loopback), and 224/4 + 240/4 (multicast/reserved, includes
## 255.255.255.255). Malformed input fails closed (not reachable).
static func is_internet_reachable_address(ip: String) -> bool:
	var octets: Array[int] = parse_ipv4_octets(ip)
	if octets.is_empty():
		return false
	if octets[0] == 0:
		return false
	if octets[0] == 10:
		return false
	if octets[0] == 172 and octets[1] >= 16 and octets[1] <= 31:
		return false
	if octets[0] == 192 and octets[1] == 168:
		return false
	if octets[0] == 100 and octets[1] >= 64 and octets[1] <= 127:
		return false
	if octets[0] == 169 and octets[1] == 254:
		return false
	if octets[0] == 127:
		return false
	if octets[0] >= 224:
		return false
	return true
