class_name PhantomDecoy
extends TrapItem

## Fake pickup: inherits the mine's deterministic arming and spin-out contract.

const ROTATION_SPEED: float = 1.5


func _process(delta: float) -> void:
	$Mesh.rotate_y(ROTATION_SPEED * delta)
