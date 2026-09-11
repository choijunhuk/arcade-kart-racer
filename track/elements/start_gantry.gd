class_name StartGantry
extends Node3D

## Countdown-lit start/finish arch (Phase 17 v3 dressing). Purely reactive to
## `EventBus.countdown_tick`, not `RaceManager` directly, so `TrackDressing`
## can build one for any track without a hard dependency on race wiring; a
## sandbox snapshot with no active countdown simply keeps the idle amber row.

const LIGHT_COUNT: int = 5
const IDLE_COLOR: Color = Color(0.55, 0.46, 0.22)
const READY_COLOR: Color = Color(0.95, 0.15, 0.08)
const GO_COLOR: Color = Color(0.15, 0.95, 0.25)
const LIT_ENERGY: float = 3.2
const IDLE_ENERGY: float = 0.7

var _materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	EventBus.countdown_tick.connect(_on_tick)


## Adds `LIGHT_COUNT` emissive bulbs spanning the header beam, `width` wide.
func build_lights(width: float) -> void:
	for index: int in range(LIGHT_COUNT):
		var shape: SphereMesh = SphereMesh.new()
		shape.radius = 0.22
		shape.height = 0.44
		var paint: StandardMaterial3D = PrimitiveArt.material(IDLE_COLOR, true)
		paint.emission_energy_multiplier = IDLE_ENERGY
		var bulb: MeshInstance3D = MeshInstance3D.new()
		bulb.name = "Bulb%d" % index
		bulb.mesh = shape
		bulb.material_override = paint
		bulb.position = Vector3(-width * 0.5 + width * (float(index) + 0.5) / float(LIGHT_COUNT), 4.6, 0.0)
		add_child(bulb)
		_materials.append(paint)


## Builds the sequential red row toward GO, then flashes every bulb green.
func _on_tick(value: int) -> void:
	var go: bool = value <= 0
	var lit_count: int = LIGHT_COUNT if go else clampi(LIGHT_COUNT - value + 1, 0, LIGHT_COUNT)
	for index: int in range(_materials.size()):
		var lit: bool = index < lit_count
		_materials[index].emission = (GO_COLOR if go else READY_COLOR) if lit else IDLE_COLOR
		_materials[index].emission_energy_multiplier = LIT_ENERGY if lit else IDLE_ENERGY
