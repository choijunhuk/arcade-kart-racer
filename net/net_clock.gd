class_name NetClock
extends RefCounted

## Network-only monotonic clock estimator; gameplay remains fixed-tick driven.
var offset_seconds: float = 0.0
var rtt_seconds: float = 0.0
var initialized: bool = false
const SAMPLE_WEIGHT: float = 0.2

## Estimates server time at receipt as its echoed send time plus RTT/2.
func observe(sent: float, server: float, received: float) -> void:
	if received < sent:
		return
	var rtt: float = received - sent
	var offset: float = server + rtt * 0.5 - received
	offset_seconds = lerpf(offset_seconds, offset, SAMPLE_WEIGHT) if initialized else offset
	rtt_seconds = lerpf(rtt_seconds, rtt, SAMPLE_WEIGHT) if initialized else rtt
	initialized = true

## Converts a local monotonic timestamp to estimated server time.
func server_time(local: float) -> float:
	return local + offset_seconds
