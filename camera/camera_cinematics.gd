class_name CameraCinematics
extends RefCounted

## Presentation-only camera moves owned by one RaceCamera (19-D item 2): the
## pre-countdown grid flyover and the finish beat + orbit. Pure pose math and a
## clock advanced from `_process`; it never touches gameplay or time scale. The
## finish "slow-mo" is a camera beat (hold + FOV punch-in), not Engine.time_scale,
## so online races stay deterministic.

enum Mode { NONE, INTRO, FINISH }

## Intro: sweep from high in front of the grid around to the chase pose.
const INTRO_START_ANGLE: float = 0.6
const INTRO_START_RADIUS: float = 30.0
const INTRO_START_HEIGHT: float = 14.0
## Finish: hold the camera still for the beat, then blend into an orbit.
const FINISH_BEAT_SECONDS: float = 0.5
const FINISH_BEAT_FOV_DROP: float = 14.0
const FINISH_BLEND_SECONDS: float = 1.2
const FINISH_ORBIT_RADIUS: float = 6.5
const FINISH_ORBIT_HEIGHT: float = 2.2
const FINISH_ORBIT_SPEED: float = 0.45

var mode: Mode = Mode.NONE
var elapsed: float = 0.0
var duration: float = 0.0
var _hold_position: Vector3 = Vector3.ZERO


func start_intro(seconds: float) -> void:
	mode = Mode.INTRO
	elapsed = 0.0
	duration = maxf(seconds, 0.01)


func start_finish(camera_position: Vector3) -> void:
	mode = Mode.FINISH
	elapsed = 0.0
	duration = 0.0
	_hold_position = camera_position


func stop() -> void:
	mode = Mode.NONE
	elapsed = 0.0


func is_active() -> bool:
	return mode != Mode.NONE


func step(delta: float) -> void:
	elapsed += maxf(delta, 0.0)


## Camera position for the current mode around a kart pose.
func pose(kart_position: Vector3, kart_forward: Vector3, chase_distance: float, chase_height: float) -> Vector3:
	if mode == Mode.INTRO:
		return intro_pose(kart_position, kart_forward, elapsed / duration, chase_distance, chase_height)
	return finish_pose(kart_position, kart_forward, elapsed, _hold_position)


## FOV offset (degrees) layered over the chase FOV model.
func fov_offset() -> float:
	if mode != Mode.FINISH:
		return 0.0
	if elapsed <= FINISH_BEAT_SECONDS:
		return -FINISH_BEAT_FOV_DROP * smoothstep(0.0, FINISH_BEAT_SECONDS, elapsed)
	return -FINISH_BEAT_FOV_DROP * (1.0 - smoothstep(0.0, FINISH_BLEND_SECONDS, elapsed - FINISH_BEAT_SECONDS))


## `t` 0..1: front-high reveal of the grid swinging round to the chase pose.
static func intro_pose(
	kart_position: Vector3, kart_forward: Vector3, t: float, chase_distance: float, chase_height: float,
) -> Vector3:
	var weight: float = smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var angle: float = lerpf(INTRO_START_ANGLE, PI, weight)
	var radius: float = lerpf(INTRO_START_RADIUS, chase_distance, weight)
	var height: float = lerpf(INTRO_START_HEIGHT, chase_height, weight)
	return kart_position + flat_direction(kart_forward, angle) * radius + Vector3.UP * height


## Holds `hold_position` for the beat, then blends into a slow orbit that
## starts behind the kart and swings round its side.
static func finish_pose(kart_position: Vector3, kart_forward: Vector3, seconds: float, hold_position: Vector3) -> Vector3:
	if seconds <= FINISH_BEAT_SECONDS:
		return hold_position
	var orbit_seconds: float = seconds - FINISH_BEAT_SECONDS
	var angle: float = PI + FINISH_ORBIT_SPEED * orbit_seconds
	var orbit: Vector3 = kart_position + flat_direction(kart_forward, angle) * FINISH_ORBIT_RADIUS + Vector3.UP * FINISH_ORBIT_HEIGHT
	return hold_position.lerp(orbit, smoothstep(0.0, FINISH_BLEND_SECONDS, orbit_seconds))


## Horizontal unit direction `angle` radians around UP from `forward`
## (0 = ahead of the kart, PI = behind it).
static func flat_direction(forward: Vector3, angle: float) -> Vector3:
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat.length() < 0.001:
		flat = Vector3.FORWARD
	return flat.normalized().rotated(Vector3.UP, angle)
