extends GutTest

## UPnP reachability coverage (split out of test_net_internet.gd for the
## 400-line rule): an IGD behind CGNAT or a double-NAT hands back its own
## private WAN address, so the mapping is real but unreachable from outside.

func test_is_internet_reachable_address_true_for_a_normal_public_address() -> void:
	assert_true(NetUpnp.is_internet_reachable_address("203.0.113.7"))
	assert_true(NetUpnp.is_internet_reachable_address("8.8.8.8"))

func test_is_internet_reachable_address_false_for_class_a_private_range() -> void:
	assert_false(NetUpnp.is_internet_reachable_address("10.0.0.1"))
	assert_false(NetUpnp.is_internet_reachable_address("10.255.255.255"))

func test_is_internet_reachable_address_false_for_class_b_private_range() -> void:
	assert_false(NetUpnp.is_internet_reachable_address("172.16.0.1"))
	assert_false(NetUpnp.is_internet_reachable_address("172.31.255.255"))
	assert_true(NetUpnp.is_internet_reachable_address("172.32.0.1"), "172.32/12 is outside the private range")
	assert_true(NetUpnp.is_internet_reachable_address("172.15.255.255"), "172.15/12 is outside the private range")

func test_is_internet_reachable_address_false_for_class_c_private_range() -> void:
	assert_false(NetUpnp.is_internet_reachable_address("192.168.1.1"))

func test_is_internet_reachable_address_false_for_cgnat_range() -> void:
	assert_false(NetUpnp.is_internet_reachable_address("100.64.0.1"))
	assert_false(NetUpnp.is_internet_reachable_address("100.127.255.255"))
	assert_true(NetUpnp.is_internet_reachable_address("100.63.255.255"), "100.63/10 is outside the CGNAT range")
	assert_true(NetUpnp.is_internet_reachable_address("100.128.0.1"), "100.128/10 is outside the CGNAT range")

func test_is_internet_reachable_address_false_for_link_local_range() -> void:
	assert_false(NetUpnp.is_internet_reachable_address("169.254.1.1"))

func test_is_internet_reachable_address_false_for_loopback_range() -> void:
	assert_false(NetUpnp.is_internet_reachable_address("127.0.0.1"))

func test_is_internet_reachable_address_fails_closed_on_malformed_input() -> void:
	assert_false(NetUpnp.is_internet_reachable_address(""))
	assert_false(NetUpnp.is_internet_reachable_address("not.an.ip.addr"))
	assert_false(NetUpnp.is_internet_reachable_address("1.2.3"))
	assert_false(NetUpnp.is_internet_reachable_address("1.2.3.4.5"))
	assert_false(NetUpnp.is_internet_reachable_address("1.2.3.256"))

## Audit finding 2: the join code UI must not claim success behind CGNAT.
func test_status_message_flags_a_cgnat_mapping_as_not_internet_reachable() -> void:
	var message: String = NetUpnp.status_message({"status": "mapped_unreachable", "external_ip": "100.64.5.5", "port": 24565}, 24565)
	assert_true(message.findn("100.64.5.5") >= 0)
	assert_true(message.findn("not internet-reachable") >= 0)

func test_status_message_keeps_the_plain_unavailable_text_for_a_real_failure() -> void:
	var message: String = NetUpnp.status_message({"status": "no_igd"}, 24565)
	assert_eq(message, "UPnP unavailable — forward UDP port 24565 manually.")

