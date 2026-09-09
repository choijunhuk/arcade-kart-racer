class_name NetTuning
extends RefCounted

const PORT: int = 24565
const MAX_PLAYERS: int = 4
const TICK_RATE: int = 60
const STEP: float = 1.0 / TICK_RATE
const INPUT_DELAY: int = 2
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
