class_name StartGrid
extends RefCounted

## Generates a staggered 2-column starting-grid layout from a single anchor
## transform, for tracks authored with fewer than the required grid slots
## (spec §15.2: StartGrid Marker3D x N, slot 1 = pole position).

const ROW_SPACING: float = 3.5
const COLUMN_OFFSET: float = 2.2


## Returns `count` grid transforms behind `anchor`, staggered left/right,
## sharing `anchor`'s orientation.
static func generate(anchor: Transform3D, count: int) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var forward: Vector3 = -anchor.basis.z
	var right: Vector3 = anchor.basis.x
	for index: int in range(count):
		var row: int = index / 2
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var offset: Vector3 = -forward * (ROW_SPACING * float(row)) + right * (COLUMN_OFFSET * side)
		result.append(Transform3D(anchor.basis, anchor.origin + offset))
	return result
