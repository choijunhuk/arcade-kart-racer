class_name NetTuning
extends RefCounted

const PORT: int = 24565
const MAX_PLAYERS: int = 4
const TICK_RATE: int = 60
const STEP: float = 1.0 / TICK_RATE
const INPUT_DELAY: int = 2
const INPUT_BATCH_TICKS: int = 3
const SNAPSHOT_INTERVAL: int = 3
const HISTORY_TICKS: int = 240
const INTERPOLATION_SECONDS: float = 0.1
const EXTRAPOLATION_SECONDS: float = 0.05
const CORRECTION_SECONDS: float = 0.1
const SNAP_METERS: float = 3.0
const POSITION_SCALE: float = 100.0
const ANGLE_SCALE: float = 1000.0
const MAX_PACKET_BYTES: int = 65536
const MAX_UNRELIABLE_BYTES: int = 1200
## Reserve RPC command/node/method framing beyond the serialized arguments.
const RPC_OVERHEAD_BYTES: int = 64
const MAX_PROJECTILES: int = 64
const CLOCK_INTERVAL: int = 30
const CHANNEL_COUNT: int = 3
const RACE_PROCESS_PRIORITY: int = 100
## Widened ENet per-peer ack timeout (`NetTuning.widen_peer_timeout`, applied
## from `net_session.gd`), re-landed after an earlier PR's squash silently
## reverted it. Loading race.tscn -- and, on first run, compiling shaders --
## can block the main thread for ~10s, during which ENet is never serviced;
## ENet disconnects a peer once its earliest unacked reliable command has sat
## past `earliestTimeout`, measured against the per-peer `timeout_min`/
## `timeout_max` window below (not `packetThrottle`, which only scales send
## rate/resend pacing and never itself disconnects). ENet's own default
## timeout_min (5000ms) trips well inside that ~10s stall and the host drops
## the peer before the race even starts. timeout_min=12000ms leaves >2s of
## margin over that ~10s worst case; timeout_max=20000ms still reaps a
## genuinely dead peer (crashed process, unplugged cable) in well under the
## ENet default of 30s rather than lingering. timeout_limit keeps ENet's
## default backoff step count (32).
##
## Cost: this also widens the window for a peer that goes silent AFTER
## admission (not just during the one-time race-load stall) — the host now
## takes 12-20s (instead of ENet's default ~5s) to notice and drop it, during
## which that peer's roster row blocks the all-loaded START gate (the host's
## `retry_start()` is the manual escape), and a client takes the same
## 12-20s to notice a crashed/unplugged host instead of ~5s.
const PEER_TIMEOUT_LIMIT: int = 32
const PEER_TIMEOUT_MIN_MS: int = 12000
const PEER_TIMEOUT_MAX_MS: int = 20000

## Applies the widened timeout to one ENet connection; a no-op if `multiplayer_peer`
## or the peer at `id` doesn't exist yet. See the constants above for the values.
static func widen_peer_timeout(multiplayer_peer: ENetMultiplayerPeer, id: int) -> void:
	if multiplayer_peer == null:
		return
	var enet_peer: ENetPacketPeer = multiplayer_peer.get_peer(id)
	if enet_peer != null:
		enet_peer.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)

## True when an unreliable RPC's serialized arguments still fit one datagram
## once command/node/method framing is reserved. Otherwise pushes an error and
## returns false so the caller drops the packet instead of fragmenting it.
static func fits_unreliable(method: StringName, args: Array) -> bool:
	var bytes: int = var_to_bytes(args).size() + RPC_OVERHEAD_BYTES
	if bytes <= MAX_UNRELIABLE_BYTES:
		return true
	push_error("Unreliable RPC %s exceeds %d bytes (%d including framing reserve); not sent" % [method, MAX_UNRELIABLE_BYTES, bytes])
	return false
